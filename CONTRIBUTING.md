# Contributing to Multiterminal

Thanks for helping improve a small, local-first macOS terminal workspace.

## Before you start

- macOS 12 or later
- Xcode Command Line Tools
- Swift 5.9 or newer

## Development workflow

```sh
git clone https://github.com/arjunkshah12345-hash/multiterminal.git
cd multiterminal
swift run
```

Create focused branches and keep pull requests narrow enough to review. For UI work,
include a screenshot or short recording when it clarifies the change.

## Repository map

- `Sources/multiterminal/` — the native AppKit application
- `Tests/` — fast, deterministic unit tests
- `tools/` — app bundle and icon build scripts
- `website/` — the public product site
- `branding/` — source-of-truth visual assets and notes

The app has no storyboard or XIB. Keep state ownership in `Store`, view composition in
the controllers/views, and terminal lifecycle behavior close to `TerminalSession`.

## Verification

Run this before opening a pull request:

```sh
make verify
```

The equivalent checks are `swift test`, the pure layout contract in
`tools/verify_layout.swift`, `swift build -c release`, and `git diff --check`.
If you change the app bundle or icon pipeline, also run `make app` or `make icon` and
smoke-test the result on macOS.

## Design and behavior rules

- Preserve real PTY and login-shell behavior; do not replace shell semantics with a mock.
- Do not add telemetry, accounts, or remote services without an explicit design decision.
- Avoid stealing keyboard focus during store refreshes or project navigation.
- Keep persistence changes backwards-compatible with existing saved projects where possible.
- Treat dropped paths and shell commands as untrusted input; use safe shell quoting.

## Pull requests

Explain the user-facing result, how you tested it, and any macOS-specific limitations.
Behavior changes should include a regression test when practical. Security issues should
be reported privately using the process in [`SECURITY.md`](SECURITY.md), not in a public issue.
