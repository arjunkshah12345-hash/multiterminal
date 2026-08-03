import AppKit

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let store = Store()
    private var splitVC: MainSplitViewController!
    private var windowController: MainWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        splitVC = MainSplitViewController()
        splitVC.store = store              // triggers wiring + initial refresh

        windowController = MainWindowController(splitViewController: splitVC)
        windowController.window?.makeKeyAndOrderFront(nil)

        NSApp.mainMenu = buildMainMenu()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: Menu actions

    @objc private func newProject(_ sender: Any?) { store.addProject() }
    @objc private func newTerminal(_ sender: Any?) { store.addTerminal() }
    @objc private func closeTerminal(_ sender: Any?) { splitVC.closeFocusedTerminal() }
    @objc private func about(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Multiterminal",
            .applicationVersion: "1.0",
            .version: "1.0"
        ])
    }

    // MARK: Main menu

    private func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = menu(titled: "Multiterminal", items: [
            .standard("About Multiterminal", #selector(about), ""),
            .separator,
            .systemAction("Hide Multiterminal", #selector(NSApplication.hide(_:)), "h"),
            .systemAction("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            .systemAction("Show All", #selector(NSApplication.unhideAllApplications(_:)), ""),
            .separator,
            .systemAction("Quit Multiterminal", #selector(NSApplication.terminate(_:)), "q")
        ])
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = menu(titled: "File", items: [
            .target("New Project", #selector(newProject), "n"),
            .target("New Terminal", #selector(newTerminal), "t"),
            .separator,
            .target("Close Terminal", #selector(closeTerminal), "w")
        ])
        mainMenu.addItem(fileMenuItem)

        // Edit menu — standard selectors the terminal (responder chain) implements.
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = menu(titled: "Edit", items: [
            .systemAction("Cut", NSSelectorFromString("cut:"), "x"),
            .systemAction("Copy", NSSelectorFromString("copy:"), "c"),
            .systemAction("Paste", NSSelectorFromString("paste:"), "v"),
            .systemAction("Select All", NSSelectorFromString("selectAll:"), "a")
        ])
        mainMenu.addItem(editMenuItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = menu(titled: "Window", items: [
            .systemAction("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            .systemAction("Zoom", #selector(NSWindow.performZoom(_:)), "")
        ])
        windowMenuItem.submenu?.items.last?.keyEquivalentModifierMask = [.command, .option]
        mainMenu.addItem(windowMenuItem)

        return mainMenu
    }

    private enum ItemSpec {
        case target(String, Selector, String)
        case systemAction(String, Selector, String, NSEvent.ModifierFlags = .command)
        case standard(String, Selector, String)
        case separator
    }

    private func menu(titled title: String, items: [ItemSpec]) -> NSMenu {
        let menu = NSMenu(title: title)
        for spec in items {
            switch spec {
            case .separator:
                menu.addItem(.separator())
            case let .target(name, action, key):
                let item = NSMenuItem(title: name, action: action, keyEquivalent: key)
                item.target = self
                menu.addItem(item)
            case let .systemAction(name, action, key, mods):
                let item = NSMenuItem(title: name, action: action, keyEquivalent: key)
                item.target = nil
                item.keyEquivalentModifierMask = mods
                menu.addItem(item)
            case let .standard(name, action, key):
                let item = NSMenuItem(title: name, action: action, keyEquivalent: key)
                item.target = self
                menu.addItem(item)
            }
        }
        return menu
    }
}
