import AppKit

// MARK: - ContentViewController

/// Right-hand pane: a compact workspace toolbar above the live, editable terminal grid.
final class ContentViewController: NSViewController {

    let grid = TerminalGridContainer()

    private let toolbar = NSView()
    private let brandMark = NSImageView()
    private let projectLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let layoutControl = NSPopUpButton()
    private let newTerminalButton = NSButton()

    var onNewTerminal: (() -> Void)?

    init() {
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = Brand.forest.cgColor

        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = Brand.forestRaised.cgColor
        view.addSubview(toolbar)

        brandMark.translatesAutoresizingMaskIntoConstraints = false
        brandMark.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Multiterminal")
        brandMark.contentTintColor = Brand.accent
        brandMark.imageScaling = .scaleProportionallyDown
        toolbar.addSubview(brandMark)

        projectLabel.translatesAutoresizingMaskIntoConstraints = false
        projectLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        projectLabel.textColor = Brand.terminalText
        projectLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        toolbar.addSubview(projectLabel)

        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        pathLabel.textColor = Brand.accent.withAlphaComponent(0.7)
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.cell?.truncatesLastVisibleLine = true
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        toolbar.addSubview(pathLabel)

        layoutControl.translatesAutoresizingMaskIntoConstraints = false
        layoutControl.addItems(withTitles: Layout.allCases.map(\.label))
        layoutControl.selectItem(at: Layout.allCases.firstIndex(of: Settings.shared.layoutMode) ?? 0)
        layoutControl.font = .systemFont(ofSize: 11, weight: .medium)
        layoutControl.toolTip = "Choose the pane arrangement"
        layoutControl.target = self
        layoutControl.action = #selector(handleLayoutChange)
        toolbar.addSubview(layoutControl)

        newTerminalButton.translatesAutoresizingMaskIntoConstraints = false
        newTerminalButton.isBordered = false
        newTerminalButton.contentTintColor = Brand.accent
        newTerminalButton.title = "New"
        newTerminalButton.image = NSImage(systemSymbolName: "plus.square", accessibilityDescription: nil)
        newTerminalButton.imagePosition = .imageLeading
        newTerminalButton.toolTip = "New terminal (⌘T)"
        newTerminalButton.target = self
        newTerminalButton.action = #selector(handleNewTerminal)
        toolbar.addSubview(newTerminalButton)

        grid.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(grid)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: view.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 28),

            brandMark.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 12),
            brandMark.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            brandMark.widthAnchor.constraint(equalToConstant: 14),
            brandMark.heightAnchor.constraint(equalToConstant: 14),

            projectLabel.leadingAnchor.constraint(equalTo: brandMark.trailingAnchor, constant: 8),
            projectLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            pathLabel.leadingAnchor.constraint(equalTo: projectLabel.trailingAnchor, constant: 8),
            pathLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            pathLabel.trailingAnchor.constraint(lessThanOrEqualTo: layoutControl.leadingAnchor, constant: -10),

            layoutControl.trailingAnchor.constraint(equalTo: newTerminalButton.leadingAnchor, constant: -8),
            layoutControl.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            layoutControl.widthAnchor.constraint(equalToConstant: 78),

            newTerminalButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -10),
            newTerminalButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            grid.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            grid.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            grid.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        self.view = view
    }

    func setProjectTitle(_ title: String, terminalCount: Int, workingDirectory: String?) {
        let plural = terminalCount == 1 ? "terminal" : "terminals"
        projectLabel.stringValue = "\(title)  ·  \(terminalCount) \(plural)"
        pathLabel.stringValue = workingDirectory ?? "No project selected"
        pathLabel.toolTip = workingDirectory
    }

    func applySettings() {
        grid.layoutMode = Settings.shared.layoutMode
        layoutControl.selectItem(at: Layout.allCases.firstIndex(of: Settings.shared.layoutMode) ?? 0)
    }

    func applyThemeToChrome() {
        view.layer?.backgroundColor = Brand.forest.cgColor
        toolbar.layer?.backgroundColor = Brand.forestRaised.cgColor
        brandMark.contentTintColor = Brand.accent
        projectLabel.textColor = Brand.terminalText
        pathLabel.textColor = Brand.accent.withAlphaComponent(0.7)
        newTerminalButton.contentTintColor = Brand.accent
        grid.applyThemeToChrome()
    }

    @objc private func handleNewTerminal() { onNewTerminal?() }

    @objc private func handleLayoutChange(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard Layout.allCases.indices.contains(index) else { return }
        Settings.shared.layoutMode = Layout.allCases[index]
    }
}

// MARK: - SidebarViewController

