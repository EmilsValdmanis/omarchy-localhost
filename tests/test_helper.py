import os
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

import localhost_helper as helper


class ProcessInspectionTests(unittest.TestCase):
    def test_inspects_owned_process_metadata_and_identity(self):
        process = helper.inspect_process(os.getpid(), os.geteuid())

        self.assertIsNotNone(process)
        self.assertEqual(process["pid"], os.getpid())
        self.assertEqual(process["uid"], os.geteuid())
        self.assertGreater(process["startTime"], 0)
        self.assertGreater(process["memoryBytes"], 0)
        self.assertTrue(process["command"])
        self.assertTrue(process["cwd"])

    def test_ignores_process_owned_by_another_uid(self):
        self.assertIsNone(helper.inspect_process(os.getpid(), os.geteuid() + 1))

    def test_parses_unique_positive_process_ids(self):
        self.assertEqual(helper.comma_separated_pids("12,bad,0,12,34"), [12, 12, 34])
        inspected = helper.inspect_processes([os.getpid(), os.getpid()], os.geteuid())
        self.assertEqual(len(inspected), 1)

    def test_recovery_preserves_empty_arguments_and_non_utf8_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "cmdline"
            raw = b"node\0server.js\0\0last\xff\0"
            path.write_bytes(raw)
            arguments = helper.read_null_separated(path, errors="surrogateescape")
            self.assertEqual(arguments[:3], ["node", "server.js", ""])
            self.assertEqual(b"\0".join(value.encode(errors="surrogateescape") for value in arguments) + b"\0", raw)

    def test_wildcard_readiness_uses_loopback_instead_of_an_unowned_url_host(self):
        with mock.patch.object(helper, "listening_endpoints", return_value={("0.0.0.0", 3000)}):
            self.assertEqual(helper.owned_probe_host(Path("/proc/fixture"), ("http", "192.0.2.123", 3000)), "127.0.0.1")
        with mock.patch.object(helper, "listening_endpoints", return_value={("::", 3000)}):
            self.assertEqual(helper.owned_probe_host(Path("/proc/fixture"), ("https", "2001:db8::123", 3000)), "::1")

    def test_parses_docker_memory_units(self):
        self.assertEqual(helper.parse_docker_memory("1.5GiB / 4GiB"), 1610612736)
        self.assertEqual(helper.parse_docker_memory("100MiB / 4GiB"), 104857600)
        self.assertEqual(helper.parse_docker_memory("12.5MB / 1GB"), 12500000)
        self.assertEqual(helper.parse_docker_memory("unavailable"), -1)

    def test_reads_total_and_available_system_ram(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "meminfo"
            path.write_text("MemTotal:       16384 kB\nMemFree: 1024 kB\nMemAvailable: 4096 kB\n")
            self.assertEqual(helper.read_system_memory(path), {
                "totalBytes": 16384 * 1024, "availableBytes": 4096 * 1024
            })
            path.write_text("MemTotal: 10 kB\nMemAvailable: 11 kB\n")
            self.assertEqual(helper.read_system_memory(path), {
                "totalBytes": -1, "availableBytes": -1
            })

    def test_container_stats_are_batched_and_fail_open(self):
        result = subprocess.CompletedProcess([], 0, "abc123def456\t24MiB / 1GiB\n", "")
        with mock.patch.object(helper.subprocess, "run", return_value=result) as run:
            self.assertEqual(helper.inspect_container_memory(["abc123def456", "abc123def456"]), {"abc123def456": 25165824})
            self.assertEqual(run.call_args.args[0][-1], "abc123def456")
        with mock.patch.object(helper.subprocess, "run", side_effect=subprocess.TimeoutExpired("docker", 3)):
            self.assertEqual(helper.inspect_container_memory(["abc123def456"]), {})

        ids = [f"{index:012x}" for index in range(150)]
        def stats_for_batch(command, **_kwargs):
            output = "".join(f"{container_id}\t1MiB / 2GiB\n" for container_id in command[5:])
            return subprocess.CompletedProcess(command, 0, output, "")

        with mock.patch.object(helper.subprocess, "run", side_effect=stats_for_batch) as run:
            memory = helper.inspect_container_memory(ids)
            self.assertEqual(len(memory), 150)
            self.assertEqual(memory[ids[-1]], 1048576)
            self.assertEqual([len(call.args[0]) - 5 for call in run.call_args_list], [128, 22])


class ProcessActionTests(unittest.TestCase):
    def setUp(self):
        self.child = subprocess.Popen(
            [sys.executable, "-c", "import time; time.sleep(60)"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        deadline = time.monotonic() + 2
        while not Path(f"/proc/{self.child.pid}/stat").exists():
            if time.monotonic() > deadline:
                self.fail("test child did not start")
            time.sleep(0.01)
        self.start_time = helper.read_process_stat(self.child.pid)[1]
        self.restarted = None
        self.state_directory = tempfile.TemporaryDirectory()

    def start_http_server(self):
        self.child.kill()
        self.child.wait(timeout=2)
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1", 0))
            self.port = reservation.getsockname()[1]
        self.script = Path(self.state_directory.name) / "server.py"
        self.script.write_text(
            "import sys\nfrom http.server import HTTPServer, BaseHTTPRequestHandler\n"
            "class Handler(BaseHTTPRequestHandler):\n"
            " def do_HEAD(self):\n  self.send_response(404)\n  self.end_headers()\n"
            "server = HTTPServer(('127.0.0.1', int(sys.argv[1])), Handler)\n"
            "print('ready', flush=True)\nserver.serve_forever()\n"
        )
        self.child = subprocess.Popen(
            [sys.executable, str(self.script), str(self.port)],
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            text=True,
        )
        self.assertEqual(self.child.stdout.readline().strip(), "ready")
        self.start_time = helper.read_process_stat(self.child.pid)[1]
        self.url = f"http://127.0.0.1:{self.port}"

    def tearDown(self):
        if self.child.poll() is None:
            self.child.kill()
        self.child.wait(timeout=2)
        if self.child.stdout:
            self.child.stdout.close()
        if self.restarted and self.restarted.poll() is None:
            self.restarted.kill()
        if self.restarted:
            self.restarted.wait(timeout=2)
        self.state_directory.cleanup()

    def test_rejects_stale_process_identity(self):
        with self.assertRaisesRegex(helper.LocalhostError, "process changed"):
            helper.signal_process(self.child.pid, self.start_time + 1)
        self.assertIsNone(self.child.poll())

    def test_signals_verified_user_owned_process(self):
        helper.signal_process(self.child.pid, self.start_time)
        self.child.wait(timeout=2)
        self.assertIsNotNone(self.child.returncode)

    def test_restarts_with_recovered_process_context(self):
        self.start_http_server()
        state_root = Path(self.state_directory.name) / "omarchy" / "localhost"
        state_root.mkdir(parents=True)
        for stamp in range(helper.MAX_RESTART_LOGS):
            (state_root / f"restart-{stamp:019d}.log").write_text("old log")

        with mock.patch.dict(os.environ, {"XDG_STATE_HOME": self.state_directory.name}):
            self.restarted, log_path = helper.restart_process(
                self.child.pid, self.start_time, self.url
            )
        self.child.wait(timeout=2)

        self.assertGreater(self.restarted.pid, 1)
        self.assertTrue(Path(f"/proc/{self.restarted.pid}").exists())
        self.assertTrue(log_path.parent.is_dir())
        self.assertEqual(len(list(state_root.glob("restart-*.log"))), helper.MAX_RESTART_LOGS)
        self.assertFalse((state_root / f"restart-{0:019d}.log").exists())
        self.assertEqual(log_path.stat().st_mode & 0o777, 0o600)
        self.assertIn(self.port, helper.listening_ports(Path(f"/proc/{self.restarted.pid}")))

    def test_log_directory_failure_preserves_original_server(self):
        self.start_http_server()
        blocked = Path(self.state_directory.name) / "blocked"
        blocked.write_text("a file cannot be a state directory")
        with mock.patch.dict(os.environ, {"XDG_STATE_HOME": str(blocked)}):
            with self.assertRaisesRegex(helper.LocalhostError, "prepare the restart log"):
                helper.restart_process(self.child.pid, self.start_time, self.url)
        self.assertIsNone(self.child.poll())
        self.assertIn(self.port, helper.listening_ports(Path(f"/proc/{self.child.pid}")))

    def test_log_open_failure_preserves_original_server(self):
        self.start_http_server()
        with mock.patch.dict(os.environ, {"XDG_STATE_HOME": self.state_directory.name}):
            with mock.patch.object(helper.os, "open", side_effect=PermissionError("unwritable log")):
                with self.assertRaisesRegex(helper.LocalhostError, "prepare the restart log"):
                    helper.restart_process(self.child.pid, self.start_time, self.url)
        self.assertIsNone(self.child.poll())

    def test_missing_entry_point_disables_restart_and_preserves_original(self):
        self.start_http_server()
        self.script.unlink()
        process = helper.inspect_process(self.child.pid, os.geteuid())
        self.assertFalse(process["restartAvailable"])
        with self.assertRaisesRegex(helper.LocalhostError, "entry point cannot be verified"):
            helper.restart_process(self.child.pid, self.start_time, self.url)
        self.assertIsNone(self.child.poll())

    @unittest.skipUnless(shutil.which("node"), "requires Node for the rewritten-title fixture")
    def test_rewritten_node_title_disables_restart_without_stopping_server(self):
        self.child.kill()
        self.child.wait(timeout=2)
        self.child = subprocess.Popen(
            ["node", "-e", "process.title = 'next-server (v15.0.0)'; console.log('ready'); setInterval(() => {}, 1000)"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
        )
        self.assertEqual(self.child.stdout.readline().strip(), "ready")
        self.start_time = helper.read_process_stat(self.child.pid)[1]
        process = helper.inspect_process(self.child.pid, os.geteuid())
        self.assertIn("next-server", process["command"])
        self.assertFalse(process["restartAvailable"])
        with self.assertRaisesRegex(helper.LocalhostError, "rewritten process title"):
            helper.restart_process(self.child.pid, self.start_time, "http://localhost:3000")
        self.assertIsNone(self.child.poll())

    def test_replacement_exit_is_reported_as_failure_with_log(self):
        self.start_http_server()
        self.script.write_text("import sys\nprint('startup failed', flush=True)\nsys.exit(7)\n")
        with mock.patch.dict(os.environ, {"XDG_STATE_HOME": self.state_directory.name}):
            with self.assertRaisesRegex(helper.LocalhostError, "replacement exited with status 7; see"):
                helper.restart_process(self.child.pid, self.start_time, self.url)
        self.child.wait(timeout=2)
        logs = list((Path(self.state_directory.name) / "omarchy" / "localhost").glob("restart-*.log"))
        self.assertEqual(len(logs), 1)
        self.assertIn("startup failed", logs[0].read_text())

    def test_invalid_readiness_url_preserves_original(self):
        for url in ("", "ftp://localhost:3000", "http://user:pass@localhost:3000", "http://localhost:3000/path", "http://localhost:0", "http://example.com:3000"):
            with self.assertRaisesRegex(helper.LocalhostError, "HTTP or HTTPS URL"):
                helper.restart_process(self.child.pid, self.start_time, url)
        self.assertIsNone(self.child.poll())

    def test_wrong_listening_address_preserves_original(self):
        self.start_http_server()
        with self.assertRaisesRegex(helper.LocalhostError, "original process no longer owns"):
            helper.restart_process(self.child.pid, self.start_time, f"http://127.0.0.2:{self.port}")
        self.assertIsNone(self.child.poll())

    def test_delayed_replacement_waits_for_http_readiness(self):
        self.start_http_server()
        self.script.write_text("import time\ntime.sleep(0.3)\n" + self.script.read_text())
        started_at = time.monotonic()
        with mock.patch.dict(os.environ, {"XDG_STATE_HOME": self.state_directory.name}):
            self.restarted, _log = helper.restart_process(self.child.pid, self.start_time, self.url)
        self.assertGreaterEqual(time.monotonic() - started_at, 0.5)

    def test_other_process_http_response_cannot_make_replacement_ready(self):
        self.start_http_server()
        self.restarted = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"])
        with self.assertRaisesRegex(helper.LocalhostError, "did not become HTTP-ready"):
            helper.wait_for_restart_ready(self.restarted, helper.restart_endpoint(self.url), Path("fixture.log"), timeout=0.2)

    def test_handle_is_acquired_before_verification_and_used_for_signal(self):
        events = []
        with mock.patch.object(helper.os, "pidfd_open", side_effect=lambda pid: events.append("open") or 1234), \
                mock.patch.object(helper, "verified_process_directory", side_effect=lambda *args: events.append("verify") or Path("/proc/fixture")), \
                mock.patch.object(helper.signal, "pidfd_send_signal", side_effect=lambda *args: events.append("signal")) as send, \
                mock.patch.object(helper.os, "kill") as kill, \
                mock.patch.object(helper.os, "close") as close:
            helper.signal_process(self.child.pid, self.start_time, force=True)
        self.assertEqual(events, ["open", "verify", "signal"])
        send.assert_called_once_with(1234, signal.SIGKILL)
        close.assert_called_once_with(1234)
        kill.assert_not_called()

    def test_handle_is_closed_when_identity_verification_fails(self):
        with mock.patch.object(helper.os, "pidfd_open", return_value=1234), \
                mock.patch.object(helper.os, "close") as close, \
                mock.patch.object(helper.signal, "pidfd_send_signal") as send:
            with self.assertRaisesRegex(helper.LocalhostError, "process changed"):
                helper.signal_process(self.child.pid, self.start_time + 1)
        close.assert_called_once_with(1234)
        send.assert_not_called()

    def test_unavailable_pidfd_fails_without_falling_back_to_pid_signal(self):
        with mock.patch.object(helper.os, "pidfd_open", side_effect=OSError("not supported")), \
                mock.patch.object(helper.os, "kill") as kill:
            with self.assertRaisesRegex(helper.LocalhostError, "process handle"):
                helper.signal_process(self.child.pid, self.start_time)
        kill.assert_not_called()
        self.assertIsNone(self.child.poll())

    def test_offers_force_stop_only_after_graceful_stop_fails(self):
        self.child.kill()
        self.child.wait(timeout=2)
        self.child = subprocess.Popen(
            [
                sys.executable,
                "-c",
                "import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); print('ready', flush=True); time.sleep(60)",
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        self.assertEqual(self.child.stdout.readline().strip(), "ready")
        self.start_time = helper.read_process_stat(self.child.pid)[1]

        with self.assertRaisesRegex(helper.LocalhostError, "did not stop cleanly"):
            helper.signal_process(self.child.pid, self.start_time)
        self.assertIsNone(self.child.poll())

        helper.signal_process(self.child.pid, self.start_time, force=True)
        self.child.wait(timeout=2)
        self.assertIsNotNone(self.child.returncode)


class RestartLogTests(unittest.TestCase):
    def test_prunes_old_restart_logs_keeping_the_newest(self):
        with tempfile.TemporaryDirectory() as directory:
            state_root = Path(directory)
            for stamp in range(15):
                (state_root / f"restart-{stamp:019d}.log").write_text("log")

            helper.prune_restart_logs(state_root)

            remaining = sorted(path.name for path in state_root.glob("restart-*.log"))
            self.assertEqual(len(remaining), helper.MAX_RESTART_LOGS)
            self.assertEqual(remaining[0], f"restart-{5:019d}.log")
            self.assertEqual(remaining[-1], f"restart-{14:019d}.log")

    def test_tolerates_a_missing_state_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            missing = Path(directory) / "omarchy" / "localhost"
            helper.prune_restart_logs(missing)
            self.assertFalse(missing.exists())


class DockerActionTests(unittest.TestCase):
    def test_rejects_invalid_container_id_before_running_docker(self):
        with mock.patch.object(helper, "run_command") as run:
            with self.assertRaisesRegex(helper.LocalhostError, "Invalid Docker"):
                helper.docker_action("not-a-container", "stop")
            run.assert_not_called()

    def test_verifies_container_before_stopping_it(self):
        container_id = "a" * 12
        responses = [
            subprocess.CompletedProcess([], 0, container_id + "f" * 52 + "\n", ""),
            subprocess.CompletedProcess([], 0, "", ""),
        ]
        with mock.patch.object(helper, "run_command", side_effect=responses) as run:
            helper.docker_action(container_id, "stop")

        self.assertEqual(run.call_args_list[0].args[0], ["docker", "ps", "-q", "--no-trunc"])
        self.assertEqual(
            run.call_args_list[1].args[0],
            ["docker", "stop", "--time", "10", container_id + "f" * 52],
        )

    def test_refuses_container_that_is_no_longer_running(self):
        with mock.patch.object(
            helper,
            "run_command",
            return_value=subprocess.CompletedProcess([], 0, "b" * 64 + "\n", ""),
        ):
            with self.assertRaisesRegex(helper.LocalhostError, "no longer running"):
                helper.docker_action("a" * 12, "restart")


if __name__ == "__main__":
    unittest.main()
