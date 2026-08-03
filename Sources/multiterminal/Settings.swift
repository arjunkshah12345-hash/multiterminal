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

enum Brand {
    /// Indigo — the app's accent color (matches the icon).
    static let accent = NSColor(srgbRed: 0.388, green: 0.423, blue: 0.902, alpha: 1.0)
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

    private init() {}

    var appearance: Appearance {
        get {
            guard let raw = defaults.string(forKey: appearanceKey) else { return .system }
            return Appearance(rawValue: raw) ?? .system
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
}

// MARK: - SettingsViewController

/// A compact preferences sheet: Appearance (System/Light/Dark) + terminal font size.
final class SettingsViewController: NSViewController {

    private let appearanceControl = NSSegmentedControl()
    private let fontStepper = NSStepper()
    private let fontLabel = NSTextField(labelWithString: "")

    var onChange: (() -> Void)?

    init() { super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 150))
        view.translatesAutoresizingMaskIntoConstraints = false

        let appearanceLabel = sectionLabel("Appearance")
        appearanceControl.segmentCount = 3
        for (i, a) in Appearance.allCases.enumerated() {
            appearanceControl.setLabel(a.label, forSegment: i)
        }
        appearanceControl.target = self
        appearanceControl.action = #selector(appearanceChanged)
        appearanceControl.selectedSegment = Appearance.allCases.firstIndex(of: Settings.shared.appearance) ?? 0

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

        view.addSubview(appearanceLabel)
        view.addSubview(appearanceControl)
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

            fontSectionLabel.topAnchor.constraint(equalTo: appearanceControl.bottomAnchor, constant: 18),
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

    @objc private func fontChanged(_ sender: NSStepper) {
        Settings.shared.fontSize = CGFloat(sender.integerValue)
        refreshFontLabel()
        onChange?()
    }

    @objc private func close() {
        view.window?.sheetParent?.endSheet(view.window!)
    }
}
