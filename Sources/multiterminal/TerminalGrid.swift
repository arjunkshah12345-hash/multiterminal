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

// MARK: - PaneContextAction

enum PaneContextAction {
    case moveLeft
    case moveRight
    case moveToProject(Project)
}

// MARK: - TerminalPaneView

/// The chrome around a single terminal: a slim title bar (with title + close button)
/// on top, and the live `LocalProcessTerminalView` filling the rest. Owns nothing about
/// the shell lifecycle — that lives in `TerminalSession`.
final class TerminalPaneView: NSView, NSMenuDelegate {

    let terminal: LocalProcessTerminalView

    var onClose: (() -> Void)?
    var onContextAction: ((PaneContextAction) -> Void)?
    var projectProvider: (() -> [(String, Project)])?

    private let header = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let exitedTag = NSTextField(labelWithString: "")
    private var contextMenu: NSMenu!

    private let headerHeight: CGFloat = 22

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

        // Context menu (right-click the header to organize/move this pane).
        contextMenu = NSMenu()
        contextMenu.delegate = self
        header.menu = contextMenu
        titleLabel.menu = contextMenu
        closeButton.menu = contextMenu
    }

    // MARK: NSMenuDelegate — build the organizable pane menu on demand.

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let left = NSMenuItem(title: "Move Left", action: #selector(paneMoveLeft(_:)), keyEquivalent: "")
        left.target = self
        menu.addItem(left)
        let right = NSMenuItem(title: "Move Right", action: #selector(paneMoveRight(_:)), keyEquivalent: "")
        right.target = self
        menu.addItem(right)

        if let projects = projectProvider?(), !projects.isEmpty {
            menu.addItem(.separator())
            let moveTo = NSMenuItem(title: "Move to Project", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for (name, project) in projects {
                let item = NSMenuItem(title: name, action: #selector(moveToProject(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = project
                sub.addItem(item)
            }
            moveTo.submenu = sub
            menu.addItem(moveTo)
        }
    }

    @objc private func paneMoveLeft(_ sender: Any?) { onContextAction?(.moveLeft) }
    @objc private func paneMoveRight(_ sender: Any?) { onContextAction?(.moveRight) }
    @objc private func moveToProject(_ sender: NSMenuItem) {
        if let project = sender.representedObject as? Project {
            onContextAction?(.moveToProject(project))
        }
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
    private let resizeOverlay = ResizeOverlay()

    private var columnWeights: [CGFloat] = []
    private var rowWeights: [CGFloat] = []
    private var lastRows = 0
    private var lastCols = 0
    private var colX: [CGFloat] = []
    private var colW: [CGFloat] = []
    private var rowTopY: [CGFloat] = []
    private var rowH: [CGFloat] = []

    let spacing: CGFloat = 4

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

        resizeOverlay.container = self
        resizeOverlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(resizeOverlay)   // topmost; passes through except near dividers
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

        emptyLabel.stringValue = emptyMessage
        emptyLabel.isHidden = !panes.isEmpty

        // Keep the resize overlay on top of the just-added panes.
        addSubview(resizeOverlay)

        needsLayout = true
    }

    func focusFirstTerminal() {
        guard let first = panes.first else { return }
        window?.makeFirstResponder(first.terminal)
    }

    // MARK: Layout (weighted)

    override func layout() {
        super.layout()
        resizeOverlay.frame = bounds
        guard !panes.isEmpty else { return }

        let n = panes.count
        let (rows, cols) = gridDimensions(n)
        if columnWeights.count != cols { columnWeights = Array(repeating: 1, count: cols) }
        if rowWeights.count != rows { rowWeights = Array(repeating: 1, count: rows) }
        lastRows = rows
        lastCols = cols

        let gap = spacing
        let availW = bounds.width - gap * CGFloat(cols - 1)
        let availH = bounds.height - gap * CGFloat(rows - 1)
        let totalCW = columnWeights.reduce(0, +)
        let totalRW = rowWeights.reduce(0, +)

        colX = []; colW = []
        var x: CGFloat = 0
        for c in 0..<cols {
            let w = availW * columnWeights[c] / max(totalCW, 1)
            colX.append(x); colW.append(w)
            x += w + gap
        }

        rowTopY = []; rowH = []
        var yTop = bounds.maxY
        for r in 0..<rows {
            let h = availH * rowWeights[r] / max(totalRW, 1)
            rowTopY.append(yTop); rowH.append(h)
            yTop -= h + gap
        }

        for (i, pane) in panes.enumerated() {
            let row = i / cols
            let col = i % cols
            pane.frame = NSRect(x: colX[col],
                                y: rowTopY[row] - rowH[row],
                                width: colW[col],
                                height: rowH[row])
            pane.needsLayout = true
        }
    }

    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        needsLayout = true
    }

    // MARK: Resize support (called by ResizeOverlay)

    func dividerAxisAndIndex(at p: NSPoint, threshold: CGFloat) -> (axis: DividerAxis, index: Int)? {
        guard lastRows > 0, lastCols > 0 else { return nil }
        for c in 0..<(lastCols - 1) {
            let xdiv = colX[c] + colW[c] + spacing / 2
            if abs(p.x - xdiv) <= threshold, p.y >= 0, p.y <= bounds.height {
                return (.vertical, c)
            }
        }
        for r in 0..<(lastRows - 1) {
            let ydiv = rowTopY[r] - rowH[r] - spacing / 2
            if abs(p.y - ydiv) <= threshold, p.x >= 0, p.x <= bounds.width {
                return (.horizontal, r)
            }
        }
        return nil
    }

    func beginResize(axis: DividerAxis, index: Int, at p: NSPoint) {
        activeAxis = axis
        activeIndex = index
        dragStart = p
        dragStartWeights = axis == .vertical ? columnWeights : rowWeights
    }

    func updateResize(to p: NSPoint) {
        guard let axis = activeAxis else { return }
        let i0 = activeIndex, i1 = activeIndex + 1
        let delta = axis == .vertical ? (p.x - dragStart.x) : (dragStart.y - p.y)
        let weights = dragStartWeights
        let pairSum = weights[i0] + weights[i1]
        let extent = axis == .vertical
            ? (bounds.width - spacing * CGFloat(lastCols - 1))
            : (bounds.height - spacing * CGFloat(lastRows - 1))
        let frac = delta / max(extent, 1)
        let wDelta = frac * pairSum
        let minW = pairSum * 0.2
        let maxW = pairSum * 0.8
        var w0 = min(max(weights[i0] + wDelta, minW), maxW)
        w0 = min(w0, pairSum - minW)
        var w1 = pairSum - w0
        w1 = min(max(w1, minW), pairSum - minW)
        w0 = pairSum - w1
        if axis == .vertical {
            columnWeights[i0] = w0; columnWeights[i1] = w1
        } else {
            rowWeights[i0] = w0; rowWeights[i1] = w1
        }
        needsLayout = true
    }

    func endResize() {
        activeAxis = nil
        dragStartWeights = []
    }

    private var activeAxis: DividerAxis?
    private var activeIndex = 0
    private var dragStart: NSPoint = .zero
    private var dragStartWeights: [CGFloat] = []
}

enum DividerAxis {
    case vertical
    case horizontal
}

// MARK: - ResizeOverlay

/// Transparent overlay on top of the grid. It only captures input when the pointer is
/// near a pane divider (so it can resize); everywhere else it passes events through,
/// letting the terminals beneath receive clicks/typing normally.
final class ResizeOverlay: NSView {

    weak var container: TerminalGridContainer?

    private var trackingArea: NSTrackingArea?
    private var dragging = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        if let t = trackingArea { removeTrackingArea(t) }
        trackingArea = NSTrackingArea(rect: bounds,
                                      options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                      owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
        super.updateTrackingAreas()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let c = container, c.dividerAxisAndIndex(at: point, threshold: 6) != nil else { return nil }
        return self
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(event)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let c = container, let div = c.dividerAxisAndIndex(at: p, threshold: 6) else { return }
        c.beginResize(axis: div.axis, index: div.index, at: p)
        dragging = true
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        let p = convert(event.locationInWindow, from: nil)
        container?.updateResize(to: p)
    }

    override func mouseUp(with event: NSEvent) {
        if dragging {
            container?.endResize()
            dragging = false
        }
        updateCursor(event)
    }

    private func updateCursor(_ event: NSEvent) {
        if dragging { return }
        let p = convert(event.locationInWindow, from: nil)
        if let div = container?.dividerAxisAndIndex(at: p, threshold: 4) {
            switch div.axis {
            case .vertical: NSCursor.resizeLeftRight.set()
            case .horizontal: NSCursor.resizeUpDown.set()
            }
        }
        // Not near a divider: leave the cursor to the view below (e.g. the terminal's i-beam).
    }
}
