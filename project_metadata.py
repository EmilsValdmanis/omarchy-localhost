"""Read project identity without running project code or walking directory trees."""

from __future__ import annotations

import json
from pathlib import Path
import re
import tomllib

MAX_MANIFEST_BYTES = 256 * 1024
MAX_ANCESTORS = 24


def git_line(path: Path) -> str:
    """Read one small Git metadata file, ignoring missing or malformed values."""
    try:
        if path.is_file():
            with path.open("rb") as stream:
                raw = stream.read(8193)
            if len(raw) <= 8192:
                value = raw.decode().rstrip("\r\n")
                if value.isprintable():
                    return value
    except (OSError, UnicodeError):
        pass
    return ""


def git_directory(root: Path) -> Path | None:
    marker = root / ".git"
    if marker.is_dir():
        return marker if (marker / "HEAD").is_file() else None
    pointer = git_line(marker)
    if pointer.startswith("gitdir: ") and pointer[8:]:
        return root / pointer[8:]
    return None


def worktree_metadata(directory: Path) -> tuple[str, str]:
    head = git_line(directory / "HEAD")
    if not head:
        return "", ""
    common = git_line(directory / "commondir")
    try:
        repository = (directory / common).resolve(strict=True)
    except (OSError, RuntimeError):
        return "", ""
    branch = head.removeprefix("ref: refs/heads/") if head.startswith("ref: refs/heads/") else ""
    return str(repository), branch


class ProjectInspector:
    """One cache per discovery batch, shared by processes and Compose projects."""

    def __init__(self):
        self.projects: dict[str, dict] = {}
        self.manifests: dict[Path, dict] = {}
        self.worktrees: dict[Path, tuple[str, str]] = {}

    def manifest(self, path: Path) -> dict:
        if path not in self.manifests:
            try:
                if not path.is_file() or path.stat().st_size > MAX_MANIFEST_BYTES:
                    raise ValueError("not a small manifest")
                with path.open("rb") as stream:
                    raw = stream.read(MAX_MANIFEST_BYTES + 1)
                if len(raw) > MAX_MANIFEST_BYTES:
                    raise ValueError("manifest grew while reading")
                value = tomllib.loads(raw.decode()) if path.suffix == ".toml" else json.loads(raw)
                self.manifests[path] = value if isinstance(value, dict) else {}
            except (OSError, ValueError, RecursionError):
                self.manifests[path] = {}
        return self.manifests[path]

    def inspect(self, cwd: str) -> dict:
        if not cwd or not Path(cwd).is_absolute():
            return {}
        try:
            directory = Path(cwd).resolve(strict=True)
        except (OSError, RuntimeError):
            return {}
        if not directory.is_dir():
            return {}
        key = str(directory)
        if key in self.projects:
            return self.projects[key]

        package_dir = None
        package = {}
        python = {}
        workspace = None
        repository = None
        git = None
        for depth, parent in enumerate((directory, *directory.parents)):
            if depth >= MAX_ANCESTORS or parent == Path(parent.anchor):
                break
            node_manifest = self.manifest(parent / "package.json")
            py_manifest = self.manifest(parent / "pyproject.toml")
            if package_dir is None and (node_manifest or py_manifest):
                package_dir, package, python = parent, node_manifest, py_manifest
            if ((parent / "pnpm-workspace.yaml").is_file()
                    or node_manifest.get("workspaces")
                    or (parent / "lerna.json").is_file()
                    or self.manifest(parent / "Cargo.toml").get("workspace") is not None
                    or (parent / "go.work").is_file()):
                workspace = parent
            # Git worktrees use a .git file. Nested repositories are boundaries.
            git = git_directory(parent)
            if git is not None:
                repository = parent
                break

        root = repository or workspace or package_dir or directory
        project_dir = package_dir or directory
        dependencies = set()
        for section in ("dependencies", "devDependencies", "peerDependencies"):
            values = package.get(section, {})
            if isinstance(values, dict):
                dependencies.update(values)
        py_project = python.get("project", {})
        if not isinstance(py_project, dict):
            py_project = {}
        py_dependencies = py_project.get("dependencies", [])
        if isinstance(py_dependencies, list):
            for dependency in py_dependencies:
                match = re.match(r"[\w.-]+", str(dependency))
                if match:
                    dependencies.add(match[0].lower().replace("_", "-"))
        tools = python.get("tool", {})
        poetry = tools.get("poetry", {}) if isinstance(tools, dict) else {}
        if isinstance(poetry, dict) and isinstance(poetry.get("dependencies"), dict):
            dependencies.update(str(name).lower() for name in poetry["dependencies"])

        value = {
            "root": str(root),
            "name": str(package.get("name") or py_project.get("name") or project_dir.name)[:160],
            "relativePath": str(project_dir.relative_to(root)) if project_dir.is_relative_to(root) else ".",
            "dependencies": sorted(dependencies)[:2048],
        }
        if git is not None:
            if git not in self.worktrees:
                self.worktrees[git] = worktree_metadata(git)
            value["gitCommonDir"], value["gitBranch"] = self.worktrees[git]
        self.projects[key] = value
        return value
