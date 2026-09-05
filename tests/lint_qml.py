"""Qt 6 lint with narrow allowances for upstream Omarchy/Quickshell metadata.

The runtime tests exercise these dynamic properties with the real components.
All other warnings, including layout, syntax and unresolved imports, fail.
"""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


def upstream_metadata(warning, source):
    if warning["id"] == "signal-handler-parameters":
        return warning["message"].startswith("Type QProcess::ExitStatus of parameter exitStatus")
    if warning["id"] == "uncreatable-type":
        # The Wayland backend registers this type inside Quickshell at startup.
        return warning["message"] == "Type PanelWindow is not creatable."
    if warning["id"] != "missing-property":
        return False
    member = re.fullmatch(r'Member "(\w+)" not found on type "QObject"', warning["message"])
    if not member:
        return False
    name = member[1]
    tokens = {
        "Style.font": {"family", "heading", "title", "body", "bodySmall", "caption"},
        "Style.spacing": {"hairline"},
        "Color.popups": {"text", "background"},
        "root.bar": {"background"},
    }
    return any(name in names and f"{prefix}.{name}" in source for prefix, names in tokens.items())


def main():
    repo = Path(__file__).resolve().parent.parent
    shell = Path(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy")) / "shell"
    lint = os.environ.get("QMLLINT", "/usr/lib/qt6/bin/qmllint")
    if not shutil.which(lint) or not (shell / "Ui").is_dir():
        sys.exit("Lint requires Qt 6 qmllint and the Omarchy shell (QMLLINT / OMARCHY_PATH)")
    with tempfile.TemporaryDirectory(prefix="localhost-lint-") as directory:
        imports = Path(directory) / "qs"
        imports.mkdir()
        for module in ("Commons", "Ui"):
            (imports / module).symlink_to(shell / module, target_is_directory=True)
        files = sorted(repo.glob("*.qml"))
        result = subprocess.run([lint, "--ignore-settings", "--json", "-", "-I", directory, *map(str, files)],
                                capture_output=True, text=True, timeout=30)
        try:
            reports = json.loads(result.stdout)["files"]
        except (ValueError, KeyError):
            sys.exit(result.stderr or "qmllint did not return a report")
        if len(reports) != len(files):
            sys.exit("qmllint did not check all QML files")
        failures = 0
        known = 0
        for report in reports:
            lines = Path(report["filename"]).read_text().splitlines()
            for warning in report["warnings"]:
                if warning["type"] not in {"warning", "error", "critical"}:
                    continue
                line = warning.get("line", 0)
                source = lines[line - 1] if 0 < line <= len(lines) else ""
                if warning["type"] == "warning" and upstream_metadata(warning, source):
                    known += 1
                    continue
                failures += 1
                print(f"{report['filename']}:{line}: {warning['message']} [{warning['id']}]")
        if failures or result.returncode not in (0, 255):
            sys.exit("Qt 6 QML lint failed")
        print(f"Qt 6 lint checked {len(files)} files; {known} known upstream metadata warnings allowed")


if __name__ == "__main__":
    main()