final class SidebarViewController: NSViewController {
    let sidebar = SidebarView()
    init() { super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    override func loadView() {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(sidebar)
        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: v.topAnchor),
            sidebar.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            sidebar.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            sidebar.bottomAnchor.constraint(equalTo: v.bottomAnchor)
        ])
        self.view = v
    }
}

// MARK: - MainSplitViewController

/// Owns the sidebar + content split, wires all sidebar callbacks to the store, and
/// refreshes the whole UI whenever the store changes (project switch, add/remove, etc.).
final class MainSplitViewController: NSSplitViewController {

    let sidebarVC = SidebarViewController()
    let contentVC = ContentViewController()
    private var displayedProjectID: UUID?
    private var quickViewController: SessionQuickViewController?

    var store: Store! {
        didSet { wire(); reloadFromStore() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let sidebarItem = NSSplitViewItem(viewController: sidebarVC)
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 360
        sidebarItem.holdingPriority = .defaultLow + 1
        sidebarItem.preferredThicknessFraction = 0.0

        let contentItem = NSSplitViewItem(viewController: contentVC)
        contentItem.canCollapse = false
        contentItem.holdingPriority = .defaultLow
        contentItem.minimumThickness = 360

        splitView.dividerStyle = .thin
        splitView.isVertical = true        // vertical dividers -> side-by-side panes
        splitViewItems = [sidebarItem, contentItem]
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Initial sidebar width.
        splitView.setPosition(220, ofDividerAt: 0)
    }

    // MARK: Wiring

    private func wire() {
        let sidebar = sidebarVC.sidebar
        sidebar.store = store

        sidebar.onSelectProject = { [weak self] row in
            self?.store.selectProject(at: row)
        }
        sidebar.onAddProject = { [weak self] in
            self?.store.addProject()
        }
        sidebar.onRenameProject = { [weak self] row, name in
            self?.store.renameProject(at: row, to: name)
        }
        sidebar.onSetWorkingDirectory = { [weak self] row in
            self?.presentSetDirectory(for: row)
        }
        sidebar.onDeleteProject = { [weak self] row in
            self?.store.deleteProject(at: row)
        }
        sidebar.onAddTerminalToProject = { [weak self] row in
            guard let self = self, row < self.store.projects.count else { return }
            self.store.selectProject(at: row)
            self.store.addTerminal(to: self.store.projects[row])
        }

        contentVC.onNewTerminal = { [weak self] in
            self?.store.addTerminal()
        }

        store.onChange = { [weak self] in
            self?.reloadFromStore()
        }
    }

    // MARK: Refresh

    func reloadFromStore() {
        sidebarVC.sidebar.reload()
        quickViewController?.reload()
        let project = store.selectedProject
        let projectChanged = displayedProjectID != project?.id
        displayedProjectID = project?.id
        let count = project?.sessions.count ?? 0
        contentVC.setProjectTitle(project?.name ?? "No Project",
                                  terminalCount: count,
                                  workingDirectory: project?.workingDirectory)

        // Dynamic window title keeps the active project visible in macOS window switchers.
        view.window?.title = project.map { "Multiterminal - \($0.name)" } ?? "Multiterminal"

        let emptyMsg = store.projects.isEmpty
            ? "No projects - press ⌘N to create one"
            : "No terminals - press ⌘T to create one"
        contentVC.grid.show(sessions: project?.sessions ?? [], emptyMessage: emptyMsg)

        // Give the grid a layout pass, then focus only when the visible project changed
        // or the previous responder disappeared. Shell title/cwd updates also call this
        // method; refocusing here used to jump typing into pane one.
        contentVC.grid.needsLayout = true
        wirePaneContextActions()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if projectChanged || !self.contentVC.grid.hasFocusedTerminal() {
                self.contentVC.grid.focusFirstTerminal()
            }
        }
    }

    /// Wire each visible pane's header menu to organize/move actions (idempotent).
    private func wirePaneContextActions() {
        guard let project = store.selectedProject else { return }
        for session in project.sessions {
            let pane = session.pane
            if pane.onContextAction == nil {
                pane.onContextAction = { [weak self, weak session] action in
                    guard let session else { return }
                    self?.handlePaneContext(action, session: session)
                }
            }
            if pane.projectProvider == nil {
                pane.projectProvider = { [weak self, weak session] in
                    guard let self, let session else { return [] }
                    let current = self.store.projects.first {
                        $0.sessions.contains { $0 === session }
                    }
                    return self.store.projects
                        .filter { $0 !== current }
                        .map { ($0.name, $0) }
                }
            }
            if pane.onRename == nil {
                pane.onRename = { [weak self, weak session] in
                    guard let self, let session else { return }
                    self.presentPaneRename(for: session)
                }
            }
        }
    }

