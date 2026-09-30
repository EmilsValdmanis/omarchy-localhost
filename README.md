# Localhost for Omarchy

[![Built for Omarchy: Plugin](https://raw.githubusercontent.com/tcballard/omarchy-badges/75975e5b5bf75e7ede3764bcd2950046f7abfe2c/badges/v1/omarchy-plugin.svg)](https://github.com/tcballard/omarchy-badges)

Discover, control, and share local development servers from the Omarchy bar.
Start Vite, Next.js, Astro, Rails, or another server and Localhost adds it
automatically.

See [GitHub Releases](https://github.com/EmilsValdmanis/omarchy-localhost/releases)
for version history and release notes.

> `pnpm dev` → Localhost appears → click **QR** → scan with your phone

![Localhost for Omarchy in Everforest: compact RAM summary, memory trends, project groups, and explicit LAN sharing](preview.png)

## Features

- Automatic process, framework, Docker, and Compose discovery
- Repository and monorepo grouping with package-aware framework detection
- Localhost and LAN URLs with bind-address-aware availability
- Open locally, copy local or LAN URLs, QR, terminal, editor, restart, and stop actions
- Search and complete arrow-key or Vim-style navigation
- Phone-ready QR sharing with optional subnet-scoped UFW rules
- Discovery diagnostics, port filters, and LAN-rule management
- Process identity verification before stop or restart
- Native Omarchy styling with no service to install, database, or account
- Compact RAM summary with expandable system and server details
- Live RAM sparkline and usage number for each server
- Independent native and Docker discovery, with slower RAM sampling while closed
- Restart logs capped at 1 MiB each, keeping recent output

Servers in the same repository or workspace appear together, with package paths
under each name. Use the folder button to switch to a flat list sorted by port.
Click a row to select it, then use the shared action toolbar. Moving the pointer
over other rows keeps your selection. **Open** and clicking a port use the local
URL. **Copy local** copies that same URL; **Copy LAN** and **QR** explicitly
share the network URL. Click **Details** beside the RAM summary to expand its
breakdown. Server colors stay tied to process or container identity when the
list changes; ports served by the same process share a color.

LAN-ready servers listen on `0.0.0.0`, `::`, or a LAN interface. Servers bound
to `127.0.0.1` or `::1` remain available for desktop actions, but **Copy LAN**
and **QR** are disabled until they are exposed to the local network.

## Install

Localhost targets the Quickshell-based Omarchy 4 / Quattro plugin API.

```bash
omarchy plugin add https://github.com/EmilsValdmanis/omarchy-localhost.git --enable
```

It appears on the right side of the bar by default. Move it with:

```bash
omarchy bar move emils.localhost --section left   # or center / right
```

The intended Omarchy environment already provides the required system tools:
Python 3.11+, `ss`, `ip`, `curl`, `wl-copy`, and `qrencode`. Docker discovery is
optional and only runs when Docker is available.

## Keyboard

| Key                                  | Action                                                 |
| ------------------------------------ | ------------------------------------------------------ |
| `/` or click search                  | Search by project, framework, port, path, or container |
| `up/down`, `j/k`, `ctrl+p/ctrl+n`    | Select a server                                        |
| `left/right`, `h/l`                  | Select an action in the footer                         |
| `enter`                              | Run the selected action                                |
| `ctrl+c`                             | Copy the selected local URL                            |
| `ctrl+shift+c`                       | Copy the selected LAN URL, when available              |
| `ctrl+m`                             | Expand or collapse RAM details                         |
| `ctrl+r`                             | Refresh discovery                                      |
| `alt+r`                              | Restart the selected server                            |
| `delete`, or `ctrl+k` with no filter | Confirm stopping the selected server                   |
| `esc`                                | Leave search, clear the filter, then close             |

### Optional global shortcut

`SUPER + SHIFT + L` is unassigned in the stock Omarchy 4 keybindings. To use
it to toggle Localhost, add this to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + L", "Localhost", "omarchy-shell emils.localhost toggle")
```

## Use it from a phone

Bind the development server to all interfaces:

```bash
pnpm dev -- --host 0.0.0.0       # Vite, SvelteKit, Astro
pnpm dev -- -H 0.0.0.0           # Next.js
python -m http.server 8000 --bind 0.0.0.0
```

Open Localhost and choose **QR**. Your phone must be on the same Wi-Fi or LAN.
If UFW blocks the port, Localhost can add a persistent inbound TCP rule limited
to the server URL's interface, subnet, and selected port. Rules created by
Localhost can be removed from the shield menu.

LAN discovery resolves the default route's interface address, including routes
without a source address. Set **LAN interface** to an interface name to choose
a different network. A server bound to a specific address uses that address's
interface and subnet for firewall authorization.

## Settings

| Setting              | Purpose                                         |
| -------------------- | ----------------------------------------------- |
| Refresh interval     | Scan native listeners every 1–30 seconds        |
| Show server count    | Show the detected count beside the bar icon     |
| Show when empty      | Keep the widget available with no servers       |
| Include Docker       | Discover browser-ready Docker and Compose ports |
| Ignored ports        | Hide ports or ranges such as `3001,8000-8010`   |
| Always include ports | Probe unusual or unrecognized servers           |
| LAN interface        | Use the default route, or choose an interface such as `wlan0` |
| Authorize LAN access | Offer scoped UFW access before QR sharing       |

## How it works

Localhost reads listening sockets from `ss`, batches process metadata through a
small Python helper, and probes likely development servers over HTTP and HTTPS.
It filters helper sockets, databases, and other non-browser services. Published
Docker ports, including published ranges, have their own metadata and probe
pipeline: a slow Docker daemon cannot delay native results. Docker background
discovery runs no faster than every five seconds while the panel is open, or
15 seconds while closed, and respects a longer configured refresh interval.
Manual refresh (Ctrl+R, the refresh button,
right-clicking the bar icon, or IPC refresh) bypasses HTTP probe caches;
background scans retain caching.
RAM readings use resident memory for native listener processes and Docker's
container memory usage for published services. The total counts a shared
process or container once even if it serves multiple ports. Unavailable
readings are shown as a dash and excluded from the total. RAM sampling is
independent of discovery: native/system RAM runs every two seconds while open
and 15 seconds while closed; Docker RAM runs every eight seconds while open
and 30 seconds while closed. Opening the panel, discovering a new source, and
manual refresh request a fresh sample, so a new row may show a dash briefly.
Sparklines contain the last 30 actual readings, with a slower cadence while
closed; discovery does not repeat cached readings in the history.
The system breakdown uses Linux `MemTotal` and `MemAvailable`; "Free" includes
reclaimable cache. The other bucket includes non-server processes and system
usage. Server portions use resident-memory estimates, so their sum may differ
slightly from physical memory accounting.

Every eligible listening port is checked, including multiple HTTP servers in
one process and fallback ports chosen when a default is busy. Framework labels
use executable arguments and dependencies from the nearest `package.json` or
`pyproject.toml`. Project metadata is read once per discovery batch without
executing project code or searching directory trees.

Grouping uses the nearest Git repository, including worktrees and nested
repositories. Outside Git, it recognizes pnpm, npm/Yarn workspaces, Lerna,
Cargo workspaces, and `go.work`. Native processes and Compose services share a
group when their working directories resolve to the same project root.

Discovery and readiness probes stay on the local machine. Before stopping or
restarting a process, the helper acquires a Linux pidfd, verifies its owner and
start time, and signals through that handle so PID reuse cannot redirect the
signal. Process actions require Python and Linux pidfd support.

Restart is disabled when the executable or runtime entry point cannot be
verified, including rewritten process titles such as `next-server`. Unknown
runtime option layouts are conservatively disabled; restart those servers
from their terminal. The helper rechecks the command and environment and
prepares a private restart log and its collector before stopping the original.
It reports success only after the replacement owns the original listening
address and port and answers
HTTP or HTTPS. Startup exits and the 10-second readiness timeout report failure
with the log path. A replacement still running at the timeout is left running;
check the log before starting another instance. Restart does not reconstruct
parent supervisors or roll back a failed launch. Logs live under
`${XDG_STATE_HOME:-~/.local/state}/omarchy/localhost/`. The newest ten are kept;
each new log is limited to 1 MiB, dropping older output as it fills. A small
detached collector drains stdout/stderr until the restarted server and any
children sharing its output close the pipe. Pruned active logs are drained
without growing deleted files. See [SECURITY.md](SECURITY.md)
for security reporting.

## Remove

Remove Localhost-created firewall rules from the shield menu first, then run:

```bash
omarchy plugin remove emils.localhost
```

If the plugin is already gone, inspect `sudo ufw status numbered` for rules
commented `omarchy-localhost` and remove the matching rule numbers.

## Development

The root keeps the two entry points named in `manifest.json`: `Widget.qml`
for the bar and panel, and `QrOverlay.qml` for phone sharing. Implementation
components live in `qml/`:

| Path                                                                | Responsibility                                         |
| ------------------------------------------------------------------- | ------------------------------------------------------ |
| `qml/RadarService.qml`                                              | Merge discovery results; run actions and RAM sampling |
| `qml/RadarDiscovery.qml`                                            | Independently discover and probe native or Docker servers |
| `qml/RadarModel.js`                                                 | Parse, normalize, filter, and summarize server data    |
| `qml/ServerPanel.qml`, `qml/ServerRow.qml`, `qml/ServerActions.qml` | Render the server list and controls                    |
| `qml/MemorySparkline.qml`, `qml/PanelScrollArea.qml`                | Shared panel pieces                                    |
| `qml/QrService.qml`, `qml/QrContent.qml`, `qml/QrCode.qml`          | QR state and display                                   |
| `localhost_helper.py`, `project_metadata.py`                        | Read Linux and Docker metadata; verify process actions |
| `tests/`                                                            | Model, helper, QML, and preview checks                 |

Data flows from `RadarService` through `RadarModel` into `ServerPanel`. The
Python helper reads OS data; QML handles presentation and interactions. Keep
the manifest entry points at the root and update imports and tests when moving
internal components.

Run the development watcher from the repository root:

```bash
./dev
```

It validates the plugin, creates a guarded development install at
`~/.config/omarchy/plugins/emils.localhost`, enables it when necessary, and
syncs every saved change into that directory. Omarchy then hot-reloads the
plugin automatically, so QML changes appear immediately. Press `ctrl+c` to
stop watching. The development install remains available for the next run;
remove it with `omarchy plugin remove emils.localhost` when it is no longer
needed.

`./dev` will not overwrite a normal Git-installed copy. Move or remove that
copy first if you want to replace it with the development install. Keep a moved
copy outside the active plugin path if you plan to restore it later.

Run the checks before opening a pull request:

```bash
./check
```

This runs model/helper tests, plugin validation, Qt 6 lint, and real Quickshell
UI tests, including native wheel input, model changes while scrolled, keyboard
actions, grouping, QR rendering, and two HTTP listeners in one disposable
process. It also checks the hidden
Wayland entry points when a compositor is available. Screenshots and logs are
saved to `/tmp/localhost-test-artifacts`; your installed plugin is untouched.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow and CI setup.

## License

[MIT](LICENSE)
