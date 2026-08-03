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

    /// Fired whenever title / cwd / alive-state changes, so the sidebar can refresh.
    var onStateChange: (() -> Void)?

    private var _closeHandler: ((TerminalSession) -> Void)?

    init(shell: String = Shell.preferred, initialDirectory: String?) {
        let tv = LocalProcessTerminalView(frame: .zero)
        tv.translatesAutoresizingMaskIntoConstraints = false

        // A clean, full environment so the child shell behaves like a normal terminal.
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["TERM_PROGRAM"] = "multiterminal"
        env["TERM_PROGRAM_VERSION"] = "1.0"
        env["COLORTERM"] = "truecolor"
        let envArray = env.map { "\($0.key)=\($0.value)" }

        tv.startProcess(executable: shell,
                        args: ["-l"],            // login shell so profiles are read
                        environment: envArray,
                        execName: nil,
                        currentDirectory: initialDirectory)

        let baseTitle = (initialDirectory as NSString?)?.lastPathComponent.nilIfEmpty ?? "Terminal"
        title = baseTitle
        terminal = tv
        pane = TerminalPaneView(terminal: tv, title: baseTitle)

        super.init()
        tv.processDelegate = self
        pane.onClose = { [weak self] in self?.requestClose() }
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
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        self.title = cleaned
        pane.setTitle(cleaned)
        onStateChange?()
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        workingDirectory = directory
        if let dir = directory, !dir.isEmpty {
            let derived = (dir as NSString).lastPathComponent.nilIfEmpty ?? "Terminal"
            if title.isEmpty || title == "Terminal" {
                title = derived
                pane.setTitle(derived)
                onStateChange?()
            }
        }
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        isAlive = false
        let deadTitle = (title.nilIfEmpty ?? "Terminal") + " — exited"
        title = deadTitle
        pane.setExited(suffix: exitCode.map { " (exit \($0))" } ?? " (terminated)")
        onStateChange?()
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
        if isAlive { terminal.terminate() }
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

    init() {
        // Seed with one project + one terminal so the app is immediately useful.
        let home = NSHomeDirectory()
        let first = Project(name: "Project 1", workingDirectory: home)
        first.sessions = [TerminalSession(initialDirectory: home)]
        projects = [first]
        wire(first)
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
        notify()
        addTerminal(to: project)        // start fresh so the new project isn't empty
        return project
    }

    func deleteProject(at index: Int) {
        guard projects.indices.contains(index), projects.count > 1 else { return }
        projects[index].sessions.forEach { $0.terminate() }
        projects.remove(at: index)
        if selectedIndex >= projects.count { selectedIndex = projects.count - 1 }
        if index <= selectedIndex && selectedIndex > 0 { selectedIndex -= 1 }
        notify()
    }

    func renameProject(at index: Int, to name: String) {
        guard projects.indices.contains(index) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        projects[index].name = trimmed
        notify()
    }

    func setWorkingDirectory(forProjectAt index: Int, to url: URL) {
        guard projects.indices.contains(index) else { return }
        projects[index].workingDirectory = url.path
        notify()
    }

    func selectProject(at index: Int) {
        guard projects.indices.contains(index), index != selectedIndex else { return }
        selectedIndex = index
        notify()
    }

    // MARK: Terminals

    @discardableResult
    func addTerminal(to project: Project? = nil, in directory: String? = nil) -> TerminalSession {
        let target = project ?? selectedProject ?? projects.first!
        let dir = directory ?? target.workingDirectory
        let session = TerminalSession(initialDirectory: dir)
        session.registerCloseHandler { [weak self] s in self?.removeTerminal(s) }
        target.sessions.append(session)
        notify()
        return session
    }

    func removeTerminal(_ session: TerminalSession) {
        for project in projects {
            if let i = project.sessions.firstIndex(where: { $0 === session }) {
                session.terminate()
                project.sessions.remove(at: i)
                notify()
                return
            }
        }
    }

    // MARK: Wiring

    /// Make sidebar badges refresh when a terminal's title/cwd/alive state changes.
    private func wire(_ project: Project) {
        for session in project.sessions {
            session.onStateChange = { [weak self] in self?.notify() }
        }
    }

    private func notify() { onChange?() }
}
