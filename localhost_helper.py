#!/usr/bin/env python3
"""OS-facing process and Docker actions for the Localhost shell plugin.

The QML layer owns presentation and discovery orchestration. This helper keeps
the security-sensitive `/proc` checks and lifecycle actions in one testable
place and always returns a small JSON response.
"""

from __future__ import annotations

import argparse
from contextlib import contextmanager
import http.client
import ipaddress
import json
import os
import re
import select
import shlex
import shutil
import signal
import socket
import ssl
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Sequence
from urllib.parse import urlsplit

from project_metadata import ProjectInspector


CONTAINER_ID_RE = re.compile(r"^[0-9a-f]{12,64}$")
MAX_RESTART_LOGS = 10
RESTART_READY_TIMEOUT = 10.0


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


def read_null_separated(path: Path, *, errors: str = "replace") -> list[str]:
    try:
        values = path.read_bytes().split(b"\0")
    except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
        return []
    # Empty argv entries are real arguments; only remove the final terminator.
    if values and values[-1] == b"":
        values.pop()
    return [value.decode(errors=errors) for value in values]


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

    memory_bytes = -1
    try:
        for line in (directory / "status").read_text(errors="replace").splitlines():
            if line.startswith("VmRSS:"):
                memory_bytes = int(line.split()[1]) * 1024
                break
    except (FileNotFoundError, PermissionError, ProcessLookupError, OSError, ValueError, IndexError):
        pass

    restart_reason = ""
    try:
        read_restart_context(directory)
    except LocalhostError as error:
        restart_reason = str(error)

    return {
        "pid": pid,
        "uid": uid,
        "command": shlex.join(argv),
        "argv": argv,
        "cwd": cwd,
        "executable": executable,
        "startTime": start_time,
        "memoryBytes": memory_bytes,
        "restartAvailable": not restart_reason,
        "restartReason": restart_reason,
    }


def parse_docker_memory(value: str) -> int:
    """Convert the used half of Docker's human-readable MemUsage to bytes."""
    match = re.match(r"^\s*([\d.]+)\s*([KMGTPE]?i?B|B)\b", value, re.IGNORECASE)
    if not match:
        return -1
    unit = match.group(2).upper()
    power = "KMGTPE".find(unit[0]) + 1 if unit != "B" else 0
    base = 1024 if "I" in unit else 1000
    return round(float(match.group(1)) * base ** power)


def read_system_memory(meminfo_path: Path = Path("/proc/meminfo")) -> dict[str, int]:
    """Read physical RAM and the kernel's estimate of immediately available RAM."""
    values: dict[str, int] = {}
    try:
        for line in meminfo_path.read_text().splitlines():
            fields = line.split()
            if len(fields) == 3 and fields[0] in {"MemTotal:", "MemAvailable:"} and fields[2] == "kB":
                values[fields[0]] = int(fields[1]) * 1024
    except (OSError, ValueError):
        return {"totalBytes": -1, "availableBytes": -1}
    total = values.get("MemTotal:", -1)
    available = values.get("MemAvailable:", -1)
    if total <= 0 or available < 0 or available > total:
        return {"totalBytes": -1, "availableBytes": -1}
    return {"totalBytes": total, "availableBytes": available}


def inspect_container_memory(container_ids: Sequence[str]) -> dict[str, int]:
    ids = list(dict.fromkeys(value for value in container_ids if CONTAINER_ID_RE.fullmatch(value)))
    if not ids:
        return {}
    memory = {}
    for offset in range(0, len(ids), 128):
        batch = ids[offset : offset + 128]
        try:
            result = subprocess.run(
                ["docker", "stats", "--no-stream", "--format", "{{.ID}}\t{{.MemUsage}}", *batch],
                check=False, capture_output=True, text=True, timeout=3,
            )
        except (subprocess.TimeoutExpired, OSError):
            continue
        if result.returncode != 0:
            continue
        for line in result.stdout.splitlines():
            fields = line.split("\t", 1)
            if len(fields) != 2:
                continue
            for container_id in batch:
                if container_id.startswith(fields[0]) or fields[0].startswith(container_id):
                    memory[container_id] = parse_docker_memory(fields[1])
                    break
    return memory


