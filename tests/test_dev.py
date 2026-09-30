import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


@unittest.skipUnless(shutil.which("jq"), "development watcher requires jq")
class DevelopmentWatcherTests(unittest.TestCase):
    def run_watcher(self, plugins):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            commands = root / "bin"
            commands.mkdir()
            log = root / "commands.log"
            stubs = {
                "omarchy": 'echo "$*" >> "$WATCHER_TEST_LOG"\nif [[ "$*" == "plugin list --json" ]]; then echo "$WATCHER_TEST_PLUGINS"; fi\n',
                "omarchy-shell": "exit 0\n",
                "rsync": "exit 0\n",
                "inotifywait": "exit 0\n",
                "sleep": "exit 0\n",
            }
            for name, body in stubs.items():
                path = commands / name
                path.write_text("#!/usr/bin/env bash\n" + body)
                path.chmod(0o755)
            environment = dict(os.environ, PATH=str(commands) + os.pathsep + os.environ["PATH"],
                               XDG_CONFIG_HOME=str(root / "config"), WATCHER_TEST_LOG=str(log),
                               WATCHER_TEST_PLUGINS=json.dumps(plugins))
            result = subprocess.run([str(Path(__file__).resolve().parent.parent / "dev")],
                                    env=environment, capture_output=True, text=True, timeout=10)
            return result, log.read_text()

    def test_disabled_plugin_is_found_and_enabled(self):
        result, commands = self.run_watcher([{"id": "emils.localhost", "enabled": False}])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("plugin enable emils.localhost\n", commands)
        self.assertIn("Watching", result.stdout)

    def test_enabled_plugin_is_found_without_enabling_again(self):
        result, commands = self.run_watcher([{"id": "emils.localhost", "enabled": True}])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("plugin enable", commands)

    def test_absent_plugin_is_reported_separately(self):
        result, commands = self.run_watcher([])
        self.assertEqual(result.returncode, 1)
        self.assertIn("did not discover emils.localhost", result.stderr)
        self.assertNotIn("plugin enable", commands)
