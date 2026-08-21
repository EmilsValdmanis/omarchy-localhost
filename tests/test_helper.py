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
        self.assertTrue(process["command"])
        self.assertTrue(process["cwd"])

    def test_ignores_process_owned_by_another_uid(self):
        self.assertIsNone(helper.inspect_process(os.getpid(), os.geteuid() + 1))

    def test_parses_unique_positive_process_ids(self):
        self.assertEqual(helper.comma_separated_pids("12,bad,0,12,34"), [12, 12, 34])
        inspected = helper.inspect_processes([os.getpid(), os.getpid()], os.geteuid())
        self.assertEqual(len(inspected), 1)


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
