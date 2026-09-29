# Changelog

## 0.5.1 — 2026-09-29

### Bug Fixes

- Fixed mouse hover changing the selected server while moving to the shared
  action toolbar. Click a row to select it; keyboard navigation and direct port
  opening continue to work as before. ([#14](https://github.com/EmilsValdmanis/omarchy-localhost/pull/14))

### Tests

- Added native mouse regression coverage for row selection, the Stop confirmation
  target, and direct port opening. ([#14](https://github.com/EmilsValdmanis/omarchy-localhost/pull/14))

## 0.5.0 — 2026-09-05

- Publish versioned GitHub Releases automatically after main-branch CI passes,
  using the manifest version and changelog notes.
- Group servers by repository or monorepo, keeping package names and paths;
  support Git worktrees, common workspace manifests, and Compose directories.
- Detect frameworks from executable arguments and nearby package dependencies.
  Probe all eligible listening ports instead of choosing one port per process;
  recognize explicit port arguments and exclude debugger/database sockets.
- Use compact two-line rows, clickable ports, and one shared action toolbar.
  Add a grouped/flat view toggle that preserves the selected server.
- Use native Qt scrolling and the stock Omarchy scrollbar. Keep the viewport
  inside the popup and preserve manual scrolling during discovery updates.
- Make firewall rules and diagnostics scroll on smaller displays.
- Share incremental model updates, reuse server delegates, defer closed-panel
  filtering, and stop timer ticks from queuing continuous scans.
- Honor successful probe expiry and bound Docker discovery to three seconds.
- Render QR codes with one canvas and handle generation cancellation/reopening.
- Use shared Omarchy borders, section headers and separators; display project
  names and process output as plain text. Disable directory actions when no
  project directory is available.
- Add native Quickshell regression/integration tests, Qt 6 lint, Wayland smoke
  checks, a single `./check` command, and native UI coverage in CI.
- Cover framework/port detection, workspace identity, grouped navigation, and
  multiple HTTP listeners in one process. Add a shared marketplace/README
  preview with minimal Everforest branding, the real panel, and a smaller
  QR card, plus a repeatable preview rendering command.
