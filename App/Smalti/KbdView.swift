import AppKit
import SmaltiCore

/// A shortcut drawn like the boards' `.kbd`: monospaced 10.5, padded, rounded, faint border.
final class KbdView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let theme: Theme

    init(_ text: String, theme: Theme) {
        self.theme = theme
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = theme.kbd.cornerRadius
        layer?.borderWidth = 1
        layer?.borderColor = theme.kbd.border.nsColor.cgColor
        layer?.backgroundColor = theme.kbd.background.nsColor.cgColor
        label.font = theme.kbdFont
        label.textColor = theme.kbd.text.nsColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: theme.kbd.paddingHorizontal),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -theme.kbd.paddingHorizontal),
            label.topAnchor.constraint(equalTo: topAnchor, constant: theme.kbd.paddingVertical),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -theme.kbd.paddingVertical),
        ])
        self.text = text
    }

    @available(*, unavailable, message: "Built in code only")
    required init?(coder: NSCoder) { nil }

    var text: String {
        get { label.stringValue }
        set {
            label.stringValue = newValue
            isHidden = newValue.isEmpty
        }
    }
}
