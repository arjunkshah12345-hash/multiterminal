import AppKit
import SwiftTerm

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
    var onRename: (() -> Void)?
    var projectProvider: (() -> [(String, Project)])?

    private let header = NSView()
    private let focusBar = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let exitedTag = NSTextField(labelWithString: "")
    private var contextMenu: NSMenu!

    private let headerHeight: CGFloat = 24

    private var isExited = false

    init(terminal: LocalProcessTerminalView, title: String) {
        self.terminal = terminal
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 0
        layer?.backgroundColor = Brand.ink.cgColor
        // Flush, edge-to-edge panes: no border — just a 1px hairline between panes.
        layer?.borderWidth = 0

        setupHeader(title: title)
        setupTerminal()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupHeader(title: String) {
        header.translatesAutoresizingMaskIntoConstraints = false
        header.wantsLayer = true
        header.layer?.backgroundColor = Brand.inkRaised.cgColor
        addSubview(header)

        // A 2px accent line along the very top of the focused pane — the only cue
        // showing which terminal is active in a flush, borderless grid.
        focusBar.translatesAutoresizingMaskIntoConstraints = false
        focusBar.wantsLayer = true
        focusBar.layer?.backgroundColor = Brand.accent.cgColor
        focusBar.isHidden = true
        addSubview(focusBar)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = Brand.terminalText
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.cell?.truncatesLastVisibleLine = true
        // Double-click the title to rename it.
        let renameGesture = NSClickGestureRecognizer(target: self, action: #selector(handleRename))
        renameGesture.numberOfClicksRequired = 2
        titleLabel.addGestureRecognizer(renameGesture)
        header.addSubview(titleLabel)

        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        pathLabel.textColor = Brand.accent.withAlphaComponent(0.72)
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.cell?.truncatesLastVisibleLine = true
        header.addSubview(pathLabel)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isBordered = false
        closeButton.isTransparent = false
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close pane")
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.contentTintColor = Brand.terminalText.withAlphaComponent(0.72)
        closeButton.toolTip = "Close pane"
        closeButton.target = self
        closeButton.action = #selector(handleClose)
        closeButton.bezelColor = .clear
        header.addSubview(closeButton)

        exitedTag.translatesAutoresizingMaskIntoConstraints = false
        exitedTag.isHidden = true
        exitedTag.font = .systemFont(ofSize: 10, weight: .medium)
        exitedTag.textColor = NSColor.systemOrange
        header.addSubview(exitedTag)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: headerHeight),

            focusBar.topAnchor.constraint(equalTo: topAnchor),
            focusBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            focusBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            focusBar.heightAnchor.constraint(equalToConstant: 2),

            titleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            exitedTag.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 5),
            exitedTag.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            closeButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -6),
            closeButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 16),

            pathLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            pathLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            pathLabel.leadingAnchor.constraint(greaterThanOrEqualTo: exitedTag.trailingAnchor, constant: 6),
            pathLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 240)
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
        let rename = NSMenuItem(title: "Rename…", action: #selector(handleRename), keyEquivalent: "")
        rename.target = self
        menu.addItem(rename)
        menu.addItem(.separator())
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
    @objc private func handleRename() { onRename?() }
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

        // Focus accent is driven by the window (see KeyWindow.makeFirstResponder),
        // which reliably fires for every first-responder change — clicks included.
    }

    /// Show the accent focus line when this pane's terminal is the key first responder.
    func setFocused(_ focused: Bool) {
        focusBar.isHidden = !focused
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

    func setWorkingDirectory(_ directory: String) {
        pathLabel.stringValue = directory
        pathLabel.toolTip = directory
    }

    func setExited(suffix: String) {
        isExited = true
        exitedTag.stringValue = "exited" + suffix
        exitedTag.isHidden = false
        layer?.backgroundColor = Brand.forest.cgColor
    }

    func applyThemeToChrome() {
        layer?.backgroundColor = isExited ? Brand.forest.cgColor : Brand.ink.cgColor
        header.layer?.backgroundColor = Brand.inkRaised.cgColor
        titleLabel.textColor = Brand.terminalText
        pathLabel.textColor = Brand.accent.withAlphaComponent(0.72)
        closeButton.contentTintColor = Brand.terminalText.withAlphaComponent(0.72)
        focusBar.layer?.backgroundColor = Brand.accent.cgColor
    }

    @objc private func handleClose() {
        onClose?()
    }
}