def inspect_processes(
    pids: Sequence[int],
    expected_uid: int,
    proc_root: Path = Path("/proc"),
    inspector: ProjectInspector | None = None,
) -> list[dict[str, Any]]:
    inspector = inspector or ProjectInspector()
    processes = []
    for pid in dict.fromkeys(pids):
        process = inspect_process(pid, expected_uid, proc_root)
        if process and process["cwd"] and process["command"]:
            process["project"] = inspector.inspect(process["cwd"])
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


@contextmanager
def verified_process_handle(pid: int, expected_start_time: int):
    """Pin the process before checking /proc; never signal a bare, reusable PID."""
    if not hasattr(os, "pidfd_open") or not hasattr(signal, "pidfd_send_signal"):
        raise LocalhostError("Process actions require Linux pidfd support")
    try:
        handle = os.pidfd_open(pid)
    except ProcessLookupError as error:
        raise LocalhostError(f"PID {pid} is no longer running") from error
    except OSError as error:
        raise LocalhostError(f"Could not acquire a process handle for PID {pid}: {error}") from error
    try:
        directory = verified_process_directory(pid, expected_start_time)
        yield handle, directory
    finally:
        os.close(handle)


def send_process_signal(handle: int, pid: int, selected_signal: int) -> None:
    try:
        signal.pidfd_send_signal(handle, selected_signal)
    except ProcessLookupError as error:
        raise LocalhostError(f"PID {pid} is no longer running") from error
    except OSError as error:
        raise LocalhostError(f"Could not signal PID {pid}: {error}") from error


def wait_for_handle_exit(handle: int, timeout: float = 1.5) -> bool:
    poller = select.poll()
    poller.register(handle, select.POLLIN)
    return bool(poller.poll(round(timeout * 1000)))


def signal_process(pid: int, expected_start_time: int, force: bool = False) -> None:
    with verified_process_handle(pid, expected_start_time) as (handle, _directory):
        send_process_signal(handle, pid, signal.SIGKILL if force else signal.SIGTERM)
        if not force and not wait_for_handle_exit(handle):
            raise LocalhostError("The server did not stop cleanly; use Force stop if needed")


def read_restart_context(directory: Path) -> tuple[list[str], dict[str, str], str, str]:
    argv = read_null_separated(directory / "cmdline", errors="surrogateescape")
    if not argv:
        raise LocalhostError("Could not recover the server command")

    environment: dict[str, str] = {}
    for value in read_null_separated(directory / "environ", errors="surrogateescape"):
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
    except OSError as error:
        raise LocalhostError("Could not recover the server executable") from error
    argv = validate_restart_command(argv, environment, cwd, executable)
    return argv, environment, cwd, executable


def validate_restart_command(
    argv: list[str], environment: dict[str, str], cwd: str, executable: str,
) -> list[str]:
    """Reject rewritten titles instead of substituting an executable for argv[0]."""
    if not Path(cwd).is_dir() or not os.access(cwd, os.X_OK):
        raise LocalhostError("The server directory is no longer accessible")
    if not argv:
        raise LocalhostError("Could not recover the server command")
    command = argv[0]
    if "/" in command:
        resolved = command if os.path.isabs(command) else os.path.join(cwd, command)
    else:
        # Resolve relative PATH entries against the server's working directory.
        search_path = os.pathsep.join(
            entry if os.path.isabs(entry) else os.path.join(cwd, entry)
            for entry in environment.get("PATH", os.defpath).split(os.pathsep)
        )
        resolved = shutil.which(command, path=search_path) or ""
    try:
        matches = bool(resolved) and os.path.samefile(resolved, executable)
    except OSError:
        matches = False
    if not matches or not os.access(executable, os.X_OK):
        raise LocalhostError("Restart unavailable: the launch command cannot be recovered reliably (possibly a rewritten process title)")

    runtime = Path(executable).name
    python_runtime = bool(re.fullmatch(r"python(?:\d+(?:\.\d+)?)?", runtime))
    if runtime in {"node", "nodejs", "bun", "deno"} or python_runtime:
        arguments = argv[1:]
        # Only recover explicit entry points. Unknown runtime option layouts and
        # runtime-only titles are deliberately disabled rather than guessed.
        if not arguments:
            raise LocalhostError("Restart unavailable: the runtime entry point is missing")
        inline_modes = {"-c", "-m"} if python_runtime else {"-e", "--eval"}
        if arguments[0] in inline_modes:
            if len(arguments) < 2 or not arguments[1]:
                raise LocalhostError("Restart unavailable: the runtime entry point is missing")
        else:
            entry_point = arguments[1] if runtime == "deno" and arguments[0] == "run" and len(arguments) > 1 else arguments[0]
            path = Path(cwd) / entry_point
            if entry_point.startswith("-") or not path.is_file() or not os.access(path, os.R_OK):
                raise LocalhostError("Restart unavailable: the runtime entry point cannot be verified")
    return [executable, *argv[1:]]


