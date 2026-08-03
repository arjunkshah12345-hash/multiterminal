import AppKit

// MARK: - ContentViewController

/// Right-hand pane: a thin toolbar (project name + "New Terminal" button) above the
/// auto-arranging terminal grid.
final class ContentViewController: NSViewController {

    let grid = TerminalGridContainer()

    private let toolbar = NSView()
    private let brandMark = NSImageView()
    private let projectLabel = NSTextField(labelWithString: "")
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
        view.layer?.backgroundColor = NSColor.underPageBackgroundColor.cgColor

        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        view.addSubview(toolbar)

        brandMark.translatesAutoresizingMaskIntoConstraints = false
        brandMark.image = NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: "Multiterminal")
        brandMark.contentTintColor = Brand.accent
        brandMark.imageScaling = .scaleProportionallyDown
        toolbar.addSubview(brandMark)

        projectLabel.translatesAutoresizingMaskIntoConstraints = false
        projectLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        projectLabel.textColor = .labelColor
        toolbar.addSubview(projectLabel)

        newTerminalButton.translatesAutoresizingMaskIntoConstraints = false
        newTerminalButton.isBordered = false
        newTerminalButton.contentTintColor = Brand.accent
        newTerminalButton.title = "New Terminal"
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
            toolbar.heightAnchor.constraint(equalToConstant: 30),

            brandMark.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 12),
            brandMark.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            brandMark.widthAnchor.constraint(equalToConstant: 16),
            brandMark.heightAnchor.constraint(equalToConstant: 16),

            projectLabel.leadingAnchor.constraint(equalTo: brandMark.trailingAnchor, constant: 8),
            projectLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            newTerminalButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -8),
            newTerminalButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            grid.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            grid.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            grid.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        self.view = view
    }

    func setProjectTitle(_ title: String, terminalCount: Int) {
        let plural = terminalCount == 1 ? "terminal" : "terminals"
        projectLabel.stringValue = "\(title)  ·  \(terminalCount) \(plural)"
    }

    @objc private func handleNewTerminal() { onNewTerminal?() }
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

    var store: Store! {
        didSet { wire(); reloadFromStore() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let sidebarItem = NSSplitViewItem(viewController: sidebarVC)
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = 200
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
        splitView.setPosition(232, ofDividerAt: 0)
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
        let project = store.selectedProject
        let count = project?.sessions.count ?? 0
        contentVC.setProjectTitle(project?.name ?? "No Project", terminalCount: count)

        // Dynamic window title: "Multiterminal — <project>"
        view.window?.title = project.map { "Multiterminal — \($0.name)" } ?? "Multiterminal"

        let emptyMsg = store.projects.isEmpty
            ? "No projects — press ⌘N to create one"
            : "No terminals — press ⌘T to create one"
        contentVC.grid.show(sessions: project?.sessions ?? [], emptyMessage: emptyMsg)

        // Give the grid a layout pass, then focus the first terminal.
        contentVC.grid.needsLayout = true
        wirePaneContextActions()
        DispatchQueue.main.async { [weak self] in
            self?.contentVC.grid.focusFirstTerminal()
        }
    }

    /// Wire each visible pane's header menu to organize/move actions (idempotent).
    private func wirePaneContextActions() {
        guard let project = store.selectedProject else { return }
        for session in project.sessions {
            let pane = session.pane
            if pane.onContextAction == nil {
                pane.onContextAction = { [weak self] action in
                    self?.handlePaneContext(action, session: session)
                }
            }
            if pane.projectProvider == nil {
                pane.projectProvider = { [weak self] in
                    self?.store.projects.map { ($0.name, $0) } ?? []
                }
            }
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
        store.applyFontToAll()
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

// MARK: - MainWindowController

final class MainWindowController: NSWindowController {
    init(splitViewController: MainSplitViewController) {
        let window = NSWindow(contentViewController: splitViewController)
        window.title = "Multiterminal"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.contentMinSize = NSSize(width: 680, height: 360)
        let frame = NSRect(x: 200, y: 200, width: 1080, height: 680)
        window.setFrame(frame, display: true)
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }
}

