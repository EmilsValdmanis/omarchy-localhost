# Contributing

Thanks for helping improve Localhost.

## Before you start

- Search existing issues before opening a new one.
- Use an issue template for bugs and feature requests.
- Keep changes focused. For a substantial behavior or UI change, open an issue
  first so the approach can be agreed on before implementation.
- Report security vulnerabilities privately as described in
  [SECURITY.md](SECURITY.md).

## Development

Localhost targets the Quickshell-based Omarchy 4 / Quattro plugin API. Run the
available checks before opening a pull request:

```bash
./check
```

`./check` runs the JavaScript and Python tests, manifest validation, Qt 6 QML
lint, and native UI tests inside an isolated Quickshell instance. It also loads
both hidden entry points on Wayland when a local display is available. It does
not install the plugin or change your bar configuration.

The UI suite sends native wheel and keyboard events, checks scrolling after
model changes, verifies small popups and font scaling, tests QR pixels and
process cancellation, grouping and shared actions, and discovers/stops a
disposable process with two loopback HTTP listeners. Model and helper tests
cover framework arguments, port selection, and repository/workspace metadata.
Only that fixture's verified PID is stopped. Screenshots and logs go to
`/tmp/localhost-test-artifacts` (override with `LOCALHOST_TEST_ARTIFACTS`).

For systems without Omarchy, run the portable checks:

```bash
node --test --test-isolation=none tests/*.mjs
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

CI runs those checks plus native QML lint and runtime tests on Arch Linux with
Quickshell and Omarchy v4.0.2's actual shared components. The native tests require
Qt 6, `ss`, `curl`, Python 3.11+ and `qrencode`; no desktop session is needed. Set
`OMARCHY_PATH` to test another Omarchy checkout. `tests/lint_qml.py` explicitly
uses Qt 6 (`QMLLINT` can override its path), allows only documented upstream
metadata gaps, and rejects other warnings. Wayland entry-point loading requires
a local compositor and is covered by `./check` on Omarchy.

## Preview image

Regenerate the shared marketplace and README preview after UI changes:

```bash
python3 tests/run_qml.py --previews
```

This renders a single 1600×900 `preview.png` with the Localhost title,
a concise feature list, the actual panel, and a smaller QR card. It uses fixed
demo data, Omarchy's Everforest palette and tree-tops wallpaper, iA Writer
Quattro, and JetBrains Mono. The wallpaper is read from the installed Omarchy
theme (or `OMARCHY_PATH`); it is not duplicated in this repository. Inspect the image before
committing. The composition lives in `tests/qml/previews.qml`.
The preview QR links to Rick Astley's video as an easter egg.
Set `LOCALHOST_PREVIEW_DIR` to save it somewhere else. Rendering uses an
isolated Quickshell instance and does not change your desktop theme.

## Pull requests

1. Create a branch from `main`.
2. Add tests for behavior changes where practical.
3. Update documentation when user-facing behavior changes.
4. Open a pull request and complete the checklist.
5. Resolve review conversations and wait for required checks to pass.

## Releases

To ship a stable version, update `manifest.json` and add a matching entry at the
top of `CHANGELOG.md` in the same PR. Use a `major.minor.patch` version and a
heading such as `## 0.5.1 — 2026-09-06`, followed by the user-facing changes.
`./check` and CI require matching, nonempty notes.

Group changes under level-three headings such as `### Features`, `### Bug Fixes`,
and `### Tests`, omitting empty sections. Describe the user-visible change and
link its pull request. GitHub release titles contain only the version (for
example, `v0.5.1`). The publisher uses GitHub-generated release notes with
"What's Changed", pull request links, contributor credits, and a full changelog
comparison link. GitHub includes "New Contributors" when applicable.

After the PR merges, CI runs on `main`. Once both test jobs pass, it creates
the version tag and publishes a GitHub Release with those generated notes.
Commits with an already published version leave its release unchanged. No
personal token or manual tag push is required. Publishing is restricted to
the tested commit while it is still the current `main` commit. Rerun the CI
workflow after a transient publication failure; existing releases are preserved.

Marketplace verification is a separate step after release: submit the full
merged commit SHA through the [verification form](https://github.com/omacom/omarchy-plugin-marketplace/issues/new?template=verify-plugin.yml),
selecting “Verify and publish a newer upstream commit”. Verification covers
that exact commit and requires the marketplace's checks and maintainer approval.

By contributing, you agree that your contribution is licensed under the MIT
License used by this repository.