def listening_endpoints(directory: Path) -> set[tuple[str, int]]:
    """Find TCP listening sockets owned by this process, not another port user."""
    inodes = set()
    try:
        for descriptor in (directory / "fd").iterdir():
            try:
                target = os.readlink(descriptor)
            except OSError:
                continue
            match = re.fullmatch(r"socket:\[(\d+)\]", target)
            if match:
                inodes.add(match.group(1))
    except OSError:
        return set()
    endpoints = set()
    for protocol in ("tcp", "tcp6"):
        try:
            lines = (directory / "net" / protocol).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[3] == "0A" and fields[9] in inodes:
                raw_address, raw_port = fields[1].split(":")
                encoded = bytes.fromhex(raw_address)
                if sys.byteorder == "little":
                    encoded = b"".join(encoded[offset:offset + 4][::-1] for offset in range(0, len(encoded), 4))
                address = socket.inet_ntop(socket.AF_INET if protocol == "tcp" else socket.AF_INET6, encoded)
                endpoints.add((address, int(raw_port, 16)))
    return endpoints


def listening_ports(directory: Path) -> set[int]:
    return {port for _host, port in listening_endpoints(directory)}


def owned_probe_host(directory: Path, endpoint: tuple[str, str, int]) -> str | None:
    _scheme, host, port = endpoint
    addresses = sorted(address for address, bound_port in listening_endpoints(directory) if bound_port == port)
    for address in addresses:
        bound = ipaddress.ip_address(address)
        if host == "localhost":
            if bound.is_unspecified:
                return "127.0.0.1" if bound.version == 4 else "::1"
            if bound.is_loopback:
                return address
        else:
            requested = ipaddress.ip_address(host)
            if bound == requested:
                return host
            if bound.is_unspecified and bound.version == requested.version:
                return "127.0.0.1" if bound.version == 4 else "::1"
    return None


def restart_endpoint(url: str) -> tuple[str, str, int]:
    try:
        parsed = urlsplit(url)
        if (parsed.scheme not in {"http", "https"} or not parsed.hostname
                or parsed.username is not None or parsed.password is not None
                or parsed.path not in {"", "/"} or parsed.query or parsed.fragment
                or parsed.port is None or parsed.port < 1):
            raise ValueError("invalid URL")
        if parsed.hostname != "localhost":
            ipaddress.ip_address(parsed.hostname)
        return parsed.scheme, parsed.hostname, parsed.port
    except ValueError as error:
        raise LocalhostError("Restart requires the server's HTTP or HTTPS URL") from error


