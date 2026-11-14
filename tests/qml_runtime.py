"""Isolated Quickshell execution shared by native test entry points."""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


REPO = Path(__file__).resolve().parent.parent
QUICKSHELL = shutil.which("quickshell")
OMARCHY_SHELL = Path(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy")) / "shell"
RUNTIME_ERRORS = re.compile(r"TypeError|ReferenceError|Binding loop|Unable to assign|Required property")


class QmlRuntime:
    def __enter__(self):
        self.directory = tempfile.TemporaryDirectory(prefix="localhost-qml-")
        self.root = Path(self.directory.name)
        self.add_import("Plugin", REPO)
        self.runtime = self.root / "runtime"
        self.runtime.mkdir(mode=0o700)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="",
                        QT_QUICK_BACKEND="software", XDG_RUNTIME_DIR=str(self.runtime))
        self.env.pop("WAYLAND_DISPLAY", None)
        self.env.pop("DISPLAY", None)
        self.env["PATH"] = str(self.bin) + os.pathsep + self.env["PATH"]
        return self

    def __exit__(self, *_exc):
        self.directory.cleanup()

    def add_import(self, name, path):
        (self.root / name).symlink_to(path, target_is_directory=True)

    def add_omarchy_imports(self, *, ui_overrides=None):
        self.add_import("Commons", OMARCHY_SHELL / "Commons")
        if not ui_overrides:
            self.add_import("Ui", OMARCHY_SHELL / "Ui")
            return
        ui = self.root / "Ui"
        ui.mkdir()
        for path in (OMARCHY_SHELL / "Ui").iterdir():
            source = ui_overrides.get(path.name, path)
            (ui / path.name).symlink_to(source, target_is_directory=source.is_dir())

    def command(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/sh\n" + body)
        path.chmod(0o755)

    def run(self, source=None, *, timeout=15):
        if source is not None:
            (self.root / "shell.qml").write_text(source)
        return subprocess.run([QUICKSHELL, "-p", str(self.root), "--no-color"],
                              env=self.env, capture_output=True, text=True, timeout=timeout)


def output_of(result):
    return result.stdout + result.stderr


def result_payload(output, prefix):
    matches = re.findall(re.escape(prefix) + r" (\{[^\n]+\})", output)
    if len(matches) != 1:
        raise AssertionError(f"Expected exactly one {prefix} result:\n{output}")
    return json.loads(matches[0])


def check_test_result(result, prefix, expected):
    output = output_of(result)
    if result.returncode or RUNTIME_ERRORS.search(output):
        raise AssertionError(output)
    summary = result_payload(output, prefix)
    if summary != {"tests": expected, "failed": 0, "skipped": 0}:
        raise AssertionError(output)
    return output
