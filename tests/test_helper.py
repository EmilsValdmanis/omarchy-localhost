import os
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
        state_root = Path(self.state_directory.name) / "omarchy" / "localhost"
        state_root.mkdir(parents=True)
        for stamp in range(helper.MAX_RESTART_LOGS):
            (state_root / f"restart-{stamp:019d}.log").write_text("old log")

        with mock.patch.dict(os.environ, {"XDG_STATE_HOME": self.state_directory.name}):
            self.restarted, log_path = helper.restart_process(
                self.child.pid, self.start_time
            )
        self.child.wait(timeout=2)

        self.assertGreater(self.restarted.pid, 1)
        self.assertTrue(Path(f"/proc/{self.restarted.pid}").exists())
        self.assertTrue(log_path.parent.is_dir())
        self.assertEqual(len(list(state_root.glob("restart-*.log"))), helper.MAX_RESTART_LOGS)
        self.assertFalse((state_root / f"restart-{0:019d}.log").exists())

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
