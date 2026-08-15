#!/usr/bin/env python3
"""Localhost discovery and actions for the emils.localhost Omarchy plugin.

The scanner only inspects listening sockets and processes owned by the current
user. It intentionally avoids privileged APIs, network services, and package
dependencies so the plugin stays easy to review and portable across Omarchy
machines.
"""

from __future__ import annotations

import argparse
import ipaddress
import json
import os
from pathlib import Path
import re
import shlex
import signal
import subprocess
import sys
import time
from typing import Any, Iterable


PROJECT_MARKERS = (
    "package.json",
    "pyproject.toml",
    "requirements.txt",
    "manage.py",
    "Cargo.toml",
    "go.mod",
    "Gemfile",
    "composer.json",
    "mix.exs",
)

COMMON_DEV_PORTS = {
    3000,
    3001,
    4000,
    4173,
    4200,
    4321,
    5000,
    5173,
    5174,
    8000,
    8001,
    8080,
    8787,
}

EXCLUDED_PROCESSES = {
    "cloudflared",
    "containerd",
    "cupsd",
    "dnsmasq",
    "docker-proxy",
    "opendeck",
    "qemu-system-x86_64",
    "sshd",
    "systemd-resolved",
}

DEV_COMMAND_PATTERN = re.compile(
    r"(?:^|[ /._-])(?:"
    r"astro|bun|cargo|deno|django|expo|fastapi|flask|gatsby|go|"
    r"http\.server|mix|next|node|nuxt|parcel|php|pnpm|rails|remix|"
    r"storybook|svelte|uvicorn|vite|webpack|yarn"
    r")(?:$|[ /._-])",
    re.IGNORECASE,
)


def run(command: list[str], *, timeout: float = 2.0) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        check=False,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def lan_ip_address() -> str:
    """Return the IPv4 source address for the default route, without I/O."""
    try:
        result = run(["ip", "-j", "route", "get", "1.1.1.1"])
        if result.returncode == 0:
            routes = json.loads(result.stdout or "[]")
            for route in routes:
                candidate = str(route.get("prefsrc", ""))
                if candidate and not ipaddress.ip_address(candidate).is_loopback:
                    return candidate
    except (FileNotFoundError, json.JSONDecodeError, subprocess.TimeoutExpired, ValueError):
        pass

    try:
        result = run(["hostname", "-I"])
        for candidate in result.stdout.split():
            address = ipaddress.ip_address(candidate)
            if address.version == 4 and not address.is_loopback and not address.is_link_local:
                return candidate
    except (FileNotFoundError, subprocess.TimeoutExpired, ValueError):
        pass
    return ""


def split_endpoint(endpoint: str) -> tuple[str, int] | None:
    endpoint = endpoint.strip()
    if endpoint.startswith("[") and "]:" in endpoint:
        address, raw_port = endpoint[1:].rsplit("]:", 1)
    elif ":" in endpoint:
        address, raw_port = endpoint.rsplit(":", 1)
    else:
        return None
    address = address.split("%", 1)[0]
    try:
        return address, int(raw_port)
    except ValueError:
        return None


def parse_ss(raw: str) -> list[dict[str, Any]]:
    """Parse `ss -H -ltnp`, grouping duplicate bindings per process/port."""
    grouped: dict[tuple[int, int], dict[str, Any]] = {}
    for line in raw.splitlines():
        fields = line.split(None, 5)
        if len(fields) < 5:
            continue
        endpoint = split_endpoint(fields[3])
        if endpoint is None:
            continue
        address, port = endpoint
        process_field = fields[5] if len(fields) > 5 else ""
        pids = [int(value) for value in re.findall(r"pid=(\d+)", process_field)]
        names = re.findall(r'\("([^"]+)"', process_field)
        for index, pid in enumerate(pids):
            key = (pid, port)
            entry = grouped.setdefault(
                key,
                {
                    "pid": pid,
                    "port": port,
                    "process": names[index] if index < len(names) else "",
                    "addresses": [],
                },
            )
            if address not in entry["addresses"]:
                entry["addresses"].append(address)
    return list(grouped.values())


