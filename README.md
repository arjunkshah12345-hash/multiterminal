# Multiterminal

**Your command line, in one beautiful pane.** A tiny, fast, **native macOS** multi-pane terminal
with a project sidebar — real shells, your full history, and panes that arrange themselves.

> 🌐 **[multiterminal.vercel.app](https://multiterminal.vercel.app)** · 🐙 [Public repo](https://github.com/arjunkshah12345-hash/multiterminal)

<img src="assets/app-mockup.svg" width="820" alt="Multiterminal — a project sidebar and a 2×2 grid of terminals" />

---

## Highlights

- **Auto-arranging panes** — open 1, 2, 3, 4, 6, 9… terminals and they balance into a grid.
  No tiling configuration. Then **drag any divider to resize**, or grab a pane and organize.
- **Projects as folders** — pick a folder and it becomes a project, **named after the folder**
  (unless you rename it). Every pane in that project roots at that folder.
- **Real shells, full history** — every pane is a genuine PTY running your login shell (`$SHELL`,
  `zsh`, `bash`, …). Commands, aliases, and history all behave exactly like Terminal.app.
- **Pick up where you left off** — quit and relaunch, and Multiterminal restores your projects,
  their folders, and pane counts from your last session.
- **Resize & organize** — drag dividers to resize panes; right-click a pane header to move it
  left/right or into another project.
- **Style it your way** — System / Light / Dark chrome plus a terminal font size, all in one
  settings sheet (`⌘,`), applied live.
- **Fast & local** — native Swift + AppKit on the [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)
  engine. No Electron, no browser, no webview, no account, no telemetry.

<h3>Panes that stay out of your way</h3>
<p align="center">
  <img src="assets/layout.svg" width="820" alt="Layout diagram: 1, 2, 3, 4, 6 and 9 panes auto-arranged" />
</p>

---

## Install

Requires **macOS 12+** and the Swift toolchain.

```sh
git clone https://github.com/arjunkshah12345-hash/multiterminal.git
cd multiterminal
swift run                                   # build & run
```

Or build a double-clickable `.app` with the real icon:

```sh
sh tools/build_app.sh release
open Multiterminal.app
```

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| `⌘T` | New terminal in the current project |
| `⌘N` | New project |
| `⌘O` | Open folder as project |
| `⌘,` | Settings (appearance + font size) |
| `⌘W` | Close the focused terminal |
| Right-click pane header | Move left / right / to another project |
| Drag a divider | Resize the neighboring panes |

---

## How it works

Pure Swift + AppKit, no storyboards or XIBs. Terminal emulation comes from
[Miguel de Icaza's **SwiftTerm**](https://github.com/migueldeicaza/SwiftTerm) — specifically
`LocalProcessTerminalView`, a real pseudo-terminal running your shell. Projects and pane counts
persist in `UserDefaults`, so the app reopens your last session on launch.

| Path | Role |
| --- | --- |
| `main.swift` | Boots `NSApplication` |
| `AppDelegate.swift` | Menu, keyboard shortcuts, settings wiring |
| `Store.swift` | Projects / sessions, persistence, working-dir → default name |
| `MainWindowController.swift` | Split view (sidebar \| grid), toolbar, wiring |
| `SidebarView.swift` | Project list + context menu |
| `TerminalGrid.swift` | Auto-arrange layout, pane chrome, **resizable dividers**, organize menu |
| `Settings.swift` | Appearance + font-size preferences |

## Tooling

- `tools/build_icon.sh` — regenerates the app icon (`assets/AppIcon.icns`).
- `tools/build_app.sh [release|debug]` — assembles `Multiterminal.app`.
- `website/` — the marketing site (deployed to **multiterminal.vercel.app**).

---
© 2026 ideatr · Made native, kept simple.
