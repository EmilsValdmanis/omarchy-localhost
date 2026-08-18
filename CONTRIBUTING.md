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
node --test tests/test_radar_model.mjs
omarchy plugin validate .
qmllint -I /usr/share/omarchy/shell \
  RadarService.qml ServerPanel.qml Widget.qml QrOverlay.qml
```

The first check is also run by CI. The Omarchy-specific checks require an
Omarchy development environment.

## Pull requests

1. Create a branch from `main`.
2. Add tests for behavior changes where practical.
3. Update documentation when user-facing behavior changes.
4. Open a pull request and complete the checklist.
5. Resolve review conversations and wait for required checks to pass.

By contributing, you agree that your contribution is licensed under the MIT
License used by this repository.
