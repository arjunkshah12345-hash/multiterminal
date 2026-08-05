import AppKit

// MARK: - Appearance

enum Appearance: String, CaseIterable {
    case system, light, dark

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - Brand

// MARK: - Theme

enum Theme: String, CaseIterable, Codable {
    case forest, ink, slate, sand, light

    var label: String {
        switch self {
        case .forest: return "Forest"
        case .ink: return "Ink"
        case .slate: return "Slate"
        case .sand: return "Sand"
        case .light: return "Light"
        }
    }

    struct Palette {
        let background: NSColor
        let foreground: NSColor
        let caret: NSColor
        let caretText: NSColor
        let selectionBg: NSColor
        let selectionFg: NSColor
        let accent: NSColor
        let ink: NSColor
        let forest: NSColor
        let forestRaised: NSColor
        let inkRaised: NSColor
        let terminalText: NSColor
    }

    var palette: Palette {
        switch self {
        case .forest:
            return Palette(
                background: NSColor(srgbRed: 0.024, green: 0.039, blue: 0.031, alpha: 1),
                foreground: NSColor(srgbRed: 0.933, green: 0.957, blue: 0.894, alpha: 1),
                caret: NSColor(srgbRed: 0.471, green: 0.804, blue: 0.745, alpha: 1),
                caretText: NSColor(srgbRed: 0.024, green: 0.039, blue: 0.031, alpha: 1),
                selectionBg: NSColor(srgbRed: 0.471, green: 0.804, blue: 0.745, alpha: 0.82),
                selectionFg: NSColor(srgbRed: 0.024, green: 0.039, blue: 0.031, alpha: 1),
                accent: NSColor(srgbRed: 0.471, green: 0.804, blue: 0.745, alpha: 1),
                ink: NSColor(srgbRed: 0.024, green: 0.039, blue: 0.031, alpha: 1),
                forest: NSColor(srgbRed: 0.063, green: 0.102, blue: 0.086, alpha: 1),
                forestRaised: NSColor(srgbRed: 0.090, green: 0.145, blue: 0.122, alpha: 1),
                inkRaised: NSColor(srgbRed: 0.047, green: 0.071, blue: 0.059, alpha: 1),
                terminalText: NSColor(srgbRed: 0.933, green: 0.957, blue: 0.894, alpha: 1)
            )
        case .ink:
            return Palette(
                background: NSColor(white: 0.02, alpha: 1),
                foreground: NSColor(white: 0.88, alpha: 1),
                caret: NSColor(red: 0, green: 1, blue: 0.53, alpha: 1),
                caretText: NSColor(white: 0.02, alpha: 1),
                selectionBg: NSColor(red: 0, green: 1, blue: 0.53, alpha: 0.82),
                selectionFg: NSColor(white: 0.02, alpha: 1),
                accent: NSColor(red: 0, green: 1, blue: 0.53, alpha: 1),
                ink: NSColor(white: 0.02, alpha: 1),
                forest: NSColor(white: 0.06, alpha: 1),
                forestRaised: NSColor(white: 0.10, alpha: 1),
                inkRaised: NSColor(white: 0.13, alpha: 1),
                terminalText: NSColor(white: 0.88, alpha: 1)
            )
        case .slate:
            return Palette(
                background: NSColor(white: 0.05, alpha: 1),
                foreground: NSColor(white: 0.78, alpha: 1),
                caret: NSColor(red: 0.35, green: 0.65, blue: 1, alpha: 1),
                caretText: NSColor(white: 0.05, alpha: 1),
                selectionBg: NSColor(red: 0.35, green: 0.65, blue: 1, alpha: 0.82),
                selectionFg: NSColor(white: 0.05, alpha: 1),
                accent: NSColor(red: 0.35, green: 0.65, blue: 1, alpha: 1),
                ink: NSColor(white: 0.02, alpha: 1),
                forest: NSColor(white: 0.08, alpha: 1),
                forestRaised: NSColor(white: 0.12, alpha: 1),
                inkRaised: NSColor(white: 0.15, alpha: 1),
                terminalText: NSColor(white: 0.78, alpha: 1)
            )
        case .sand:
            return Palette(
                background: NSColor(srgbRed: 0.10, green: 0.08, blue: 0.06, alpha: 1),
                foreground: NSColor(srgbRed: 0.91, green: 0.86, blue: 0.78, alpha: 1),
                caret: NSColor(srgbRed: 0.83, green: 0.65, blue: 0.45, alpha: 1),
                caretText: NSColor(srgbRed: 0.10, green: 0.08, blue: 0.06, alpha: 1),
                selectionBg: NSColor(srgbRed: 0.83, green: 0.65, blue: 0.45, alpha: 0.82),
                selectionFg: NSColor(srgbRed: 0.10, green: 0.08, blue: 0.06, alpha: 1),
                accent: NSColor(srgbRed: 0.83, green: 0.65, blue: 0.45, alpha: 1),
                ink: NSColor(srgbRed: 0.06, green: 0.05, blue: 0.03, alpha: 1),
                forest: NSColor(srgbRed: 0.14, green: 0.11, blue: 0.08, alpha: 1),
                forestRaised: NSColor(srgbRed: 0.18, green: 0.14, blue: 0.10, alpha: 1),
                inkRaised: NSColor(srgbRed: 0.22, green: 0.17, blue: 0.12, alpha: 1),
                terminalText: NSColor(srgbRed: 0.91, green: 0.86, blue: 0.78, alpha: 1)
            )
        case .light:
            return Palette(
                background: NSColor(white: 0.96, alpha: 1),
                foreground: NSColor(white: 0.15, alpha: 1),
                caret: NSColor(srgbRed: 0.12, green: 0.55, blue: 0.40, alpha: 1),
                caretText: NSColor(white: 0.96, alpha: 1),
                selectionBg: NSColor(srgbRed: 0.12, green: 0.55, blue: 0.40, alpha: 0.82),
                selectionFg: NSColor(white: 0.96, alpha: 1),
                accent: NSColor(srgbRed: 0.12, green: 0.55, blue: 0.40, alpha: 1),
                ink: NSColor(white: 0.92, alpha: 1),
                forest: NSColor(white: 0.85, alpha: 1),
                forestRaised: NSColor(white: 0.80, alpha: 1),
                inkRaised: NSColor(white: 0.75, alpha: 1),
                terminalText: NSColor(white: 0.15, alpha: 1)
            )
        }
    }

