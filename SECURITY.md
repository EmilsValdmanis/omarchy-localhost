# Security Policy

## Supported versions

Security fixes are made on the latest release and the `main` branch. Older
versions may not receive security updates.

## Reporting a vulnerability

Please do not disclose suspected vulnerabilities in a public issue or pull
request. Use GitHub's **Report a vulnerability** form in the repository's
Security tab instead:

https://github.com/EmilsValdmanis/omarchy-localhost/security/advisories/new

Include the affected version or commit, reproduction steps, impact, and any
suggested mitigation. You should receive an acknowledgement within seven days.
Please allow reasonable time for a fix before public disclosure.

## Local privilege boundaries

Localhost only controls processes owned by the current user. Before signaling a
process, its helper verifies both the `/proc` owner and Linux process start time
captured during discovery. Docker actions require the user's existing Docker
daemon access.

When enabled, QR sharing can invoke the fixed `/usr/bin/ufw` executable through
Polkit after an in-plugin confirmation. Rules are limited to the active network
interface, current subnet, selected TCP port, and the `omarchy-localhost`
comment. Localhost never runs its own plugin files as root.
