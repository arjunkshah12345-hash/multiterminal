import AppKit
import Foundation
import UserNotifications

// MARK: - Native command notifications

/// Owns the app-level notification permission and delivery. Shell hooks send OSC 777
/// through SwiftTerm, which keeps command completion inside the existing PTY path.
final class CommandNotificationCenter: NSObject, UNUserNotificationCenterDelegate {

    static let shared = CommandNotificationCenter()

    // `swift run` has a bundle-shaped URL but no application bundle proxy, so asking
    // UserNotifications for its singleton there raises an AppKit exception. Notifications
    // are a convenience; keep source-mode development usable and enable them in the real
    // .app bundle produced by tools/build_app.sh.
    private lazy var center: UNUserNotificationCenter? = {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        return UNUserNotificationCenter.current()
    }()

    private override init() {
        super.init()
        center?.delegate = self
    }

    func requestAuthorization() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func deliver(title: String, body: String, suppressIfActive: Bool = true) {
        // Match Terminal's useful behavior: don't interrupt someone who is already
        // looking at the terminal, but do surface work that finished in the background.
        guard !suppressIfActive || !NSApp.isActive else { return }
        guard let center else { return }

        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? "Multiterminal" : title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "multiterminal.command.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - Shell integration

/// Installs per-session prompt hooks without modifying the user's dotfiles. Zsh gets a
/// temporary ZDOTDIR wrapper so the hook runs after the user's .zshrc; Bash uses its
/// standard PROMPT_COMMAND environment hook.
enum ShellIntegration {

    static func configure(shell: String, environment: inout [String: String]) -> URL? {
        switch (shell as NSString).lastPathComponent {
        case "zsh":
            return configureZsh(environment: &environment)
        case "bash":
            configureBash(environment: &environment)
            return nil
        default:
            return nil
        }
    }

    private static func configureZsh(environment: inout [String: String]) -> URL? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("multiterminal-zsh-" + UUID().uuidString, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let originalZDotDir = environment["ZDOTDIR"] ?? NSHomeDirectory()
            environment["MULTITERMINAL_ORIGINAL_ZDOTDIR"] = originalZDotDir
            environment["ZDOTDIR"] = directory.path

            try zshenv.write(to: directory.appendingPathComponent(".zshenv"), atomically: true, encoding: .utf8)
            try zprofile.write(to: directory.appendingPathComponent(".zprofile"), atomically: true, encoding: .utf8)
            try zshrc.write(to: directory.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
            try zlogin.write(to: directory.appendingPathComponent(".zlogin"), atomically: true, encoding: .utf8)
            return directory
        } catch {
            try? FileManager.default.removeItem(at: directory)
            return nil
        }
    }

    private static func configureBash(environment: inout [String: String]) {
        let hook = #"__multiterminal_status=$?; if [[ -n "${MULTITERMINAL_COMMAND_ACTIVE:-}" ]]; then printf '\e]777;notify;Multiterminal;Command finished (exit %s)\a' "$__multiterminal_status"; fi; MULTITERMINAL_COMMAND_ACTIVE=1"#
        if let existing = environment["PROMPT_COMMAND"], !existing.isEmpty {
            environment["PROMPT_COMMAND"] = "\(hook); \(existing)"
        } else {
            environment["PROMPT_COMMAND"] = hook
        }
    }

    private static let zshenv = #"""
    if [[ -f "${MULTITERMINAL_ORIGINAL_ZDOTDIR}/.zshenv" && "${MULTITERMINAL_ORIGINAL_ZDOTDIR}/.zshenv" != "$ZDOTDIR/.zshenv" ]]; then
      source "${MULTITERMINAL_ORIGINAL_ZDOTDIR}/.zshenv"
    fi
    """#

    private static let zprofile = #"""
    if [[ -f "${MULTITERMINAL_ORIGINAL_ZDOTDIR}/.zprofile" ]]; then
      source "${MULTITERMINAL_ORIGINAL_ZDOTDIR}/.zprofile"
    fi
    """#

    private static let zshrc = #"""
    if [[ -f "${MULTITERMINAL_ORIGINAL_ZDOTDIR}/.zshrc" ]]; then
      source "${MULTITERMINAL_ORIGINAL_ZDOTDIR}/.zshrc"
    fi

    autoload -Uz add-zsh-hook
    _multiterminal_preexec() {
      MULTITERMINAL_COMMAND_ACTIVE=1
    }
    _multiterminal_precmd() {
      local status=$?
      if [[ -n "${MULTITERMINAL_COMMAND_ACTIVE:-}" ]]; then
        printf '\e]777;notify;Multiterminal;Command finished (exit %s)\a' "$status"
      fi
      MULTITERMINAL_COMMAND_ACTIVE=1
    }
    add-zsh-hook preexec _multiterminal_preexec
    add-zsh-hook precmd _multiterminal_precmd
    """#

    private static let zlogin = #"""
    if [[ -f "${MULTITERMINAL_ORIGINAL_ZDOTDIR}/.zlogin" ]]; then
      source "${MULTITERMINAL_ORIGINAL_ZDOTDIR}/.zlogin"
    fi

    # Do not leak the temporary wrapper directory into child processes such as tmux.
    # The current shell has already loaded the integration hooks above; descendants
    # should use the user's real startup directory and remain valid after this pane exits.
    export ZDOTDIR="${MULTITERMINAL_ORIGINAL_ZDOTDIR:-$HOME}"
    """#
}
