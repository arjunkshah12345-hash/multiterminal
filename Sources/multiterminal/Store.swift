import AppKit
import SwiftTerm

// MARK: - Shell detection

enum Shell {
    /// The user's preferred shell, falling back to zsh, then bash.
    static var preferred: String {
        if let s = ProcessInfo.processInfo.environment["SHELL"],
           FileManager.default.isExecutableFile(atPath: s) {
            return s
        }
        if FileManager.default.isExecutableFile(atPath: "/bin/zsh") { return "/bin/zsh" }
        return "/bin/bash"
    }
}

// MARK: - TerminalSession

/// One live terminal: a `LocalProcessTerminalView` (real PTY/shell) plus its pane chrome
/// (title bar + close button) and lifecycle state. The view and shell keep running while
/// the session lives, even when its project is not currently visible.
final class TerminalSession: NSObject, LocalProcessTerminalViewDelegate {

    let id = UUID()
    let terminal: LocalProcessTerminalView
    let pane: TerminalPaneView

    private(set) var title: String
    private(set) var workingDirectory: String?
    private(set) var isAlive: Bool = true

    /// A user-set title that takes precedence over the shell's reported title, so a
    /// rename sticks even when the running program changes its window title.
    private var customTitle: String?

    /// Fired whenever title / cwd / alive-state changes, so the sidebar can refresh.
    var onStateChange: (() -> Void)?

    private var _closeHandler: ((TerminalSession) -> Void)?
    private var shellIntegrationDirectory: URL?
    private var isClosing = false
    private var outputBuffer = ""
    private let outputBufferLimit = 64 * 1024

    init(shell: String = Shell.preferred, initialDirectory: String?) {
        let tv = FileDropTerminalView(frame: .zero)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.font = Settings.shared.terminalFont
        tv.nativeBackgroundColor = Brand.ink
        tv.nativeForegroundColor = Brand.terminalText
        tv.caretColor = Brand.accent
        tv.caretTextColor = Brand.ink
        tv.selectedTextBackgroundColor = Brand.accent.withAlphaComponent(0.82)
        tv.selectedTextForegroundColor = Brand.ink
        // A real terminal needs generous history; SwiftTerm defaults to only 500 lines.
        tv.changeScrollback(10_000)

        // A clean terminal boundary so shells and tmux behave like they do in a
        // standalone terminal, even when the app itself was launched from tmux.
        var env = TerminalEnvironment.configured(from: ProcessInfo.processInfo.environment)
        shellIntegrationDirectory = ShellIntegration.configure(shell: shell, environment: &env)
        let envArray = env.map { "\($0.key)=\($0.value)" }

        let baseTitle = (initialDirectory as NSString?)?.lastPathComponent.nilIfEmpty ?? "Terminal"
        title = baseTitle
        terminal = tv
        pane = TerminalPaneView(terminal: tv, title: baseTitle)

        super.init()
        tv.onOutput = { [weak self] slice in
            self?.appendOutput(slice)
        }
        tv.terminal.registerOscHandler(code: 777) { [weak self] data in
            self?.handleTerminalNotification(data)
        }
        tv.processDelegate = self
        pane.onClose = { [weak self] in self?.requestClose() }

        tv.startProcess(executable: shell,
                        args: ["-l"],            // login shell so profiles are read
                        environment: envArray,
                        execName: nil,
                        currentDirectory: initialDirectory)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: LocalProcessTerminalViewDelegate

extension TerminalSession {
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // Nothing to do: the terminal resizes itself and informs the PTY.
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        // Don't clobber a user rename.
        guard customTitle == nil else { return }
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        self.title = cleaned
        pane.setTitle(cleaned)
        onStateChange?()
    }

    /// Set a name that overrides the shell's title. Pass empty to revert to automatic.
    func rename(to name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        customTitle = cleaned.isEmpty ? nil : cleaned
        let display = customTitle ?? (title.nilIfEmpty ?? "Terminal")
        title = display
        pane.setTitle(display)
        onStateChange?()
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        workingDirectory = directory
        if let dir = directory, !dir.isEmpty {
            let derived = (dir as NSString).lastPathComponent.nilIfEmpty ?? "Terminal"
            pane.setWorkingDirectory(derived)
            if customTitle == nil && (title.isEmpty || title == "Terminal") {
                title = derived
                pane.setTitle(derived)
                onStateChange?()
            }
        }
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        isAlive = false
        cleanupShellIntegration()
        let deadTitle = (title.nilIfEmpty ?? "Terminal") + " - exited"
        title = deadTitle
        pane.setExited(suffix: exitCode.map { " (exit \($0))" } ?? " (terminated)")
        onStateChange?()
        if !isClosing {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                CommandNotificationCenter.shared.deliver(
                    title: "Terminal exited",
                    body: self.title,
                    suppressIfActive: self.isTerminalFocused
                )
            }
        }
    }
}

