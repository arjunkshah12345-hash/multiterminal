import AppKit

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let store = Store()
    private var splitVC: MainSplitViewController!
    private var windowController: MainWindowController!
    private var mcpServer: MCPServer!

    func applicationDidFinishLaunching(_ notification: Notification) {
        splitVC = MainSplitViewController()
        splitVC.store = store              // triggers wiring + initial refresh

        windowController = MainWindowController(splitViewController: splitVC)
        windowController.window?.makeKeyAndOrderFront(nil)

        mcpServer = MCPServer(store: store) { [weak self] session in
            guard let self else { return }
            self.windowController.window?.makeKeyAndOrderFront(nil)
            DispatchQueue.main.async { [weak self] in
                self?.splitVC.contentVC.grid.focus(session)
            }
        }
        mcpServer.start()

        NSApp.mainMenu = buildMainMenu()
        NSApp.activate(ignoringOtherApps: true)
        CommandNotificationCenter.shared.requestAuthorization()

        // Apply persisted settings (appearance + font) and react to live changes.
        Settings.shared.onChange = { [weak self] in self?.applySettings() }
        applySettings()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        mcpServer?.stop()
    }

    // MARK: Menu actions

    @objc private func newProject(_ sender: Any?) { store.addProject() }
    @objc private func openFolderAsProject(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Open"
        panel.title = "Open Folder as Project"
        guard let window = windowController?.window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }
            self.store.addProject(fromFolder: url)
        }
    }
    @objc private func newTerminal(_ sender: Any?) {
        // Continue where you are: a new pane opens in the focused pane's directory
        // (when known) instead of always falling back to the project root.
        let cwd = splitVC.contentVC.grid.focusedPane().flatMap { pane -> String? in
            store.projects
                .flatMap { $0.sessions }
                .first { $0.pane === pane }?
                .workingDirectory
        }
        store.addTerminal(in: cwd)
    }
    @objc private func closeTerminal(_ sender: Any?) { splitVC.closeFocusedTerminal() }
    @objc private func clearScreen(_ sender: Any?) { splitVC.contentVC.grid.clearFocusedScreen() }
    @objc private func focusNextPane(_ sender: Any?) { splitVC.contentVC.grid.focusNext() }
    @objc private func focusPreviousPane(_ sender: Any?) { splitVC.contentVC.grid.focusPrevious() }
    @objc private func presentSettings(_ sender: Any?) { splitVC.presentSettings() }
    @objc private func toggleSessionQuickView(_ sender: Any?) { splitVC.toggleSessionQuickView() }
    @objc private func about(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Multiterminal",
            .applicationVersion: "1.0",
            .version: "1.0"
        ])
    }

    /// Apply the persisted workspace appearance to the window and every live terminal.
    private func applySettings() {
        splitVC.applyAppearance()
        splitVC.applyThemeToChrome()
        splitVC.contentVC.applySettings()
        store.applyFontToAll()
        store.applyThemeToAll()
    }

    // MARK: Main menu

    private func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = menu(titled: "Multiterminal", items: [
            .standard("About Multiterminal", #selector(about), ""),
            .target("Copy MCP Configuration", #selector(copyMCPConfiguration), ""),
            .separator,
            .target("Settings…", #selector(presentSettings), ","),
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
            .target("Open Folder as Project…", #selector(openFolderAsProject), "o"),
            .target("New Terminal", #selector(newTerminal), "t"),
            .separator,
            .target("Close Terminal", #selector(closeTerminal), "w")
        ])
        mainMenu.addItem(fileMenuItem)

        // View menu
        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = menu(titled: "View", items: [
            .target("Focus Next Pane", #selector(focusNextPane), "]"),
            .target("Focus Previous Pane", #selector(focusPreviousPane), "["),
            .separator,
            .targetWithModifiers("Session Quick View", #selector(toggleSessionQuickView), "p", [.command, .shift])
        ])
        mainMenu.addItem(viewMenuItem)

        // Edit menu — standard selectors the terminal (responder chain) implements.
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = menu(titled: "Edit", items: [
            .systemAction("Cut", NSSelectorFromString("cut:"), "x"),
            .systemAction("Copy", NSSelectorFromString("copy:"), "c"),
            .systemAction("Paste", NSSelectorFromString("paste:"), "v"),
            .systemAction("Select All", NSSelectorFromString("selectAll:"), "a"),
            .target("Clear Screen", #selector(clearScreen), "k")
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

    @objc private func copyMCPConfiguration(_ sender: Any?) {
        mcpServer.copyConfigurationToPasteboard()
    }

    private enum ItemSpec {
        case target(String, Selector, String)
        case targetWithModifiers(String, Selector, String, NSEvent.ModifierFlags)
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
            case let .targetWithModifiers(name, action, key, modifiers):
                let item = NSMenuItem(title: name, action: action, keyEquivalent: key)
                item.target = self
                item.keyEquivalentModifierMask = modifiers
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
