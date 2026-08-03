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
        tv.font = Settings.shared.terminalFont

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

    /// Apply the current global font setting to this terminal (live font-size change).
    func applyFont() {
        terminal.font = Settings.shared.terminalFont
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
    func addTerminal(to project: Project? = nil, in directory: String? = nil) -> TerminalSession? {
        guard let target = project ?? selectedProject else { return nil }
        let dir = directory ?? target.workingDirectory
        let session = TerminalSession(initialDirectory: dir)
        session.registerCloseHandler { [weak self] s in self?.removeTerminal(s) }
        target.sessions.append(session)
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
            let count = max(1, entry["count"] as? Int ?? 1)
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
        for session in project.sessions {
            session.onStateChange = { [weak self] in self?.notify() }
        }
    }

    private func notify() { onChange?() }
}
