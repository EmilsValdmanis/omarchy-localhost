import json
from pathlib import Path
import tempfile
import unittest

from project_metadata import MAX_MANIFEST_BYTES, ProjectInspector


class ProjectMetadataTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.inspector = ProjectInspector()

    def tearDown(self):
        self.temp.cleanup()

    def package(self, directory, payload):
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "package.json").write_text(json.dumps(payload))

    def repository(self, directory):
        (directory / ".git").mkdir()
        (directory / ".git/HEAD").write_text("ref: refs/heads/main\n")

    def test_pnpm_siblings_share_root_but_keep_their_package_metadata(self):
        (self.root / "pnpm-workspace.yaml").write_text("packages:\n  - apps/*\n")
        self.package(self.root / "apps/web", {"name": "@atlas/web", "dependencies": {"next": "16", "react": "19"}})
        self.package(self.root / "apps/api", {"name": "@atlas/api", "dependencies": {"hono": "4"}})
        web = self.inspector.inspect(str(self.root / "apps/web"))
        api = self.inspector.inspect(str(self.root / "apps/api"))
        self.assertEqual(web["root"], api["root"])
        self.assertEqual(web["root"], str(self.root))
        self.assertEqual(web["name"], "@atlas/web")
        self.assertEqual(web["relativePath"], "apps/web")
        self.assertEqual(api["dependencies"], ["hono"])

    def test_package_workspaces_and_subdirectories(self):
        self.package(self.root, {"workspaces": ["packages/*"]})
        app = self.root / "packages/site"
        self.package(app, {"name": "site"})
        (app / "src").mkdir()
        project = self.inspector.inspect(str(app / "src"))
        self.assertEqual(project["root"], str(self.root))
        self.assertEqual(project["relativePath"], "packages/site")

    def test_nested_git_repository_is_a_group_boundary(self):
        self.repository(self.root)
        self.package(self.root, {"workspaces": ["apps/*"]})
        nested = self.root / "apps/vendor"
        self.package(nested, {"name": "vendor"})
        (nested / ".git").write_text("gitdir: /unused/worktree")
        self.assertEqual(self.inspector.inspect(str(nested))["root"], str(nested))

    def test_git_root_groups_polyglot_apps_without_workspace_configuration(self):
        self.repository(self.root)
        api = self.root / "services/api"
        api.mkdir(parents=True)
        (api / "pyproject.toml").write_text('[project]\nname="api"\ndependencies=["fastapi>=0.100", "uvicorn[standard]"]\n')
        project = self.inspector.inspect(str(api))
        self.assertEqual(project["root"], str(self.root))
        self.assertEqual(project["name"], "api")
        self.assertEqual(project["dependencies"], ["fastapi", "uvicorn"])

    def test_identical_folder_names_in_different_repositories_stay_separate(self):
        roots = []
        for name in ("one", "two"):
            repo = self.root / name
            repo.mkdir()
            self.repository(repo)
            self.package(repo / "apps/api", {"name": "api"})
            roots.append(self.inspector.inspect(str(repo / "apps/api"))["root"])
        self.assertNotEqual(*roots)

    def test_malformed_and_oversized_manifests_do_not_break_discovery(self):
        (self.root / "package.json").write_text("{broken")
        (self.root / "pyproject.toml").write_text("x" * (MAX_MANIFEST_BYTES + 1))
        project = self.inspector.inspect(str(self.root))
        self.assertEqual(project["dependencies"], [])
        self.assertEqual(project["root"], str(self.root))

    def test_batch_cache_and_next_scan_observe_metadata_changes(self):
        self.package(self.root, {"name": "first"})
        first = self.inspector.inspect(str(self.root))
        self.package(self.root, {"name": "second"})
        self.assertIs(self.inspector.inspect(str(self.root)), first)
        self.assertEqual(ProjectInspector().inspect(str(self.root))["name"], "second")

    def test_symlinks_resolve_to_the_same_project_and_missing_paths_are_ignored(self):
        app = self.root / "app"
        self.package(app, {"name": "app"})
        (self.root / "alias").symlink_to(app, target_is_directory=True)
        self.assertEqual(self.inspector.inspect(str(app)), self.inspector.inspect(str(self.root / "alias")))
        self.assertEqual(self.inspector.inspect("relative/path"), {})
        self.assertEqual(self.inspector.inspect(str(self.root / "missing")), {})


if __name__ == "__main__":
    unittest.main()
