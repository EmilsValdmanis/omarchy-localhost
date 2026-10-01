import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


@unittest.skipUnless(shutil.which("jq"), "development watcher requires jq")
class DevelopmentWatcherTests(unittest.TestCase):
    def run_watcher(self, plugins, *, synced_paths=(), events=(), restart_status=0, sync_status=0):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            commands = root / "bin"
            commands.mkdir()
            log = root / "commands.log"
            stubs = {
                "omarchy": 'echo "$*" >> "$WATCHER_TEST_LOG"\nif [[ "$*" == "plugin list --json" ]]; then echo "$WATCHER_TEST_PLUGINS"; fi\nif [[ "$*" == "restart shell" ]]; then exit "$WATCHER_TEST_RESTART_STATUS"; fi\n',
                "omarchy-shell": 'echo "shell-ipc $*" >> "$WATCHER_TEST_LOG"\n',
                "rsync": 'if [[ -f "$WATCHER_TEST_LOG.synced" ]]; then printf "%s\\n" "$WATCHER_TEST_SYNCED_PATHS"; fi\ntouch "$WATCHER_TEST_LOG.synced"\nexit "$WATCHER_TEST_SYNC_STATUS"\n',
                "inotifywait": 'if [[ -n "$WATCHER_TEST_EVENTS" ]]; then printf "%s\\n" "$WATCHER_TEST_EVENTS"; fi\n',
                "sleep": "exit 0\n",
            }
            for name, body in stubs.items():
                path = commands / name
                path.write_text("#!/usr/bin/env bash\n" + body)
                path.chmod(0o755)
            environment = dict(os.environ, PATH=str(commands) + os.pathsep + os.environ["PATH"],
                               XDG_CONFIG_HOME=str(root / "config"), WATCHER_TEST_LOG=str(log),
                               WATCHER_TEST_PLUGINS=json.dumps(plugins),
                               WATCHER_TEST_SYNCED_PATHS="\n".join(synced_paths),
                               WATCHER_TEST_EVENTS="\n".join(str(Path(__file__).resolve().parent.parent / path) for path in events),
                               WATCHER_TEST_RESTART_STATUS=str(restart_status),
                               WATCHER_TEST_SYNC_STATUS=str(sync_status))
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
        self.assertIn("shell-ipc shell ping\n", commands)
        self.assertEqual(commands.count("restart shell\n"), 1)
        self.assertNotIn("rescanPlugins", commands)

    def test_cached_components_are_replaced_after_source_changes(self):
        for path in ("Widget.qml", "qml/ServerPanel.qml", "qml/RadarModel.js", "manifest.json"):
            with self.subTest(path=path):
                result, commands = self.run_watcher(
                    [{"id": "emils.localhost", "enabled": True}], synced_paths=[path], events=[path])
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(commands.count("restart shell\n"), 2)

    def test_helper_changes_do_not_restart_the_shell_again(self):
        result, commands = self.run_watcher(
            [{"id": "emils.localhost", "enabled": True}],
            synced_paths=["localhost_helper.py"], events=["localhost_helper.py"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(commands.count("restart shell\n"), 1)
        self.assertIn("Synced localhost_helper.py", result.stdout)

    def test_save_burst_causes_one_restart(self):
        paths = ["Widget.qml", "qml/ServerPanel.qml", "qml/RadarModel.js"]
        result, commands = self.run_watcher(
            [{"id": "emils.localhost", "enabled": True}], synced_paths=paths, events=paths)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(commands.count("restart shell\n"), 2)
        self.assertEqual(result.stdout.count("Synced "), 1)

    def test_unchanged_files_do_not_restart_the_shell_again(self):
        result, commands = self.run_watcher(
            [{"id": "emils.localhost", "enabled": True}], events=["Widget.qml"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(commands.count("restart shell\n"), 1)

    def test_failed_restart_does_not_claim_the_plugin_is_live(self):
        result, commands = self.run_watcher(
            [{"id": "emils.localhost", "enabled": True}], restart_status=1)
        self.assertEqual(result.returncode, 1)
        self.assertIn("the copied plugin may not be live", result.stderr)
        self.assertNotIn("Watching", result.stdout)

    def test_failed_sync_does_not_restart_the_shell(self):
        result, commands = self.run_watcher(
            [{"id": "emils.localhost", "enabled": True}], sync_status=1)
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("restart shell", commands)
        self.assertNotIn("Watching", result.stdout)

    def test_absent_plugin_is_reported_separately(self):
        result, commands = self.run_watcher([])
        self.assertEqual(result.returncode, 1)
        self.assertIn("did not discover emils.localhost", result.stderr)
        self.assertNotIn("plugin enable", commands)
