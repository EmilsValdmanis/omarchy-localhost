#!/usr/bin/env python3
"""OS-facing process and Docker actions for the Localhost shell plugin.

The QML layer owns presentation and discovery orchestration. This helper keeps
the security-sensitive `/proc` checks and lifecycle actions in one testable
place and always returns a small JSON response.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Sequence


CONTAINER_ID_RE = re.compile(r"^[0-9a-f]{12,64}$")
MAX_RESTART_LOGS = 10


class LocalhostError(RuntimeError):
    """An expected failure that can be shown directly in the plugin UI."""


def json_print(payload: dict[str, Any]) -> None:
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))


def proc_directory(pid: int, proc_root: Path = Path("/proc")) -> Path:
    return proc_root / str(pid)


def read_process_stat(pid: int, proc_root: Path = Path("/proc")) -> tuple[str, int]:
    """Return Linux process state and start time from proc(5) stat fields."""

    try:
        raw = (proc_directory(pid, proc_root) / "stat").read_text(errors="replace")
    except (FileNotFoundError, PermissionError, ProcessLookupError, OSError) as error:
        raise LocalhostError(f"PID {pid} is no longer running") from error

    closing = raw.rfind(")")
    fields = raw[closing + 2 :].split() if closing >= 0 else []
    # After removing PID and the parenthesized comm, state is field 3 and
    # starttime is field 22 (indices 0 and 19 in the remaining fields).
    if len(fields) <= 19:
        raise LocalhostError(f"Could not verify PID {pid}")
    try:
        return fields[0], int(fields[19])
    except ValueError as error:
        raise LocalhostError(f"Could not verify PID {pid}") from error


def read_null_separated(path: Path) -> list[str]:
    try:
        values = path.read_bytes().split(b"\0")
    except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
        return []
    return [value.decode(errors="replace") for value in values if value]


def inspect_process(
    pid: int,
    expected_uid: int,
    proc_root: Path = Path("/proc"),
) -> dict[str, Any] | None:
    directory = proc_directory(pid, proc_root)
    try:
        uid = directory.stat().st_uid
    except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
        return None
    if uid != expected_uid:
        return None

    try:
        _state, start_time = read_process_stat(pid, proc_root)
    except LocalhostError:
        return None

    argv = read_null_separated(directory / "cmdline")
    try:
        cwd = os.readlink(directory / "cwd")
    except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
        cwd = ""
    try:
        executable = os.readlink(directory / "exe")
    except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
        executable = ""

    return {
        "pid": pid,
        "uid": uid,
        "command": shlex.join(argv),
        "cwd": cwd,
        "executable": executable,
        "startTime": start_time,
    }


def inspect_processes(
    pids: Sequence[int],
    expected_uid: int,
    proc_root: Path = Path("/proc"),
) -> list[dict[str, Any]]:
    processes = []
    for pid in dict.fromkeys(pids):
        process = inspect_process(pid, expected_uid, proc_root)
        if process and process["cwd"] and process["command"]:
            processes.append(process)
    return processes


def verified_process_directory(
    pid: int,
    expected_start_time: int,
    proc_root: Path = Path("/proc"),
) -> Path:
    if pid <= 1 or pid in {os.getpid(), os.getppid()}:
        raise LocalhostError("Refusing to signal this process")
    if expected_start_time <= 0:
        raise LocalhostError("The process identity is incomplete; refresh and try again")

    directory = proc_directory(pid, proc_root)
    try:
        owner_uid = directory.stat().st_uid
    except (FileNotFoundError, PermissionError, ProcessLookupError, OSError) as error:
        raise LocalhostError(f"PID {pid} is no longer running") from error
    if owner_uid != os.geteuid():
        raise LocalhostError("Localhost only controls processes owned by your user")

    _state, current_start_time = read_process_stat(pid, proc_root)
    if current_start_time != expected_start_time:
        raise LocalhostError("The process changed since it was discovered; refresh and try again")
    return directory


def signal_process(pid: int, expected_start_time: int, force: bool = False) -> None:
    verified_process_directory(pid, expected_start_time)
    selected_signal = signal.SIGKILL if force else signal.SIGTERM
    try:
        os.kill(pid, selected_signal)
    except ProcessLookupError as error:
        raise LocalhostError(f"PID {pid} is no longer running") from error
    except PermissionError as error:
        raise LocalhostError(f"Permission denied while signaling PID {pid}") from error
    if not force and not wait_for_exit(pid, expected_start_time):
        raise LocalhostError("The server did not stop cleanly; use Force stop if needed")


def wait_for_exit(pid: int, expected_start_time: int, timeout: float = 1.5) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            state, start_time = read_process_stat(pid)
        except LocalhostError:
            return True
        if start_time != expected_start_time or state == "Z":
            return True
        time.sleep(0.05)
    return False


def read_restart_context(directory: Path) -> tuple[list[str], dict[str, str], str, str]:
    argv = read_null_separated(directory / "cmdline")
    if not argv:
        raise LocalhostError("Could not recover the server command")

    environment: dict[str, str] = {}
    for value in read_null_separated(directory / "environ"):
        if "=" in value:
            key, content = value.split("=", 1)
            if key:
                environment[key] = content
    if not environment:
        raise LocalhostError("Could not recover the server environment")

    try:
        cwd = os.readlink(directory / "cwd")
    except (FileNotFoundError, PermissionError, ProcessLookupError, OSError) as error:
        raise LocalhostError("Could not recover the server directory") from error
    try:
        executable = os.readlink(directory / "exe")
    except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
        executable = ""
    return argv, environment, cwd, executable


def prune_restart_logs(state_root: Path, keep: int = MAX_RESTART_LOGS) -> None:
    """Keep only the newest restart logs so repeated restarts cannot fill the disk."""

    try:
        logs = sorted(state_root.glob("restart-*.log"))
    except OSError:
        return
    for stale in logs[:-keep]:
        try:
            stale.unlink()
        except OSError:
            pass


def restart_process(
    pid: int, expected_start_time: int
) -> tuple[subprocess.Popen[bytes], Path]:
    directory = verified_process_directory(pid, expected_start_time)
    argv, environment, cwd, executable = read_restart_context(directory)

    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError as error:
        raise LocalhostError(f"PID {pid} is no longer running") from error
    except PermissionError as error:
        raise LocalhostError(f"Permission denied while signaling PID {pid}") from error
    if not wait_for_exit(pid, expected_start_time):
        raise LocalhostError("The server did not stop cleanly; use Force stop if needed")

    state_root = Path(
        os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local" / "state"))
    ) / "omarchy" / "localhost"
    state_root.mkdir(parents=True, exist_ok=True)
    log_path = state_root / f"restart-{time.time_ns()}.log"

    if not os.path.isabs(argv[0]) and executable and os.access(executable, os.X_OK):
        argv[0] = executable
    try:
        with log_path.open("ab", buffering=0) as log_file:
            restarted = subprocess.Popen(
                argv,
                cwd=cwd,
                env=environment,
                stdin=subprocess.DEVNULL,
                stdout=log_file,
                stderr=subprocess.STDOUT,
                start_new_session=True,
                close_fds=True,
            )
    except (OSError, ValueError) as error:
        raise LocalhostError(f"Could not restart the server: {error}") from error
    prune_restart_logs(state_root)
    return restarted, log_path


def run_command(
    command: Sequence[str], timeout: float,
) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            list(command),
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except (subprocess.TimeoutExpired, OSError) as error:
        raise LocalhostError(str(error)) from error


def docker_action(container_id: str, action: str) -> None:
    if not CONTAINER_ID_RE.fullmatch(container_id):
        raise LocalhostError("Invalid Docker container ID")
    listed = run_command(["docker", "ps", "-q", "--no-trunc"], timeout=3.0)
    if listed.returncode != 0:
        raise LocalhostError(listed.stderr.strip() or "Could not query Docker")
    running = {line.strip() for line in listed.stdout.splitlines() if line.strip()}
    matches = [value for value in running if value == container_id or value.startswith(container_id)]
    if len(matches) != 1:
        raise LocalhostError("The Docker container is no longer running")

    timeout = 15.0 if action == "stop" else 12.0
    command = ["docker", action]
    if action == "stop":
        command.extend(["--time", "10"])
    command.append(matches[0])
    completed = run_command(command, timeout=timeout)
    if completed.returncode != 0:
        raise LocalhostError(completed.stderr.strip() or f"Docker could not {action} the container")


def comma_separated_pids(value: str) -> list[int]:
    result = []
    for token in value.split(","):
        token = token.strip()
        if token.isdigit() and int(token) > 0:
            result.append(int(token))
    return result


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Secure Localhost plugin actions")
    subparsers = parser.add_subparsers(dest="command", required=True)

    inspect_parser = subparsers.add_parser("inspect", help="Read owned process metadata")
    inspect_parser.add_argument("--pids", required=True)
    inspect_parser.add_argument("--uid", required=True, type=int)

    action_parser = subparsers.add_parser("process-action", help="Stop or restart a process")
    action_parser.add_argument("--action", choices=["stop", "force-stop", "restart"], required=True)
    action_parser.add_argument("--pid", required=True, type=int)
    action_parser.add_argument("--start-time", required=True, type=int)

    docker_parser = subparsers.add_parser("docker-action", help="Stop or restart a container")
    docker_parser.add_argument("--action", choices=["stop", "restart"], required=True)
    docker_parser.add_argument("--id", required=True)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    arguments = build_parser().parse_args(argv)
    try:
        if arguments.command == "inspect":
            processes = inspect_processes(
                comma_separated_pids(arguments.pids), arguments.uid
            )
            json_print({"ok": True, "processes": processes})
        elif arguments.command == "process-action":
            if arguments.action == "restart":
                restarted, log_path = restart_process(arguments.pid, arguments.start_time)
                json_print({
                    "ok": True,
                    "message": "Server restarted",
                    "pid": restarted.pid,
                    "log": str(log_path),
                })
            else:
                signal_process(
                    arguments.pid,
                    arguments.start_time,
                    force=arguments.action == "force-stop",
                )
                json_print({
                    "ok": True,
                    "message": "Server force stopped" if arguments.action == "force-stop" else "Server stopped",
                })
        elif arguments.command == "docker-action":
            docker_action(arguments.id, arguments.action)
            json_print({
                "ok": True,
                "message": "Docker container stopped"
                if arguments.action == "stop"
                else "Docker container restarted",
            })
        return 0
    except LocalhostError as error:
        json_print({"ok": False, "error": str(error)})
        return 1


if __name__ == "__main__":
    sys.exit(main())
