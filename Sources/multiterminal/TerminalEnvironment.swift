import Foundation

/// Environment boundary for a new Multiterminal PTY.
///
/// A GUI terminal launched from inside tmux must not accidentally inherit the
/// launcher's client variables. Otherwise a new `tmux` command can attach or nest
/// against the wrong session. The user can still explicitly run `tmux attach`.
enum TerminalEnvironment {
    static func configured(from base: [String: String]) -> [String: String] {
        var environment = base
        environment["TERM"] = "xterm-256color"
        environment["TERM_PROGRAM"] = "multiterminal"
        environment["TERM_PROGRAM_VERSION"] = "1.0"
        environment["COLORTERM"] = "truecolor"

        // Multiterminal is a new terminal boundary, even when it was launched
        // from a tmux pane. Do not make every child shell an accidental nested client.
        environment.removeValue(forKey: "TMUX")
        environment.removeValue(forKey: "TMUX_PANE")
        return environment
    }
}