// MARK: - FileDropTerminalView

/// SwiftTerm owns the terminal's hit testing, so file drops need to be handled by
/// the terminal view itself rather than by the surrounding pane. Dropped files are
/// inserted as shell-escaped paths, matching Terminal.app without executing anything.
final class FileDropTerminalView: LocalProcessTerminalView {

    /// Called before SwiftTerm feeds a PTY chunk into the visible terminal. The app uses
    /// this to keep a bounded, readable transcript for local MCP clients.
    var onOutput: ((ArraySlice<UInt8>) -> Void)?

    private var isDropTarget = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureMouseSelectionPolicy()
        registerForDraggedTypes([.fileURL, .URL, .string])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureMouseSelectionPolicy()
        registerForDraggedTypes([.fileURL, .URL, .string])
    }

    private func configureMouseSelectionPolicy() {
        // Plain drags should behave like a normal terminal selection, even when a
        // full-screen program has enabled mouse reporting. Option-drag remains available
        // for programs such as tmux and vim that need the raw mouse event.
        allowMouseReporting = false
        toolTip = "Drag to select text · Option-drag for app mouse input"
    }

    override func mouseDown(with event: NSEvent) {
        allowMouseReporting = event.modifierFlags.contains(.option)
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        allowMouseReporting = false
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        onOutput?(slice)
        super.dataReceived(slice: slice)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasSupportedDrop(sender.draggingPasteboard) else { return [] }
        setDropTarget(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        hasSupportedDrop(sender.draggingPasteboard) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setDropTarget(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { setDropTarget(false) }

        let pasteboard = sender.draggingPasteboard
        let paths = (pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ?? []).compactMap { object -> String? in
            if let url = object as? URL { return url.path }
            if let url = object as? NSURL { return url.path }
            return nil
        }

        let insertedText: String
        if !paths.isEmpty {
            insertedText = paths.map(Self.shellQuote).joined(separator: " ")
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty {
            insertedText = text
        } else {
            return false
        }

        window?.makeFirstResponder(self)
        insertText(insertedText, replacementRange: NSRange(location: 0, length: 0))
        return true
    }

    private func hasSupportedDrop(_ pasteboard: NSPasteboard) -> Bool {
        if let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ), !objects.isEmpty {
            return true
        }
        return pasteboard.string(forType: .string)?.isEmpty == false
    }

    private func setDropTarget(_ active: Bool) {
        guard active != isDropTarget else { return }
        isDropTarget = active
        wantsLayer = true
        layer?.borderWidth = active ? 1 : 0
        layer?.borderColor = active ? Brand.accent.cgColor : nil
    }

    private static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
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

    /// Flush, edge-to-edge panes separated by a 1px hairline. Dividers stay draggable
    /// via the resize overlay (6px grab band around each hairline).
    let spacing: CGFloat = 1
    private let contentInset: CGFloat = 0
    private var layoutBounds = NSRect.zero

    /// How panes are arranged (see `Layout`). Defaults to `.auto`.
    var layoutMode: Layout = Settings.shared.layoutMode {
        didSet {
            columnWeights = []
            rowWeights = []
            needsLayout = true
            needsDisplay = true
        }
    }

    /// Merged-cell spans keyed by pane index, e.g. the bottom pane of "2 + 1".
    /// nil ⇒ regular grid (every pane fills exactly one cell).
    private var spans: [Int: (rowSpan: Int, colSpan: Int)]? = nil

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = Brand.forest.cgColor

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = .systemFont(ofSize: 14, weight: .regular)
        emptyLabel.textColor = Brand.terminalText.withAlphaComponent(0.62)
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

    func applyThemeToChrome() {
        layer?.backgroundColor = Brand.forest.cgColor
        for pane in panes {
            pane.applyThemeToChrome()
        }
        emptyLabel.textColor = Brand.terminalText.withAlphaComponent(0.62)
        needsDisplay = true
    }

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

    func focus(_ session: TerminalSession) {
        guard let pane = panes.first(where: { $0 === session.pane }) else { return }
        window?.makeFirstResponder(pane.terminal)
    }

    /// Move keyboard focus to the next visible pane (wraps), or the first pane if none
    /// is currently focused. Bound to ⌘] in the View menu.
    func focusNext() {
        guard !panes.isEmpty else { return }
        let index = focusedPaneIndex()
        let next = index.map { ($0 + 1) % panes.count } ?? 0
        window?.makeFirstResponder(panes[next].terminal)
    }

    /// Move keyboard focus to the previous visible pane (wraps), or the last pane if none
    /// is currently focused. Bound to ⌘[ in the View menu.
    func focusPrevious() {
        guard !panes.isEmpty else { return }
        let index = focusedPaneIndex()
        let prev = index.map { ($0 - 1 + panes.count) % panes.count } ?? panes.count - 1
        window?.makeFirstResponder(panes[prev].terminal)
    }

    /// The pane whose terminal currently has keyboard focus, if any.
    func focusedPane() -> TerminalPaneView? {
        guard let idx = focusedPaneIndex() else { return nil }
        return panes[idx]
    }

    /// Clear the focused terminal's screen (sends Ctrl-L, the classic clear/redraw).
    func clearFocusedScreen() {
        guard let idx = focusedPaneIndex() else { return }
        panes[idx].terminal.send([0x0c])
    }

    /// Index of the pane whose terminal (or a descendant) is the current first responder.
    private func focusedPaneIndex() -> Int? {
        guard let responder = window?.firstResponder as? NSView else { return nil }
        var current: NSView? = responder
        while let view = current {
            if let idx = panes.firstIndex(where: { $0 === view }) { return idx }
            current = view.superview
        }
        return nil
    }

    /// Recompute which pane is focused and toggle each pane's accent line.
    /// Called by the window whenever the first responder changes.
    func refreshFocus() {
        let idx = focusedPaneIndex()
        for (i, pane) in panes.enumerated() {
            pane.setFocused(i == idx)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        (window as? KeyWindow)?.onFirstResponderChange = { [weak self] in
            self?.refreshFocus()
        }
        refreshFocus()
    }

    /// Returns true when the current first responder is inside one of the visible
    /// terminal panes. Store updates happen for shell title/cwd changes too, so callers
    /// must not refocus the first pane just because the UI refreshed.
    func hasFocusedTerminal() -> Bool {
        guard let responder = window?.firstResponder as? NSView else { return false }
        var current: NSView? = responder
        while let view = current {
            if panes.contains(where: { $0 === view }) { return true }
            current = view.superview
        }
        return false
    }

    // MARK: Layout (weighted)

    override func layout() {
        super.layout()
        resizeOverlay.frame = bounds
        guard !panes.isEmpty else {
            lastRows = 0
            lastCols = 0
            needsDisplay = true
            return
        }

        let n = panes.count
        let arrangement = layoutMode.arrange(paneCount: n)
        let rows = arrangement.rows
        let cols = arrangement.cols
        spans = arrangement.spans
        if columnWeights.count != cols { columnWeights = Array(repeating: 1, count: cols) }
        if rowWeights.count != rows { rowWeights = Array(repeating: 1, count: rows) }
        lastRows = rows
        lastCols = cols

        let gap = spacing
        layoutBounds = bounds.insetBy(dx: contentInset, dy: contentInset)
        let availW = layoutBounds.width - gap * CGFloat(cols - 1)
        let availH = layoutBounds.height - gap * CGFloat(rows - 1)
        let totalCW = columnWeights.reduce(0, +)
        let totalRW = rowWeights.reduce(0, +)

        colX = []; colW = []
        var x = layoutBounds.minX
        for c in 0..<cols {
            let w = availW * columnWeights[c] / max(totalCW, 1)
            colX.append(x); colW.append(w)
            x += w + gap
        }

        rowTopY = []; rowH = []
        var yTop = layoutBounds.maxY
        for r in 0..<rows {
            let h = availH * rowWeights[r] / max(totalRW, 1)
            rowTopY.append(yTop); rowH.append(h)
            yTop -= h + gap
        }

        for (i, pane) in panes.enumerated() {
            let row = i / cols
            let col = i % cols
            let span = spans?[i] ?? (rowSpan: 1, colSpan: 1)
            let width = (0..<span.colSpan).reduce(CGFloat.zero) { $0 + colW[col + $1] }
                + gap * CGFloat(max(span.colSpan - 1, 0))
            let height = (0..<span.rowSpan).reduce(CGFloat.zero) { $0 + rowH[row + $1] }
                + gap * CGFloat(max(span.rowSpan - 1, 0))
            pane.frame = NSRect(x: colX[col],
                                y: rowTopY[row] - height,
                                width: width,
                                height: height)
            pane.needsLayout = true
        }
        needsDisplay = true
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
            if abs(p.x - xdiv) <= threshold,
               dividerVisible(.vertical, index: c, at: p) {
                return (.vertical, c)
            }
        }
        for r in 0..<(lastRows - 1) {
            let ydiv = rowTopY[r] - rowH[r] - spacing / 2
            if abs(p.y - ydiv) <= threshold,
               dividerVisible(.horizontal, index: r, at: p) {
                return (.horizontal, r)
            }
        }
        return nil
    }

    private func dividerVisible(_ axis: DividerAxis, index: Int, at point: NSPoint) -> Bool {
        guard point.x >= layoutBounds.minX, point.x <= layoutBounds.maxX,
              point.y >= layoutBounds.minY, point.y <= layoutBounds.maxY else { return false }
        // In the signature 2 + 1 composition, the vertical divider belongs only to the
        // top pair. Keeping it out of the full-width lower pane removes the awkward
        // floating line that made the old middle feel accidental.
        if layoutMode == .twoTopOneBottom, panes.count == 3, axis == .vertical, index == 0 {
            return point.y >= rowTopY[0] - rowH[0] && point.y <= rowTopY[0]
        }
        return true
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
            ? (layoutBounds.width - spacing * CGFloat(lastCols - 1))
            : (layoutBounds.height - spacing * CGFloat(lastRows - 1))
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

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !panes.isEmpty, lastRows > 0, lastCols > 0 else { return }

        // Minimalist: a single 1px hairline marks each divider — no gutter, no handle.
        let hairline = Brand.forestRaised.withAlphaComponent(0.55)
        hairline.setFill()

        if lastCols > 1 {
            for c in 0..<(lastCols - 1) {
                let x = colX[c] + colW[c]
                let y = (layoutMode == .twoTopOneBottom && panes.count == 3 && c == 0)
                    ? rowTopY[0] - rowH[0] : layoutBounds.minY
                let height = (layoutMode == .twoTopOneBottom && panes.count == 3 && c == 0)
                    ? rowH[0] : layoutBounds.height
                NSBezierPath(rect: NSRect(x: x, y: y, width: 1, height: height)).fill()
            }
        }
        if lastRows > 1 {
            for r in 0..<(lastRows - 1) {
                let y = rowTopY[r] - rowH[r]
                NSBezierPath(rect: NSRect(x: layoutBounds.minX, y: y,
                                          width: layoutBounds.width, height: 1)).fill()
            }
        }
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
        } else {
            // Clear the manually-set resize cursor when the pointer leaves a divider.
            NSCursor.arrow.set()
        }
    }
}
