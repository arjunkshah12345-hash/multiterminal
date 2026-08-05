import AppKit

// MARK: - ProjectCellView

private final class ProjectCellView: NSTableCellView {
    let countLabel = NSTextField(labelWithString: "")
    let pathLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = .systemFont(ofSize: 11, weight: .medium)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right
        addSubview(countLabel)
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        pathLabel.textColor = Brand.accent.withAlphaComponent(0.66)
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.cell?.truncatesLastVisibleLine = true
        addSubview(pathLabel)
        NSLayoutConstraint.activate([
            countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - SidebarView

/// Left-hand project switcher. Each row is a project; selecting it shows that project's
/// grid in the main area. A footer "+" button adds a project; a context menu provides
/// rename / set working directory / delete / new terminal.
final class SidebarView: NSView, NSTableViewDelegate, NSTableViewDataSource {

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let headerLabel = NSTextField(labelWithString: "PROJECTS")
    private let addButton = NSButton()
    private let separator = NSBox()

    weak var store: Store?

    var onSelectProject: ((Int) -> Void)?
    var onAddProject: (() -> Void)?
    var onRenameProject: ((Int, String) -> Void)?
    var onSetWorkingDirectory: ((Int) -> Void)?
    var onDeleteProject: ((Int) -> Void)?
    var onAddTerminalToProject: ((Int) -> Void)?

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = Brand.forestRaised.cgColor

        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        headerLabel.textColor = .secondaryLabelColor
        addSubview(headerLabel)

        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.boxType = .separator
        addSubview(separator)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.headerView = nil
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.style = .sourceList
        tableView.backgroundColor = .clear
        tableView.rowHeight = 42
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("project"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.doubleAction = #selector(handleDoubleAction(_:))
        tableView.target = self
        tableView.menu = buildContextMenu()

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        addSubview(scrollView)

        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.bezelStyle = .smallSquare
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New project")
        addButton.title = "New"
        addButton.imagePosition = .imageLeading
        addButton.toolTip = "New project (⌘N)"
        addButton.target = self
        addButton.action = #selector(handleAdd)
        addButton.isBordered = false
        addSubview(addButton)

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 6),
            headerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),

            separator.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 4),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -2),

            addButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            addButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            addButton.widthAnchor.constraint(equalToConstant: 54),
            addButton.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: Refresh + data source

extension SidebarView {
    func reload() {
        tableView.reloadData()
        let selected = store?.selectedIndex ?? 0
        if (store?.projects.count ?? 0) > 0 {
            tableView.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        store?.projects.count ?? 0
    }
}

// MARK: NSTableViewDelegate

extension SidebarView {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let store = store, store.projects.indices.contains(row) else { return nil }
        let project = store.projects[row]

        let id = NSUserInterfaceItemIdentifier("ProjectCell")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? ProjectCellView)
            ?? {
                let c = ProjectCellView()
                c.identifier = id
                let name = NSTextField(labelWithString: "")
                name.font = .systemFont(ofSize: 13, weight: .medium)
                name.textColor = .labelColor
                name.lineBreakMode = .byTruncatingTail
                name.cell?.truncatesLastVisibleLine = true
                name.translatesAutoresizingMaskIntoConstraints = false
                c.addSubview(name)
                NSLayoutConstraint.activate([
                    name.topAnchor.constraint(equalTo: c.topAnchor, constant: 5),
                    name.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 10),
                    name.trailingAnchor.constraint(lessThanOrEqualTo: c.countLabel.leadingAnchor, constant: -8)
                ])
                c.pathLabel.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    c.pathLabel.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 1),
                    c.pathLabel.leadingAnchor.constraint(equalTo: name.leadingAnchor),
                    c.pathLabel.trailingAnchor.constraint(lessThanOrEqualTo: c.countLabel.leadingAnchor, constant: -8),
                    c.pathLabel.bottomAnchor.constraint(equalTo: c.bottomAnchor, constant: -5)
                ])
                c.textField = name
                return c
            }()
        cell.textField?.stringValue = project.name
        cell.countLabel.stringValue = "\(project.sessions.count)"
        cell.pathLabel.stringValue = (project.workingDirectory as NSString).abbreviatingWithTildeInPath
        cell.pathLabel.textColor = Brand.accent.withAlphaComponent(0.66)
        cell.toolTip = project.workingDirectory
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0 else { return }
        onSelectProject?(row)
    }
}

// MARK: Actions

extension SidebarView {
    @objc private func handleAdd() { onAddProject?() }

    @objc private func handleDoubleAction(_ sender: NSTableView) {
        let row = sender.clickedRow
        guard row >= 0 else { return }
        presentRename(for: row)
    }

    private func presentRename(for row: Int) {
        guard let store = store, store.projects.indices.contains(row) else { return }
        let project = store.projects[row]
        let alert = NSAlert()
        alert.messageText = "Rename Project"
        alert.informativeText = "Enter a new name for \"\(project.name)\"."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = project.name
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard let window = self.window else { return }
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            self.onRenameProject?(row, field.stringValue)
        }
    }
}

// MARK: Context menu

extension SidebarView: NSMenuDelegate {
    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        let items: [(String, Selector)] = [
            ("New Terminal Here", #selector(ctxNewTerminal(_:))),
            ("Rename…", #selector(ctxRename(_:))),
            ("Set Working Directory…", #selector(ctxSetDir(_:))),
            ("Delete Project", #selector(ctxDelete(_:)))
        ]
        for (title, action) in items {
            if title == "Rename…" { menu.addItem(.separator()) }
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let valid = tableView.clickedRow >= 0
        for item in menu.items { item.isEnabled = valid }
    }

    @objc private func ctxNewTerminal(_ sender: Any) {
        let row = tableView.clickedRow
        guard row >= 0 else { return }
        onAddTerminalToProject?(row)
    }

    @objc private func ctxRename(_ sender: Any) {
        let row = tableView.clickedRow
        guard row >= 0 else { return }
        presentRename(for: row)
    }

    @objc private func ctxSetDir(_ sender: Any) {
        let row = tableView.clickedRow
        guard row >= 0 else { return }
        onSetWorkingDirectory?(row)
    }

    @objc private func ctxDelete(_ sender: Any) {
        let row = tableView.clickedRow
        guard row >= 0 else { return }
        onDeleteProject?(row)
    }

    func applyTheme() {
        layer?.backgroundColor = Brand.forestRaised.cgColor
        tableView.reloadData()
    }
}
