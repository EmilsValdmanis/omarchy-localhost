# Localhost for Omarchy

Your local development servers, one click away.

Start Vite, Next.js, Astro, Rails, or another development server and Localhost
automatically adds it to the Omarchy bar. Open it on your desktop, copy its
address, or put it on your phone with one scan.

> `pnpm dev` → Localhost appears → click **QR** → scan with your phone

## The good bit

Localhost understands the difference between a server that is merely running
and one your phone can actually reach.

- **Available on LAN** — the process listens on `0.0.0.0`, `::`, or a LAN
  interface. Localhost builds a URL with your default-route IP, such as
  `http://192.168.1.42:5173`, and enables QR sharing.
- **Local only** — the process listens on `127.0.0.1` or `::1`. Localhost keeps
  desktop actions available, disables QR, and explains how to bind the server
  for mobile testing.

The QR view is rendered as native QML rectangles, so it stays sharp at every
display scale and never needs a temporary image.

## MVP features

- Automatic discovery with a two-second default refresh
- Project and framework detection
- Localhost and LAN URLs
- Bind-address-aware LAN availability
- Full-screen, phone-ready QR overlay
- Open, copy, terminal, editor, restart, and stop actions
- Live server count and list transitions
- Omarchy theme, spacing, typography, and popup primitives
- No daemon, database, account, or network service

## Install

Localhost targets the Quickshell-based Omarchy 4 / Quattro plugin API.

```bash
omarchy plugin add https://github.com/EmilsValdmanis/omarchy-localhost.git --enable
```

It lands in the right side of the bar by default. Move it anywhere with the
normal Omarchy bar controls.

Localhost uses `python3`, `ss`, `ip`, `wl-copy`, and `qrencode`. These are
present in the intended Omarchy environment; `qrencode` is the same tool used
by Omarchy's built-in Wi-Fi QR panel.

## Use it from a phone

Most frameworks bind to localhost by default. Start yours on all interfaces:

```bash
# Vite / SvelteKit
pnpm dev -- --host 0.0.0.0

# Next.js
pnpm dev -- -H 0.0.0.0

# Astro
pnpm dev -- --host 0.0.0.0

# Python
python -m http.server 8000 --bind 0.0.0.0
```

Open Localhost from the bar, choose the server, and click **QR**. Your phone
must be on the same Wi-Fi/LAN, and the machine firewall must allow the port.

## How discovery works

The bundled scanner reads `ss -ltnp`, keeps only processes owned by the current
user, resolves their working directories through `/proc`, and looks for common
project markers and development-server commands. It recognizes popular Node,
Python, Ruby, PHP, Elixir, Rust, and Go workflows without inspecting source
files beyond small project manifests.

Nothing is transmitted anywhere. The LAN address comes from the source address
of the machine's default route; determining it does not contact `1.1.1.1`.

Restart recovers the listening process's command, working directory, and
environment before sending `SIGTERM`, then launches it in a new session. Output
from a restarted process goes to `~/.local/state/omarchy/localhost/`.

## Develop locally

```bash
python3 -m unittest discover -s tests -v
python3 -m py_compile scripts/radar.py
omarchy plugin validate .
qmllint -I /usr/share/omarchy/shell \
  RadarService.qml ServerPanel.qml Widget.qml QrOverlay.qml
```

Install a local checkout after committing it:

```bash
omarchy plugin add "file://$PWD" --enable --yes
```

Plugin changes hot-reload from `~/.config/omarchy/plugins/emils.localhost/`.

## License

MIT
