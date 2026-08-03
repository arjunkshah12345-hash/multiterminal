import AppKit
import SwiftTerm

// MARK: - Grid math

/// Determines rows/cols for a given pane count so the layout is as square / landscape
/// as possible while matching the user's described rules:
///   1 -> 1x1, 2 -> 1x2 (left|right), 3 -> 1x3 (left|middle|right),
///   4 -> 2x2, 5 -> 2x3, 6 -> 2x3, 7 -> 3x3, 9 -> 3x3, 16 -> 4x4, ...
/// Panes are placed left-to-right, top-to-bottom; the final row may be partial.
func gridDimensions(_ n: Int) -> (rows: Int, cols: Int) {
    guard n > 0 else { return (0, 0) }
    let r = Int((sqrt(Double(n))).rounded(.down))
    let rows = max(1, r)
    let cols = Int((Double(n) / Double(rows)).rounded(.up))
    return (rows, cols)
}

// MARK: - TerminalPaneView

/// The chrome around a single terminal: a slim title bar (with title + close button)
/// on top, and the live `LocalProcessTerminalView` filling the rest. Owns nothing about
/// the shell lifecycle — that lives in `TerminalSession`.
final class TerminalPaneView: NSView {

    let terminal: LocalProcessTerminalView

    var onClose: (() -> Void)?

    private let header = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let exitedTag = NSTextField(labelWithString: "")

    private let headerHeight: CGFloat = 22
    private let paneGap: CGFloat = 1

    init(terminal: LocalProcessTerminalView, title: String) {
        self.terminal = terminal
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        setupHeader(title: title)
        setupTerminal()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupHeader(title: String) {
        header.translatesAutoresizingMaskIntoConstraints = false
        header.wantsLayer = true
        header.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        addSubview(header)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.cell?.truncatesLastVisibleLine = true
        header.addSubview(titleLabel)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isBordered = false
        closeButton.isTransparent = false
        closeButton.title = "✕"
        closeButton.font = .systemFont(ofSize: 12, weight: .semibold)
        closeButton.toolTip = "Close pane"
        closeButton.target = self
        closeButton.action = #selector(handleClose)
        closeButton.bezelColor = .clear
        header.addSubview(closeButton)

        exitedTag.translatesAutoresizingMaskIntoConstraints = false
        exitedTag.isHidden = true
        exitedTag.font = .systemFont(ofSize: 10, weight: .medium)
        exitedTag.textColor = .systemRed
        header.addSubview(exitedTag)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: headerHeight),

            titleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            exitedTag.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6),
            exitedTag.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            closeButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -6),
            closeButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 18)
        ])
    }

    private func setupTerminal() {
        terminal.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.topAnchor.constraint(equalTo: header.bottomAnchor),
            terminal.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminal.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    override func layout() {
        super.layout()
        // SwiftTerm recalculates its cell grid in its own `setFrameSize`, so simply
        // letting auto layout pin the terminal to the pane keeps resizing correct.
    }

    // MARK: Public updates

    func setTitle(_ title: String) {
        titleLabel.stringValue = title
    }

    func setExited(suffix: String) {
        exitedTag.stringValue = "exited" + suffix
        exitedTag.isHidden = false
        layer?.backgroundColor = NSColor.underPageBackgroundColor.cgColor
    }

    @objc private func handleClose() {
        onClose?()
    }
}

// MARK: - TerminalGridContainer

/// Lays out the visible project's panes in an auto-arranging grid. Each pane is positioned
/// with a manual frame in `layout()`; the panes' internal Auto Layout pins the terminal
/// to the header, and SwiftTerm recalculates its cell grid on every frame change.
final class TerminalGridContainer: NSView {

    private var panes: [TerminalPaneView] = []
    private let emptyLabel = NSTextField(labelWithString: "")

    private let spacing: CGFloat = 4

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.underPageBackgroundColor.cgColor

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = .systemFont(ofSize: 14, weight: .regular)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Swap the visible panes. Panes that are already on screen (same session) are reused
    /// in place so their shells keep running seamlessly; the rest are added/removed.
    func show(sessions: [TerminalSession], emptyMessage: String) {
        let newPanes = sessions.map { $0.pane }

        // Remove panes no longer visible from our subview hierarchy.
        for pane in panes where !newPanes.contains(where: { $0 === pane }) {
            pane.removeFromSuperview()
        }
        // Add newly visible panes.
        for pane in newPanes where pane.superview == nil {
            addSubview(pane)
        }
        panes = newPanes

        if panes.isEmpty {
            emptyLabel.stringValue = emptyMessage
            emptyLabel.isHidden = false
        } else {
            emptyLabel.isHidden = true
        }
        needsLayout = true
    }

    func focusFirstTerminal() {
        guard let first = panes.first else { return }
        window?.makeFirstResponder(first.terminal)
    }

    override func layout() {
        super.layout()
        guard !panes.isEmpty else { return }

        let n = panes.count
        let (rows, cols) = gridDimensions(n)
        let bounds = self.bounds
        let gap = spacing

        let cellWidth = (bounds.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
        let cellHeight = (bounds.height - gap * CGFloat(rows - 1)) / CGFloat(rows)

        for (i, pane) in panes.enumerated() {
            let row = i / cols
            let col = i % cols
            // AppKit origin is bottom-left; place row 0 at the top.
            let x = CGFloat(col) * (cellWidth + gap)
            let y = bounds.maxY - (CGFloat(row + 1) * cellHeight + CGFloat(row) * gap)
            pane.frame = NSRect(x: x, y: y, width: cellWidth, height: cellHeight)
            // Ensure the terminal reflows to the freshly assigned frame.
            pane.needsLayout = true
        }
    }

    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        needsLayout = true
    }
}
