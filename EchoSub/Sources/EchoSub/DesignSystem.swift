import AppKit

enum EchoStyle {
    static let accent = NSColor.systemBlue
    static let windowBackground = NSColor(calibratedWhite: 0.135, alpha: 1)
    static let sidebarBackground = NSColor(calibratedWhite: 0.08, alpha: 0.62)
    static let panelBackground = NSColor(calibratedWhite: 1, alpha: 0.035)
    static let separator = NSColor(calibratedWhite: 1, alpha: 0.08)
    static let textPrimary = NSColor(calibratedWhite: 1, alpha: 0.92)
    static let textSecondary = NSColor(calibratedWhite: 1, alpha: 0.56)
    static let textTertiary = NSColor(calibratedWhite: 1, alpha: 0.34)
    static let highlight = NSColor.systemBlue.withAlphaComponent(0.16)

    static func label(
        _ text: String = "",
        size: CGFloat = 13,
        weight: NSFont.Weight = .regular,
        color: NSColor = textPrimary,
        lines: Int = 1
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.maximumNumberOfLines = lines
        field.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
        if lines != 1 {
            // A label's intrinsic width otherwise wins over the width supplied by
            // stack/table layouts, which clips long subtitles instead of wrapping.
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
            field.cell?.wraps = true
            field.cell?.isScrollable = false
            field.cell?.usesSingleLineMode = false
        }
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    static func button(
        _ title: String = "",
        symbol: String? = nil,
        target: AnyObject? = nil,
        action: Selector? = nil,
        primary: Bool = false
    ) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = primary ? .rounded : .recessed
        button.controlSize = .small
        button.font = .systemFont(ofSize: 12, weight: primary ? .semibold : .medium)
        if let symbol { button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title) }
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        button.translatesAutoresizingMaskIntoConstraints = false
        if primary { button.keyEquivalent = "\r" }
        return button
    }

    static func iconButton(_ symbol: String, help: String, target: AnyObject?, action: Selector?) -> NSButton {
        let button = button("", symbol: symbol, target: target, action: action)
        button.toolTip = help
        button.isBordered = false
        button.contentTintColor = textSecondary
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    static func applySubtitleText(
        _ field: NSTextField,
        text: String,
        font: NSFont,
        color: NSColor,
        alpha: CGFloat = 1
    ) {
        field.stringValue = text
        field.font = font
        field.textColor = color.withAlphaComponent(alpha)
        field.alignment = .left
        field.lineBreakMode = .byWordWrapping
        field.cell?.alignment = .left
        field.cell?.lineBreakMode = .byWordWrapping
        field.cell?.wraps = true
        field.cell?.usesSingleLineMode = false
    }

    static func card() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = panelBackground.cgColor
        view.layer?.cornerRadius = 9
        view.layer?.borderWidth = 0.5
        view.layer?.borderColor = separator.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }
}

extension NSColor {
    convenience init?(echoHex value: String) {
        let cleaned = value.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let number = UInt64(cleaned, radix: 16) else { return nil }
        self.init(
            calibratedRed: CGFloat((number >> 16) & 0xFF) / 255,
            green: CGFloat((number >> 8) & 0xFF) / 255,
            blue: CGFloat(number & 0xFF) / 255,
            alpha: 1
        )
    }

    var echoHex: String {
        let color = usingColorSpace(.deviceRGB) ?? self
        return String(format: "#%02X%02X%02X", Int(round(color.redComponent * 255)), Int(round(color.greenComponent * 255)), Int(round(color.blueComponent * 255)))
    }
}

extension AppSettings {
    var englishSubtitleColor: NSColor { NSColor(echoHex: englishColorHex) ?? .white }
    var chineseSubtitleColor: NSColor { NSColor(echoHex: chineseColorHex) ?? .systemYellow }
}

extension NSView {
    func pinEdges(to other: NSView, insets: NSEdgeInsets = .init()) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: other.trailingAnchor, constant: -insets.right),
            topAnchor.constraint(equalTo: other.topAnchor, constant: insets.top),
            bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -insets.bottom),
        ])
    }

    func removeAllSubviews() {
        subviews.forEach { $0.removeFromSuperview() }
    }
}

final class SeparatorView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = EchoStyle.separator.cgColor
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { nil }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Keeps the visual divider subtle while exposing a comfortably draggable hit area.
final class EchoSplitView: NSSplitView {
    override var dividerThickness: CGFloat { 7 }

    override func drawDivider(in rect: NSRect) {
        let line: NSRect
        if isVertical {
            line = NSRect(x: rect.midX - 0.5, y: rect.minY, width: 1, height: rect.height)
        } else {
            line = NSRect(x: rect.minX, y: rect.midY - 0.5, width: rect.width, height: 1)
        }
        EchoStyle.separator.setFill()
        line.fill()
    }
}

final class LoadingIndicator: NSProgressIndicator {
    init(small: Bool = true) {
        super.init(frame: .zero)
        style = .spinning
        controlSize = small ? .small : .regular
        isIndeterminate = true
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { nil }
}

extension NSImageView {
    func loadRemoteImage(_ value: String?) {
        image = NSImage(systemSymbolName: "play.rectangle.fill", accessibilityDescription: nil)
        contentTintColor = EchoStyle.textTertiary
        guard let value, let url = URL(string: value) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let remote = NSImage(data: data) else { return }
            DispatchQueue.main.async { self?.image = remote; self?.contentTintColor = nil }
        }.resume()
    }
}