// MARK: TerminalSession lifecycle

extension TerminalSession {
    func registerCloseHandler(_ handler: @escaping (TerminalSession) -> Void) {
        _closeHandler = handler
    }

    private func requestClose() { _closeHandler?(self) }

    /// Kill the underlying shell (used when closing the pane).
    func terminate() {
        isClosing = true
        cleanupShellIntegration()
        if isAlive { terminal.terminate() }
    }

    /// Send raw keyboard input to the live PTY. This intentionally accepts control
    /// characters because MCP clients need to be able to drive interactive commands.
    func writeInput(_ text: String) {
        guard isAlive, !text.isEmpty else { return }
        terminal.send(txt: text)
    }

    /// Return the most recent human-readable PTY output, capped so a noisy process cannot
    /// make an MCP response unbounded.
    func recentOutput(limit: Int = 16 * 1024) -> String {
        let boundedLimit = min(max(limit, 1), outputBufferLimit)
        return String(outputBuffer.suffix(boundedLimit))
    }

    /// Apply the current global font setting to this terminal (live font-size change).
    func applyFont() {
        terminal.font = Settings.shared.terminalFont
    }

    /// Apply the focused black/forest terminal palette without restarting the shell.
    func applyTheme() {
        terminal.nativeBackgroundColor = Brand.ink
        terminal.nativeForegroundColor = Brand.terminalText
        terminal.caretColor = Brand.accent
        terminal.caretTextColor = Brand.ink
        terminal.selectedTextBackgroundColor = Brand.accent.withAlphaComponent(0.82)
        terminal.selectedTextForegroundColor = Brand.ink
    }

    private func handleTerminalNotification(_ data: ArraySlice<UInt8>) {
        guard let text = String(bytes: data, encoding: .utf8) else { return }
        let parts = text.components(separatedBy: ";")
        guard parts.count >= 3, parts[0] == "notify" else { return }
        let title = parts[1].isEmpty ? "Multiterminal" : parts[1]
        let body = parts.dropFirst(2).joined(separator: ";")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            CommandNotificationCenter.shared.deliver(
                title: title,
                body: body,
                suppressIfActive: self.isTerminalFocused
            )
        }
    }

    private func appendOutput(_ data: ArraySlice<UInt8>) {
        let text = String(decoding: data, as: UTF8.self)
        guard !text.isEmpty else { return }
        outputBuffer.append(Self.stripTerminalControlSequences(text))
        if outputBuffer.count > outputBufferLimit {
            outputBuffer = String(outputBuffer.suffix(outputBufferLimit))
        }
    }

    private static func stripTerminalControlSequences(_ text: String) -> String {
        // Keep output useful to API clients without exposing ANSI cursor movement, color,
        // OSC metadata, or other terminal-emulator control bytes.
        var result: [UInt8] = []
        result.reserveCapacity(text.utf8.count)
        var iterator = text.utf8.makeIterator()
        while let byte = iterator.next() {
            guard byte == 0x1B else {
                if byte == 0x08 {
                    // Remove the previous complete UTF-8 scalar, not only its final byte.
                    while let last = result.last, (last & 0xC0) == 0x80 { result.removeLast() }
                    if !result.isEmpty { result.removeLast() }
                } else if byte >= 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
                    result.append(byte)
                }
                continue
            }

            guard let next = iterator.next() else { break }
            switch next {
            case 0x5B: // CSI: consume through the final byte.
                while let value = iterator.next() {
                    if value >= 0x40 && value <= 0x7E { break }
                }
            case 0x5D: // OSC: consume through BEL or ST.
                var previousWasEscape = false
                while let value = iterator.next() {
                    if value == 0x07 || (previousWasEscape && value == 0x5C) { break }
                    previousWasEscape = value == 0x1B
                }
            default:
                break
            }
        }
        return String(decoding: result, as: UTF8.self)
    }

    private var isTerminalFocused: Bool {
        guard NSApp.isActive, let responder = NSApp.keyWindow?.firstResponder as? NSView else {
            return false
        }
        var current: NSView? = responder
        while let view = current {
            if view === pane || view === terminal { return true }
            current = view.superview
        }
        return false
    }

    private func cleanupShellIntegration() {
        guard let directory = shellIntegrationDirectory else { return }
        shellIntegrationDirectory = nil
        try? FileManager.default.removeItem(at: directory)
    }
}

