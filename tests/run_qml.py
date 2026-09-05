#!/usr/bin/env python3
"""Run Qt Quick tests inside Quickshell with the installed, real Omarchy UI.

Quickshell statically links its QML plugins, so qmltestrunner cannot load them.
The staging directory provides qs imports without installing/enabling the plugin.
"""

import argparse
import json
import os
from pathlib import Path
import re
import selectors
import shutil
import subprocess
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wayland-smoke", action="store_true", help="also load both hidden entry points on the current Wayland display")
    parser.add_argument("--previews", action="store_true", help="regenerate the combined README/marketplace preview from the actual components")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parent.parent
    shell = Path(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy")) / "shell"
    if not shutil.which("quickshell") or not (shell / "Ui").is_dir():
        sys.exit("UI tests require Quickshell and the Omarchy shell")
    artifacts = Path(os.environ.get("LOCALHOST_TEST_ARTIFACTS", "/tmp/localhost-test-artifacts"))
    artifacts.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="localhost-qml-") as directory:
        stage = Path(directory)
        for module in ("Commons", "Ui"):
            (stage / module).symlink_to(shell / module, target_is_directory=True)
        (stage / "Plugin").symlink_to(repo, target_is_directory=True)
        shutil.copyfile(repo / "tests/qml/shell.qml", stage / "shell.qml")
        runtime = stage / "runtime"
        runtime.mkdir(mode=0o700)
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="",
                   QT_QUICK_BACKEND="software", XDG_RUNTIME_DIR=str(runtime),
                   LOCALHOST_TEST_ARTIFACTS=str(artifacts.resolve()))
        env.pop("WAYLAND_DISPLAY", None)
        env.pop("DISPLAY", None)
        if args.previews:
            wallpaper = shell.parent / "themes/everforest/backgrounds/1-tree-tops.jpg"
            if not wallpaper.is_file():
                sys.exit(f"Preview rendering requires the Everforest wallpaper: {wallpaper}")
            destination = Path(os.environ.get("LOCALHOST_PREVIEW_DIR", str(repo))).resolve()
            destination.mkdir(parents=True, exist_ok=True)
            env["LOCALHOST_PREVIEW_DIR"] = str(destination)
            env["LOCALHOST_PREVIEW_WALLPAPER"] = wallpaper.resolve().as_uri()
            shutil.copyfile(repo / "tests/qml/previews.qml", stage / "shell.qml")
            preview = subprocess.run(["quickshell", "-p", str(stage), "--no-color"],
                                     env=env, capture_output=True, text=True, timeout=30)
            output = preview.stdout + preview.stderr
            print(output, end="")
            if preview.returncode or 'LOCALHOST_PREVIEWS {"failed":0}' not in output or re.search(r"TypeError|ReferenceError|Binding loop|Unable to assign", output):
                sys.exit("Preview rendering failed")
            print(f"Updated {destination / 'preview.png'}")
            return
        fixture = subprocess.Popen([sys.executable, str(repo / "tests/http_fixture.py")],
                                   stdout=subprocess.PIPE, text=True, cwd=repo)
        try:
            with selectors.DefaultSelector() as ready:
                ready.register(fixture.stdout, selectors.EVENT_READ)
                if not ready.select(timeout=5):
                    sys.exit("HTTP fixture did not start")
            try:
                ports = json.loads(fixture.stdout.readline())
            except ValueError:
                sys.exit("HTTP fixture could not bind to loopback")
            env.update(LOCALHOST_TEST_PORT=str(ports[0]), LOCALHOST_TEST_SECOND_PORT=str(ports[1]),
                       LOCALHOST_TEST_PID=str(fixture.pid), LOCALHOST_TEST_PROJECT_ROOT=str(repo))
            try:
                result = subprocess.run(["quickshell", "-p", str(stage), "--no-color"],
                                        env=env, capture_output=True, text=True, timeout=90)
            except subprocess.TimeoutExpired as error:
                print(error.stdout or b"")
                sys.exit("UI tests timed out")
        finally:
            if fixture.poll() is None:
                fixture.terminate()
            fixture.wait(timeout=5)
            fixture.stdout.close()
        output = result.stdout + result.stderr
        (artifacts / "qml.log").write_text(output)
        print(output, end="")
        summaries = re.findall(r"LOCALHOST_RESULT (\{[^\n]+\})", output)
        if result.returncode or len(summaries) != 1:
            sys.exit("Quickshell did not complete the UI tests")
        summary = json.loads(summaries[0])
        expected = len(re.findall(r"function test_\w+\(", (repo / "tests/qml/shell.qml").read_text()))
        if summary["failed"] or summary["skipped"] or summary["tests"] != expected:
            sys.exit("UI tests failed or did not all execute")
        if re.search(r"(?:TypeError|ReferenceError|Binding loop|Unable to assign|Required property)", output):
            sys.exit("QML runtime errors detected")
        print(f"Passed {summary['tests']} Quickshell UI tests. Artifacts: {artifacts}")
        if args.wayland_smoke:
            display = os.environ.get("WAYLAND_DISPLAY", "")
            if not display:
                sys.exit("--wayland-smoke requires WAYLAND_DISPLAY")
            if not os.path.isabs(display):
                display = str(Path(os.environ["XDG_RUNTIME_DIR"]) / display)
            shutil.copyfile(repo / "tests/qml/wayland.qml", stage / "shell.qml")
            env.update(QT_QPA_PLATFORM="wayland", WAYLAND_DISPLAY=display)
            smoke = subprocess.run(["quickshell", "-p", str(stage), "--no-color"],
                                   env=env, capture_output=True, text=True, timeout=15)
            output = smoke.stdout + smoke.stderr
            (artifacts / "wayland.log").write_text(output)
            print(output, end="")
            if smoke.returncode or "LOCALHOST_WAYLAND_SMOKE emils.localhost false" not in output or re.search(r"\b(?:WARN|ERROR)\b", output):
                sys.exit("Wayland entry-point smoke test failed")
            print("Both plugin entry points loaded on Wayland")


if __name__ == "__main__":
    main()