def process_info(pid: int) -> dict[str, Any] | None:
    proc = Path("/proc") / str(pid)
    try:
        if proc.stat().st_uid != os.getuid():
            return None
        argv = [part.decode(errors="replace") for part in (proc / "cmdline").read_bytes().split(b"\0") if part]
        cwd = os.readlink(proc / "cwd")
        executable = os.readlink(proc / "exe")
    except (FileNotFoundError, PermissionError, ProcessLookupError):
        return None
    if not argv:
        return None
    return {
        "pid": pid,
        "argv": argv,
        "cwd": cwd,
        "executable": executable,
        "command": shlex.join(argv),
    }


def project_root(cwd: str) -> Path | None:
    try:
        current = Path(cwd).resolve()
    except (OSError, RuntimeError):
        return None
    if not current.is_dir():
        return None

    fallback: Path | None = None
    for _ in range(9):
        if any((current / marker).is_file() for marker in PROJECT_MARKERS):
            fallback = current
            if (current / ".git").exists() or (current / "package.json").is_file():
                return current
        if current.parent == current:
            break
        current = current.parent
    return fallback


def load_package(root: Path | None) -> dict[str, Any]:
    if root is None:
        return {}
    try:
        value = json.loads((root / "package.json").read_text())
        return value if isinstance(value, dict) else {}
    except (FileNotFoundError, PermissionError, json.JSONDecodeError, OSError):
        return {}


def file_contains(path: Path, needle: str) -> bool:
    try:
        return needle.lower() in path.read_text(errors="replace")[:200_000].lower()
    except (FileNotFoundError, PermissionError, OSError):
        return False


def framework_for(root: Path | None, command: str, package: dict[str, Any]) -> tuple[str, str]:
    command_lower = command.lower()
    dependencies: set[str] = set()
    for field in ("dependencies", "devDependencies", "peerDependencies"):
        values = package.get(field, {})
        if isinstance(values, dict):
            dependencies.update(str(key).lower() for key in values)

    node_frameworks = (
        (("next",), "Next.js", "next"),
        (("nuxt",), "Nuxt", "nuxt"),
        (("@sveltejs/kit",), "SvelteKit", "svelte"),
        (("astro",), "Astro", "astro"),
        (("@angular/core",), "Angular", "angular"),
        (("gatsby",), "Gatsby", "gatsby"),
        (("@remix-run/dev",), "Remix", "remix"),
        (("@storybook/react", "@storybook/vue3", "@storybook/svelte"), "Storybook", "storybook"),
        (("react-scripts",), "Create React App", "react"),
        (("vite",), "Vite", "vite"),
        (("webpack-dev-server",), "Webpack", "webpack"),
        (("parcel",), "Parcel", "parcel"),
    )
    for packages, name, identifier in node_frameworks:
        if any(value in dependencies for value in packages):
            return name, identifier

    command_frameworks = (
        ("next", "Next.js", "next"),
        ("nuxt", "Nuxt", "nuxt"),
        ("svelte", "SvelteKit", "svelte"),
        ("astro", "Astro", "astro"),
        ("vite", "Vite", "vite"),
        ("storybook", "Storybook", "storybook"),
        ("uvicorn", "FastAPI / Uvicorn", "python"),
        ("flask", "Flask", "python"),
        ("manage.py runserver", "Django", "python"),
        ("rails server", "Rails", "rails"),
        ("rails s", "Rails", "rails"),
        ("php artisan serve", "Laravel", "laravel"),
        ("mix phx.server", "Phoenix", "phoenix"),
        ("http.server", "Python HTTP", "python"),
        ("cargo run", "Rust", "rust"),
        ("go run", "Go", "go"),
    )
    for token, name, identifier in command_frameworks:
        if token in command_lower:
            return name, identifier

    if root is not None:
        if (root / "manage.py").is_file():
            return "Django", "python"
        if (root / "mix.exs").is_file() and file_contains(root / "mix.exs", "phoenix"):
            return "Phoenix", "phoenix"
        if (root / "Gemfile").is_file() and file_contains(root / "Gemfile", "rails"):
            return "Rails", "rails"
        if (root / "composer.json").is_file() and file_contains(root / "composer.json", "laravel"):
            return "Laravel", "laravel"
        if (root / "Cargo.toml").is_file():
            return "Rust", "rust"
        if (root / "go.mod").is_file():
            return "Go", "go"
        if (root / "pyproject.toml").is_file() or (root / "requirements.txt").is_file():
            if file_contains(root / "pyproject.toml", "fastapi") or file_contains(root / "requirements.txt", "fastapi"):
                return "FastAPI", "python"
            return "Python", "python"
        if package:
            return "Node.js", "node"
    return "Dev server", "server"