def wait_for_restart_ready(
    restarted: subprocess.Popen[bytes], endpoint: tuple[str, str, int], log_path: Path,
    timeout: float = RESTART_READY_TIMEOUT,
) -> None:
    scheme, host, port = endpoint
    deadline = time.monotonic() + timeout
    ready_since = None
    while time.monotonic() < deadline:
        if restarted.poll() is not None:
            raise LocalhostError(f"The replacement exited with status {restarted.returncode}; see {log_path}")
        ready = False
        if owned_probe_host(proc_directory(restarted.pid), endpoint):
            connection = (
                http.client.HTTPSConnection(host, port, timeout=0.3, context=ssl._create_unverified_context())
                if scheme == "https" else http.client.HTTPConnection(host, port, timeout=0.3)
            )
            try:
                connection.request("HEAD", "/")
                ready = 100 <= connection.getresponse().status <= 599
            except (OSError, http.client.HTTPException):
                pass
            finally:
                connection.close()
        if ready and restarted.poll() is None:
            if ready_since is None:
                ready_since = time.monotonic()
            elif time.monotonic() - ready_since >= 0.2:
                return
        else:
            ready_since = None
        time.sleep(0.05)
    raise LocalhostError(f"The replacement did not become HTTP-ready within {timeout:g}s; see {log_path}")


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
    pid: int, expected_start_time: int, url: str
) -> tuple[subprocess.Popen[bytes], Path]:
    endpoint = restart_endpoint(url)
    with verified_process_handle(pid, expected_start_time) as (handle, directory):
        context = read_restart_context(directory)
        argv, environment, cwd, _executable = context
        probe_host = owned_probe_host(directory, endpoint)
        if not probe_host:
            raise LocalhostError("The original process no longer owns the server's listening port")
        endpoint = endpoint[0], probe_host, endpoint[2]
        state_root = Path(
            os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local" / "state"))
        ) / "omarchy" / "localhost"
        log_path = state_root / f"restart-{time.time_ns()}.log"
        try:
            state_root.mkdir(parents=True, exist_ok=True)
            log_file = os.fdopen(os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "wb", buffering=0)
        except OSError as error:
            raise LocalhostError(f"Could not prepare the restart log: {error}") from error
        with log_file:
            verified_process_directory(pid, expected_start_time)
            if read_restart_context(directory) != context:
                raise LocalhostError("The server launch context changed; refresh and try again")
            if not owned_probe_host(directory, endpoint):
                raise LocalhostError("The original process no longer owns the server's listening port")
            send_process_signal(handle, pid, signal.SIGTERM)
            if not wait_for_handle_exit(handle):
                raise LocalhostError("The server did not stop cleanly; use Force stop if needed")
            try:
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
                raise LocalhostError(f"Could not restart the server: {error}; see {log_path}") from error
    prune_restart_logs(state_root)
    wait_for_restart_ready(restarted, endpoint, log_path)
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
    inspect_parser.add_argument("--paths", default="[]", help="JSON array of Compose working directories")
    inspect_parser.add_argument("--containers", default="", help="Comma-separated container IDs to sample")

    action_parser = subparsers.add_parser("process-action", help="Stop or restart a process")
    action_parser.add_argument("--action", choices=["stop", "force-stop", "restart"], required=True)
    action_parser.add_argument("--pid", required=True, type=int)
    action_parser.add_argument("--start-time", required=True, type=int)
    action_parser.add_argument("--url", default="", help="Original server URL for restart readiness")

    docker_parser = subparsers.add_parser("docker-action", help="Stop or restart a container")
    docker_parser.add_argument("--action", choices=["stop", "restart"], required=True)
    docker_parser.add_argument("--id", required=True)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    arguments = build_parser().parse_args(argv)
    try:
        if arguments.command == "inspect":
            inspector = ProjectInspector()
            try:
                paths = json.loads(arguments.paths)
            except ValueError as error:
                raise LocalhostError("Invalid project paths") from error
            if not isinstance(paths, list) or len(paths) > 256 or not all(isinstance(path, str) for path in paths):
                raise LocalhostError("Invalid project paths")
            processes = inspect_processes(
                comma_separated_pids(arguments.pids), arguments.uid, inspector=inspector
            )
            json_print({"ok": True, "processes": processes,
                        "projects": {path: inspector.inspect(path) for path in dict.fromkeys(paths)},
                        "containers": inspect_container_memory(arguments.containers.split(",")),
                        "systemMemory": read_system_memory()})
        elif arguments.command == "process-action":
            if arguments.action == "restart":
                restarted, log_path = restart_process(arguments.pid, arguments.start_time, arguments.url)
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
