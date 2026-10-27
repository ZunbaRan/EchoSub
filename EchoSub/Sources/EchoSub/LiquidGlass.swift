import AppKit

/// macOS 26 起的原生液态玻璃悬浮窗材质。低于该版本时回退到原来的
/// 半透明表现，颜色和透明度语义保持不变。
enum LiquidGlass {
    static var isAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    static let cornerRadius: CGFloat = 12

    /// 旧版把 0.96 的不透明度直接铺成底色；同样的值放到玻璃的 tintColor 上
    /// 会把材质压成实心黑块，所以按比例缩放，保留背景的通透和折射。
    private static let tintDepth = 0.45

    /// 悬浮窗的玻璃底色；低于阈值时完全去掉染色。
    static func tintColor(forBackgroundOpacity opacity: Double) -> NSColor? {
        let strength = min(1, max(0, opacity)) * tintDepth
        guard strength > 0.02 else { return nil }
        return NSColor.black.withAlphaComponent(strength)
    }

    /// 悬浮字幕窗：macOS 26+ 液态玻璃，旧系统为实色圆角卡片。
    static func surface() -> NSView {
        if #available(macOS 26.0, *) { return makeGlass() }
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        return view
    }

    /// 桌面歌词：macOS 26+ 液态玻璃，旧系统保留 HUD 磨砂底板。
    static func hudSurface() -> NSView {
        if #available(macOS 26.0, *) { return makeGlass() }
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        return view
    }

    /// 整窗背景比悬浮字幕更深，保证正文在明亮桌面上的对比度。
    /// 参数 opacity 是染色强度：0 为完全通透，1 为最深。
    static func applyWindowTint(_ opacity: Double = 0.55, to surface: NSView) {
        guard #available(macOS 26.0, *), let glass = surface as? NSGlassEffectView else { return }
        let value = min(1, max(0, opacity))
        glass.tintColor = value > 0.02 ? NSColor.black.withAlphaComponent(value) : nil
    }

    static func applyTint(_ opacity: Double, to surface: NSView) {
        let value = min(1, max(0, opacity))
        if #available(macOS 26.0, *), let glass = surface as? NSGlassEffectView {
            glass.tintColor = tintColor(forBackgroundOpacity: value)
        } else if let effects = surface as? NSVisualEffectView {
            effects.alphaValue = CGFloat(value)
        } else {
            surface.layer?.backgroundColor = EchoStyle.windowBackground
                .withAlphaComponent(CGFloat(value))
                .cgColor
        }
    }

    @available(macOS 26.0, *)
    private static func makeGlass() -> NSGlassEffectView {
        let glass = DraggableGlassEffectView()
        glass.style = .clear
        glass.cornerRadius = cornerRadius
        return glass
    }
}

@available(macOS 26.0, *)
private final class DraggableGlassEffectView: NSGlassEffectView {
    /// 桌面歌词依靠拖动背景移动窗口，玻璃底板也要参与窗口拖动。
    override var mouseDownCanMoveWindow: Bool { true }
}

/// 让非 key 的悬浮窗也保持液态玻璃的完整折射效果。
///
/// Liquid Glass 只在窗口被系统判定为“活跃外观”时才会呈现完整折射。
/// 这里覆盖 NSWindow 的两个私有外观查询，仅影响绘制提示，不改变窗口真实的
/// key/main 状态，也不会抢走前台应用的键盘输入。若未来 macOS 移除或改名
/// 这些选择器，覆盖自然失效并回退磨砂玻璃，不会崩溃。
class LiquidGlassPanel: NSPanel {
    @objc(_hasActiveAppearance)
    private func echo_hasActiveAppearance() -> Bool {
        if LiquidGlass.isAvailable { return true }
        return Self.realActiveAppearance(self, NSSelectorFromString("_hasActiveAppearance"))
    }

    @objc(_hasActiveAppearanceIgnoringKeyFocus)
    private func echo_hasActiveAppearanceIgnoringKeyFocus() -> Bool {
        if LiquidGlass.isAvailable { return true }
        return Self.realActiveAppearance(self, NSSelectorFromString("_hasActiveAppearanceIgnoringKeyFocus"))
    }

    private static func realActiveAppearance(_ object: AnyObject, _ selector: Selector) -> Bool {
        typealias Function = @convention(c) (AnyObject, Selector) -> Bool
        guard class_getInstanceMethod(NSWindow.self, selector) != nil,
              let implementation = class_getMethodImplementation(NSWindow.self, selector) else { return false }
        return unsafeBitCast(implementation, to: Function.self)(object, selector)
    }
}