// MARK: - Project

/// A named collection of terminals rooted at a working directory. Switching projects
/// swaps the visible grid while every shell keeps running in the background.
final class Project {
    let id = UUID()
    var name: String
    var workingDirectory: String
    var sessions: [TerminalSession] = []

    init(name: String, workingDirectory: String) {
        self.name = name
        self.workingDirectory = workingDirectory
    }
}

// MARK: - Store

/// Single source of truth for projects + selection. Pure data + mutations; the UI
/// rebuilds itself in response to `onChange`.
final class Store {
    private(set) var projects: [Project] = []
    private(set) var selectedIndex: Int = 0

    var onChange: (() -> Void)?

    private let defaults = UserDefaults.standard
    private let projectsKey = "multiterminal.projects"

    init() {
        // Restore the user's projects from the last session (name, folder, pane count).
        if restoreFromDefaults() { return }
        // First run: seed with one project + one terminal.
        let home = NSHomeDirectory()
        let first = Project(name: "Project 1", workingDirectory: home)
        first.sessions = [TerminalSession(initialDirectory: home)]
        projects = [first]
        wire(first)
        save()
    }

    var selectedProject: Project? {
        guard projects.indices.contains(selectedIndex) else { return nil }
        return projects[selectedIndex]
    }

    // MARK: Projects

    @discardableResult
    func addProject(name: String? = nil, workingDirectory: String? = nil) -> Project {
        let dir = workingDirectory ?? NSHomeDirectory()
        let project = Project(name: name ?? "Project \(projects.count + 1)", workingDirectory: dir)
        projects.append(project)
        selectedIndex = projects.count - 1
        wire(project)
        addTerminal(to: project)        // start fresh so the new project isn't empty
        return project
    }

    /// Create a project from a chosen folder: named after the folder, rooted at it,
    /// with one terminal already running there.
    @discardableResult
    func addProject(fromFolder url: URL, name: String? = nil) -> Project {
        addProject(name: name ?? url.lastPathComponent, workingDirectory: url.path)
    }

    /// Apply the current terminal font setting to every running terminal (live update).
    func applyFontToAll() {
        for project in projects {
            for session in project.sessions { session.applyFont() }
        }
    }

    func applyThemeToAll() {
        for project in projects {
            for session in project.sessions { session.applyTheme() }
        }
    }

    func deleteProject(at index: Int) {
        guard projects.indices.contains(index) else { return }
        projects[index].sessions.forEach { $0.terminate() }
        projects.remove(at: index)
        if projects.isEmpty {
            selectedIndex = 0
        } else if selectedIndex >= projects.count {
            selectedIndex = projects.count - 1
        } else if index <= selectedIndex && selectedIndex > 0 {
            selectedIndex -= 1
        }
        notify()
        save()
    }

    func renameProject(at index: Int, to name: String) {
        guard projects.indices.contains(index) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        projects[index].name = trimmed
        notify()
        save()
    }

