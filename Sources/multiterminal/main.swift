import AppKit

// Multiterminal — a tiny, fast, native multi-pane terminal with a project sidebar.
//
// Bootstraps a programmatic AppKit app (no storyboards / no .app bundle required):
// runs the shared NSApplication with our AppDelegate, which sets up the window,
// the project sidebar, and the auto-arranging terminal grid.

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.regular)
application.run()