def project_name(root: Path | None, package: dict[str, Any], process: str) -> str:
    package_name = package.get("name")
    if isinstance(package_name, str) and package_name.strip():
        return package_name.strip()
    if root is not None:
        return root.name
    return process or "Development server"


def ipv6_accepts_ipv4() -> bool:
    try:
        return Path("/proc/sys/net/ipv6/bindv6only").read_text().strip() == "0"
    except (FileNotFoundError, PermissionError, OSError):
        return False


def lan_host_for(addresses: Iterable[str], default_lan_ip: str) -> str:
    values = list(addresses)
    if default_lan_ip:
        if "0.0.0.0" in values or "*" in values or default_lan_ip in values:
            return default_lan_ip
        if "::" in values and ipv6_accepts_ipv4():
            return default_lan_ip

    for raw in values:
        candidate = raw.split("%", 1)[0]
        try:
            address = ipaddress.ip_address(candidate)
        except ValueError:
            continue
        if not address.is_loopback and not address.is_unspecified and not address.is_link_local:
            return candidate
    return ""


def url_host(host: str) -> str:
    return f"[{host}]" if ":" in host and not host.startswith("[") else host


def is_candidate(
    listener: dict[str, Any],
    process: dict[str, Any],
    root: Path | None,
    framework: str,
) -> bool:
    if listener["port"] < 1024:
        return False
    process_name = (listener.get("process") or Path(process["executable"]).name).lower()
    if process_name in EXCLUDED_PROCESSES:
        return False
    if framework != "Dev server":
        return True
    if DEV_COMMAND_PATTERN.search(process["command"]):
        return True
    return root is not None and listener["port"] in COMMON_DEV_PORTS


def scheme_for(command: str) -> str:
    lower = command.lower()
    https_tokens = ("--https", "https://", "ssl-keyfile", "--ssl", "https=true")
    return "https" if any(token in lower for token in https_tokens) else "http"


def scan_servers(ss_output: str | None = None, lan_ip: str | None = None) -> dict[str, Any]:
    if ss_output is None:
        result = run(["ss", "-H", "-ltnp"])
        if result.returncode != 0:
            raise RuntimeError(result.stderr.strip() or "Could not inspect listening sockets")
        ss_output = result.stdout
    if lan_ip is None:
        lan_ip = lan_ip_address()

    servers: list[dict[str, Any]] = []
    for listener in parse_ss(ss_output):
        process = process_info(listener["pid"])
        if process is None:
            continue
        root = project_root(process["cwd"])
        package = load_package(root)
        framework, framework_id = framework_for(root, process["command"], package)
        if not is_candidate(listener, process, root, framework):
            continue

        lan_host = lan_host_for(listener["addresses"], lan_ip)
        lan_available = bool(lan_host)
        scheme = scheme_for(process["command"])
        port = listener["port"]
        loopback_bound = any(
            value in {"127.0.0.1", "::1"} or value.startswith("127.")
            for value in listener["addresses"]
        )
        wildcard_bound = any(value in {"0.0.0.0", "*", "::"} for value in listener["addresses"])
        local_host = "localhost" if loopback_bound or wildcard_bound else (lan_host or "localhost")
        local_url = f"{scheme}://{url_host(local_host)}:{port}"
        lan_url = f"{scheme}://{url_host(lan_host)}:{port}" if lan_available else ""

        servers.append(
            {
                "id": f"{listener['pid']}:{port}",
                "name": project_name(root or Path(process["cwd"]), package, listener.get("process", "")),
                "framework": framework,
                "frameworkId": framework_id,
                "pid": listener["pid"],
                "port": port,
                "cwd": str(root or process["cwd"]),
                "command": process["command"][:240],
                "bindAddresses": listener["addresses"],
                "localUrl": local_url,
                "lanUrl": lan_url,
                "lanHost": lan_host,
                "lanAvailable": lan_available,
                "status": "Available on LAN" if lan_available else "Not available on LAN",
                "hint": (
                    "Same Wi-Fi network required"
                    if lan_available
                    else "Server is bound to localhost only. Start it with --host / 0.0.0.0 to test on another device."
                ),
            }
        )

    servers.sort(key=lambda item: (item["port"], item["name"].lower()))
    return {"lanIp": lan_ip, "servers": servers, "scannedAt": int(time.time())}


