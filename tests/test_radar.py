from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).parents[1] / "scripts" / "radar.py"
SPEC = importlib.util.spec_from_file_location("radar", SCRIPT)
assert SPEC and SPEC.loader
radar = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(radar)


class ParseSsTests(unittest.TestCase):
    def test_groups_ipv4_and_ipv6_bindings(self) -> None:
        raw = "\n".join(
            [
                'LISTEN 0 511 127.0.0.1:5173 0.0.0.0:* users:(("node",pid=410,fd=22))',
                'LISTEN 0 511 [::]:5173 [::]:* users:(("node",pid=410,fd=23))',
            ]
        )
        self.assertEqual(
            radar.parse_ss(raw),
            [
                {
                    "pid": 410,
                    "port": 5173,
                    "process": "node",
                    "addresses": ["127.0.0.1", "::"],
                }
            ],
        )

    def test_ignores_system_listener_without_pid(self) -> None:
        raw = "LISTEN 0 4096 127.0.0.53%lo:53 0.0.0.0:*"
        self.assertEqual(radar.parse_ss(raw), [])


class ReachabilityTests(unittest.TestCase):
    def test_wildcard_uses_default_route_address(self) -> None:
        self.assertEqual(radar.lan_host_for(["0.0.0.0"], "192.168.1.42"), "192.168.1.42")

    def test_loopback_is_not_lan_reachable(self) -> None:
        self.assertEqual(radar.lan_host_for(["127.0.0.1", "::1"], "192.168.1.42"), "")

    def test_specific_lan_binding_is_used(self) -> None:
        self.assertEqual(radar.lan_host_for(["10.0.0.8"], "192.168.1.42"), "10.0.0.8")


class FrameworkTests(unittest.TestCase):
    def test_prefers_sveltekit_over_vite(self) -> None:
        package = {"devDependencies": {"vite": "latest", "@sveltejs/kit": "latest"}}
        self.assertEqual(radar.framework_for(None, "node vite", package), ("SvelteKit", "svelte"))

    def test_reads_project_name(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "package.json").write_text(json.dumps({"name": "betterat-web"}))
            package = radar.load_package(root)
            self.assertEqual(radar.project_name(root, package, "node"), "betterat-web")


if __name__ == "__main__":
    unittest.main()
