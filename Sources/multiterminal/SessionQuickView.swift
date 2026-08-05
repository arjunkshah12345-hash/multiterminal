import AppKit

// MARK: - Session Quick View

private final class SessionQuickViewCell: NSTableCellView {

    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        addSubview(detailLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            detailLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, detail: String) {
        titleLabel.stringValue = title
        detailLabel.stringValue = detail
    }
}

/// A small floating navigator for every live terminal session. Selecting a row changes
/// projects when needed, brings the main window forward, and focuses that exact pane.
final class SessionQuickViewController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

    private struct Row {
        let project: Project
        let session: TerminalSession
    }

    private let store: Store
    private let tableView = NSTableView()
    private let emptyLabel = NSTextField(labelWithString: "No terminal sessions")
    private var rows: [Row] = []

    var onSelect: ((Project, TerminalSession) -> Void)?

    init(store: Store) {
        self.store = store

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 440),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Session Quick View"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        panel.minSize = NSSize(width: 300, height: 240)

        super.init(window: panel)
        configureView()
        reload()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func configureView() {
        guard let contentView = window?.contentView else { return }

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("session"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = 52
        tableView.style = .sourceList
        tableView.doubleAction = #selector(handleDoubleClick(_:))
        tableView.target = self

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = tableView
        contentView.addSubview(scrollView)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        contentView.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 20),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20)
        ])
    }

    func reload() {
        rows = store.projects.flatMap { project in
            project.sessions.map { Row(project: project, session: $0) }
        }
        tableView.reloadData()
        emptyLabel.isHidden = !rows.isEmpty
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("SessionQuickViewCell")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? SessionQuickViewCell)
            ?? {
                let view = SessionQuickViewCell()
                view.identifier = identifier
                return view
            }()
        let item = rows[row]
        let status = item.session.isAlive ? "Running" : "Exited"
        cell.configure(
            title: item.session.title,
            detail: item.project.name + "  ·  " + status
        )
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard rows.indices.contains(row) else { return }
        onSelect?(rows[row].project, rows[row].session)
    }

    @objc private func handleDoubleClick(_ sender: NSTableView) {
        let row = sender.clickedRow
        guard rows.indices.contains(row) else { return }
        onSelect?(rows[row].project, rows[row].session)
    }
}
