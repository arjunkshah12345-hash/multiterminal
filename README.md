# Multiterminal

A tiny, fast, **native macOS** multi-pane terminal with a project sidebar.

- One window, panes auto-arranged into a balanced grid:
  - 1 → full · 2 → left | right · 3 → left | middle | right · 4 → 2×2
  - 5 → 2×3 · 6 → 2×3 · 9 → 3×3 · 16 → 4×4 (rule: `rows = ⌊√n⌋`, `cols = ⌈n/rows⌉`, filled left→right, top→bottom)
- **Left sidebar** lists your projects; click one to swap to that project's set of panes.
  Every shell keeps running in the background when you switch projects.
- Each pane is a **real terminal** (real PTY + your `$SHELL`, login shell) — do everything
  you'd normally do. Pane header shows the title (from the shell) and a ✕ to close.
- `⌘N` new project · `⌘T` new terminal · `⌘W` close focused terminal · `⌘Q` quit.
  Right-click a project in the sidebar for rename / set working directory / delete / new terminal here.

## Requirements
- macOS 12+ and the Swift toolchain (`xcode-select --install` gives you `swift`).

## Build & run
```sh
swift run            # builds (first run downloads SwiftTerm) and launches the app
```
Build only:
```sh
swift build -c release      # fast, optimized binary
.build/release/multiterminal
```

## How it's built
Pure Swift + AppKit, no storyboards/XIBs, no `.app` bundle needed. Terminal emulation by
[Miguel de Icaza's SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (`LocalProcessTerminalView`
= real PTY). Layout is a single `Package.swift` + a handful of files in `Sources/multiterminal/`.

| File | Role |
|---|---|
| `Package.swift` | SwiftPM manifest; depends on SwiftTerm |
| `main.swift` | boots `NSApplication` |
| `AppDelegate.swift` | window + main menu + keyboard shortcuts |
| `MainWindowController.swift` | split view (sidebar \| content) + toolbar + wiring |
| `SidebarView.swift` | project list (source-list `NSTableView`) + context menu |
| `TerminalGrid.swift` | grid math, per-pane chrome, auto-arranging grid container |
| `Store.swift` | `Project` / `TerminalSession` / `Store` (state + mutations) |

## Notes
- The app is **not sandboxed** (SPM executable, no entitlements), so spawned shells have full
  access — that's intentional and required for a usable terminal.
- To make a real `.app` you can double-click, wrap the binary:
  ```sh
  mkdir -p Multiterminal.app/Contents/MacOS
  cp .build/release/multiterminal Multiterminal.app/Contents/MacOS/
  # then optionally add an Info.plist under Contents/
  ```