    /// Change a project's folder. If the name still matches the previous folder's name
    /// (i.e. it hasn't been manually renamed), adopt the new folder's name automatically.
    func setWorkingDirectory(forProjectAt index: Int, to url: URL) {
        guard projects.indices.contains(index) else { return }
        let project = projects[index]
        let oldFolderName = (project.workingDirectory as NSString).lastPathComponent
        let isUntouchedDefault = (project.name == oldFolderName) || project.name.hasPrefix("Project ")
        project.workingDirectory = url.path
        if isUntouchedDefault {
            project.name = url.lastPathComponent
        }
        notify()
        save()
    }

    func selectProject(at index: Int) {
        guard projects.indices.contains(index), index != selectedIndex else { return }
        selectedIndex = index
        notify()
    }

    // MARK: Terminals

    @discardableResult
    func addTerminal(to project: Project? = nil, in directory: String? = nil, shell: String? = nil) -> TerminalSession? {
        guard let target = project ?? selectedProject else { return nil }
        let dir = directory ?? target.workingDirectory
        let session = TerminalSession(shell: shell ?? Shell.preferred, initialDirectory: dir)
        target.sessions.append(session)
        wire(session)
        notify()
        save()
        return session
    }

    func removeTerminal(_ session: TerminalSession) {
        for project in projects {
            if let i = project.sessions.firstIndex(where: { $0 === session }) {
                session.terminate()
                project.sessions.remove(at: i)
                notify()
                save()
                return
            }
        }
    }

    /// Reorder a terminal within its project by a signed offset (-1 left / +1 right).
    func moveTerminal(_ session: TerminalSession, by offset: Int) {
        for project in projects {
            guard let oldIndex = project.sessions.firstIndex(where: { $0 === session }) else { continue }
            let newIndex = min(max(oldIndex + offset, 0), project.sessions.count - 1)
            guard newIndex != oldIndex else { return }
            project.sessions.swapAt(oldIndex, newIndex)
            notify()
            save()
            return
        }
    }

    /// Reorder a terminal within its project (pane "organizing").
    func moveTerminal(_ session: TerminalSession, toIndex newIndex: Int) {
        for project in projects {
            guard let oldIndex = project.sessions.firstIndex(where: { $0 === session }) else { continue }
            project.sessions.remove(at: oldIndex)
            let clamped = min(max(newIndex, 0), project.sessions.count)
            project.sessions.insert(session, at: clamped)
            notify()
            save()
            return
        }
    }

    /// Move a terminal into a different project.
    func moveTerminal(_ session: TerminalSession, to target: Project) {
        guard let source = projects.first(where: { $0.sessions.contains(where: { $0 === session }) }),
              source !== target else { return }

        for project in projects {
            if let i = project.sessions.firstIndex(where: { $0 === session }) {
                project.sessions.remove(at: i)
                break
            }
        }
        target.sessions.append(session)
        notify()
        save()
    }

    // MARK: Persistence

    @discardableResult
    private func restoreFromDefaults() -> Bool {
        guard let saved = defaults.array(forKey: projectsKey) as? [[String: Any]],
              !saved.isEmpty else { return false }
        for entry in saved {
            let name = entry["name"] as? String ?? "Project"
            let dir = entry["dir"] as? String ?? NSHomeDirectory()
            // Zero is a valid persisted state: a user can intentionally close every pane
            // in a project and recreate one later with ⌘T.
            let count = max(0, entry["count"] as? Int ?? 1)
            let project = Project(name: name, workingDirectory: dir)
            for _ in 0..<count {
                project.sessions.append(TerminalSession(initialDirectory: dir))
            }
            projects.append(project)
            wire(project)
        }
        return true
    }

    private func save() {
        let data = projects.map { p -> [String: Any] in
            ["name": p.name, "dir": p.workingDirectory, "count": p.sessions.count]
        }
        defaults.set(data, forKey: projectsKey)
    }

    // MARK: Wiring

    /// Make sidebar badges refresh when a terminal's title/cwd/alive state changes.
    private func wire(_ project: Project) {
        project.sessions.forEach { wire($0) }
    }

    private func wire(_ session: TerminalSession) {
        session.registerCloseHandler { [weak self] session in
            self?.removeTerminal(session)
        }
        session.onStateChange = { [weak self] in self?.notify() }
    }

    private func notify() { onChange?() }
}