    static var current: Self {
        get { Settings.shared.theme }
        set { Settings.shared.theme = newValue }
    }
}

enum Brand {
    /// Multiterminal's signal mint. Keep this as the only high-energy UI color.
    static var accent: NSColor { Theme.current.palette.accent }
    static var accentStrong: NSColor { Theme.current.palette.accent.withAlphaComponent(0.68) }
    static var ink: NSColor { Theme.current.palette.ink }
    static var forest: NSColor { Theme.current.palette.forest }
    static var forestRaised: NSColor { Theme.current.palette.forestRaised }
    /// A tone just above the terminal ink — used for slim, low-contrast pane headers.
    static var inkRaised: NSColor { Theme.current.palette.inkRaised }
    static var terminalText: NSColor { Theme.current.palette.terminalText }
}

// MARK: - Settings

/// Persisted user preferences (UserDefaults). `onChange` fires after any change so the
/// app can apply appearance / font updates live.
final class Settings {
    static let shared = Settings()

    var onChange: (() -> Void)?

    private let defaults = UserDefaults.standard
    private let appearanceKey = "multiterminal.appearance"
    private let fontSizeKey = "multiterminal.fontSize"
    private let layoutModeKey = "multiterminal.layoutMode"
    private let themeKey = "multiterminal.theme"

    private init() {}

    var appearance: Appearance {
        get {
            guard let raw = defaults.string(forKey: appearanceKey) else { return .dark }
            return Appearance(rawValue: raw) ?? .dark
        }
        set {
            defaults.set(newValue.rawValue, forKey: appearanceKey)
            onChange?()
        }
    }

    var fontSize: CGFloat {
        get {
            let stored = defaults.object(forKey: fontSizeKey) as? CGFloat ?? 13
            return min(24, max(9, stored))
        }
        set {
            defaults.set(min(24, max(9, newValue)), forKey: fontSizeKey)
            onChange?()
        }
    }

    /// The monospaced font used by every terminal pane.
    var terminalFont: NSFont {
        NSFont(name: "Menlo", size: fontSize)
            ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    var layoutMode: Layout {
        get {
            guard let raw = defaults.string(forKey: layoutModeKey),
                  let mode = Layout(rawValue: raw) else { return .auto }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: layoutModeKey)
            onChange?()
        }
    }