def owned_process(pid: int) -> Path:
    proc = Path("/proc") / str(pid)
    try:
        if proc.stat().st_uid != os.getuid():
            raise PermissionError("Process is not owned by the current user")
    except FileNotFoundError as error:
        raise ProcessLookupError(f"Process {pid} is no longer running") from error
    return proc


def stop_server(pid: int) -> dict[str, Any]:
    owned_process(pid)
    os.kill(pid, signal.SIGTERM)
    return {"ok": True, "pid": pid, "action": "stop"}


def read_environment(proc: Path) -> dict[str, str]:
    environment: dict[str, str] = {}
    for entry in (proc / "environ").read_bytes().split(b"\0"):
        if b"=" not in entry:
            continue
        key, value = entry.split(b"=", 1)
        environment[key.decode(errors="replace")] = value.decode(errors="replace")
    return environment


def restart_server(pid: int) -> dict[str, Any]:
    proc = owned_process(pid)
    argv = [part.decode(errors="replace") for part in (proc / "cmdline").read_bytes().split(b"\0") if part]
    if not argv:
        raise RuntimeError("Could not recover the server command")
    cwd = os.readlink(proc / "cwd")
    executable = os.readlink(proc / "exe")
    environment = read_environment(proc)
    if not os.path.isabs(argv[0]) and Path(executable).is_file():
        argv[0] = executable

    os.kill(pid, signal.SIGTERM)
    for _ in range(30):
        if not proc.exists():
            break
        time.sleep(0.05)
    if proc.exists():
        raise RuntimeError("The server did not stop cleanly; restart was cancelled")

    state_dir = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "omarchy/localhost"
    state_dir.mkdir(parents=True, exist_ok=True)
    log_path = state_dir / f"restart-{int(time.time())}.log"
    with log_path.open("ab", buffering=0) as log:
        child = subprocess.Popen(
            argv,
            cwd=cwd,
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
    return {
        "ok": True,
        "pid": child.pid,
        "previousPid": pid,
        "action": "restart",
        "log": str(log_path),
    }


def qr_matrix(payload: str) -> dict[str, Any]:
    try:
        result = subprocess.run(
            ["qrencode", "--type", "ASCII", "--margin", "4", "--output", "-"],
            input=payload,
            check=False,
            capture_output=True,
            text=True,
            timeout=4,
        )
    except FileNotFoundError as error:
        raise RuntimeError("qrencode is not installed") from error
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Could not generate the QR code")

    rows: list[str] = []
    for line in result.stdout.splitlines():
        row = "".join("1" if "#" in line[column : column + 2] else "0" for column in range(0, len(line), 2))
        rows.append(row)
    if not rows or any(len(row) != len(rows) or not re.fullmatch(r"[01]+", row) for row in rows):
        raise RuntimeError("qrencode returned an invalid matrix")
    return {"url": payload, "size": len(rows), "rows": rows}


def positive_pid(value: str) -> int:
    pid = int(value)
    if pid <= 0:
        raise argparse.ArgumentTypeError("PID must be positive")
    return pid


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description="Discover and control local development servers")
    commands = root.add_subparsers(dest="command", required=True)
    commands.add_parser("scan", help="Print discovered servers as JSON")
    qr = commands.add_parser("qr", help="Print a QR module matrix as JSON")
    qr.add_argument("url")
    stop = commands.add_parser("stop", help="Terminate an owned server process")
    stop.add_argument("pid", type=positive_pid)
    restart = commands.add_parser("restart", help="Restart an owned server process")
    restart.add_argument("pid", type=positive_pid)
    return root


def main() -> int:
    args = parser().parse_args()
    try:
        if args.command == "scan":
            payload = scan_servers()
        elif args.command == "qr":
            payload = qr_matrix(args.url)
        elif args.command == "stop":
            payload = stop_server(args.pid)
        elif args.command == "restart":
            payload = restart_server(args.pid)
        else:
            raise RuntimeError("Unknown command")
        print(json.dumps(payload, separators=(",", ":")))
        return 0
    except (OSError, RuntimeError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