    private func presentPaneRename(for session: TerminalSession) {
        let alert = NSAlert()
        alert.messageText = "Rename Pane"
        alert.informativeText = "Enter a name for this terminal."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = session.title
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard let window = view.window else { return }
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            session.rename(to: field.stringValue)
        }
    }

    private func handlePaneContext(_ action: PaneContextAction, session: TerminalSession) {
        switch action {
        case .moveLeft: store.moveTerminal(session, by: -1)
        case .moveRight: store.moveTerminal(session, by: 1)
        case .moveToProject(let target): store.moveTerminal(session, to: target)
        }
    }

    /// Apply the current Appearance setting to the window (called at launch + on change).
    func applyAppearance() {
        view.window?.appearance = Settings.shared.appearance.nsAppearance
    }

    /// Present the Settings sheet (⌘,).
    func presentSettings() {
        let vc = SettingsViewController()
        vc.onChange = { [weak self] in self?.applySettingsLive() }
        let sheet = NSWindow(contentViewController: vc)
        sheet.styleMask = [.titled]
        sheet.title = "Settings"
        view.window?.beginSheet(sheet)
    }

    /// Apply appearance + font size to all terminals (live).
    func applySettingsLive() {
        applyAppearance()
        applyThemeToChrome()
        contentVC.applySettings()
        store.applyFontToAll()
        store.applyThemeToAll()
    }

    func applyThemeToChrome() {
        view.window?.backgroundColor = Brand.forest
        contentVC.applyThemeToChrome()
        sidebarVC.sidebar.applyTheme()
    }

    /// Toggle the optional floating session navigator (⌘⇧P).
    func toggleSessionQuickView() {
        if let quickViewController {
            if quickViewController.window?.isVisible == true {
                quickViewController.close()
            } else {
                quickViewController.showWindow(nil)
                quickViewController.window?.orderFront(nil)
            }
            return
        }

        let controller = SessionQuickViewController(store: store)
        controller.onSelect = { [weak self] project, session in
            guard let self,
                  let index = self.store.projects.firstIndex(where: { $0 === project }) else { return }
            self.store.selectProject(at: index)
            self.view.window?.makeKeyAndOrderFront(nil)
            DispatchQueue.main.async { [weak self] in
                self?.contentVC.grid.focus(session)
            }
        }
        quickViewController = controller
        controller.showWindow(nil)
        controller.window?.center()
    }

    // MARK: Helpers

    private func presentSetDirectory(for row: Int) {
        guard store.projects.indices.contains(row) else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.title = "Working Directory for \(store.projects[row].name)"
        if !store.projects[row].workingDirectory.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: store.projects[row].workingDirectory)
        }
        panel.beginSheetModal(for: view.window!) { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }
            self.store.setWorkingDirectory(forProjectAt: row, to: url)
        }
    }

    /// Close the terminal pane that currently has keyboard focus (if any).
    func closeFocusedTerminal() {
        guard let fr = view.window?.firstResponder as? NSView else { return }
        // Walk up to find the pane's TerminalPaneView.
        var current: NSView? = fr
        while let v = current {
            if let pane = v as? TerminalPaneView {
                if let session = store.selectedProject?.sessions.first(where: { $0.pane === pane }) {
                    store.removeTerminal(session)
                }
                return
            }
            current = v.superview
        }
    }
}

// MARK: - KeyWindow

/// A window that reports every first-responder change so the terminal grid can update
/// its per-pane focus accent without polling. `makeFirstResponder(_:)` is `open` on
/// NSWindow, so this works even for SwiftTerm's (non-`open`) terminal view.
final class KeyWindow: NSWindow {
    var onFirstResponderChange: (() -> Void)?

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let did = super.makeFirstResponder(responder)
        if did { onFirstResponderChange?() }
        return did
    }
}

// MARK: - MainWindowController

final class MainWindowController: NSWindowController {
    init(splitViewController: MainSplitViewController) {
        let window = KeyWindow(contentViewController: splitViewController)
        window.title = "Multiterminal"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = Brand.forest
        window.contentMinSize = NSSize(width: 680, height: 360)
        // Remember where the user put the window across launches.
        window.setFrameAutosaveName("MultiterminalMain")
        if UserDefaults.standard.object(forKey: "NSWindow Frame MultiterminalMain") == nil {
            let frame = NSRect(x: 200, y: 200, width: 1080, height: 680)
            window.setFrame(frame, display: true)
            window.center()
        }
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }
}