    var theme: Theme {
        get {
            guard let raw = defaults.string(forKey: themeKey), let theme = Theme(rawValue: raw) else { return .forest }
            return theme
        }
        set {
            defaults.set(newValue.rawValue, forKey: themeKey)
            onChange?()
        }
    }
}

// MARK: - SettingsViewController

/// A compact preferences sheet: Appearance (System/Light/Dark) + terminal font size.
final class SettingsViewController: NSViewController {

    private let appearanceControl = NSSegmentedControl()
    private let themeControl = NSPopUpButton()
    private let fontStepper = NSStepper()
    private let fontLabel = NSTextField(labelWithString: "")

    var onChange: (() -> Void)?

    init() { super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 200))
        view.translatesAutoresizingMaskIntoConstraints = false

        let appearanceLabel = sectionLabel("Appearance")
        appearanceControl.segmentCount = 3
        for (i, a) in Appearance.allCases.enumerated() {
            appearanceControl.setLabel(a.label, forSegment: i)
        }
        appearanceControl.target = self
        appearanceControl.action = #selector(appearanceChanged)
        appearanceControl.selectedSegment = Appearance.allCases.firstIndex(of: Settings.shared.appearance) ?? 0

        let themeSectionLabel = sectionLabel("Theme")
        themeControl.removeAllItems()
        for theme in Theme.allCases {
            themeControl.addItem(withTitle: theme.label)
        }
        themeControl.target = self
        themeControl.action = #selector(themeChanged)
        themeControl.selectItem(at: Theme.allCases.firstIndex(of: Settings.shared.theme) ?? 0)

        let fontSectionLabel = sectionLabel("Terminal font size")
        fontLabel.font = .systemFont(ofSize: 13, weight: .medium)
        fontLabel.alignment = .right
        fontStepper.minValue = 9
        fontStepper.maxValue = 24
        fontStepper.increment = 1
        fontStepper.valueWraps = false
        fontStepper.target = self
        fontStepper.action = #selector(fontChanged)
        fontStepper.integerValue = Int(Settings.shared.fontSize.rounded())

        let doneButton = NSButton(title: "Done", target: self, action: #selector(close))
        doneButton.keyEquivalent = "\r"
        doneButton.setAccessibilityLabel("Close settings")

        view.addSubview(appearanceLabel)
        view.addSubview(appearanceControl)
        view.addSubview(themeSectionLabel)
        view.addSubview(themeControl)
        view.addSubview(fontSectionLabel)
        view.addSubview(fontLabel)
        view.addSubview(fontStepper)
        view.addSubview(doneButton)

        NSLayoutConstraint.activate([
            appearanceLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            appearanceLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            appearanceControl.topAnchor.constraint(equalTo: appearanceLabel.bottomAnchor, constant: 6),
            appearanceControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            appearanceControl.widthAnchor.constraint(equalToConstant: 220),

            themeSectionLabel.topAnchor.constraint(equalTo: appearanceControl.bottomAnchor, constant: 18),
            themeSectionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            themeControl.topAnchor.constraint(equalTo: themeSectionLabel.bottomAnchor, constant: 6),
            themeControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            themeControl.widthAnchor.constraint(equalToConstant: 220),

            fontSectionLabel.topAnchor.constraint(equalTo: themeControl.bottomAnchor, constant: 18),
            fontSectionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            fontLabel.centerYAnchor.constraint(equalTo: fontSectionLabel.centerYAnchor),
            fontLabel.trailingAnchor.constraint(equalTo: fontStepper.leadingAnchor, constant: -8),
            fontStepper.centerYAnchor.constraint(equalTo: fontSectionLabel.centerYAnchor),
            fontStepper.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            doneButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            doneButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])

        refreshFontLabel()
        self.view = view
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func refreshFontLabel() {
        fontLabel.stringValue = "\(Int(Settings.shared.fontSize.rounded())) pt"
    }

    @objc private func appearanceChanged(_ sender: NSSegmentedControl) {
        let idx = sender.indexOfSelectedItem
        guard idx < Appearance.allCases.count else { return }
        Settings.shared.appearance = Appearance.allCases[idx]
        onChange?()
    }

    @objc private func themeChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard idx < Theme.allCases.count else { return }
        Settings.shared.theme = Theme.allCases[idx]
        onChange?()
    }

    @objc private func fontChanged(_ sender: NSStepper) {
        Settings.shared.fontSize = CGFloat(sender.integerValue)
        refreshFontLabel()
        onChange?()
    }

    @objc private func close() {
        view.window?.sheetParent?.endSheet(view.window!)
    }
}
