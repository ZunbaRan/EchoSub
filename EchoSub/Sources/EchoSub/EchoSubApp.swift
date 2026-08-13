import AppKit

@main
enum EchoSubApplication {
    private static let delegate = AppDelegate()

    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        application.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController!
    private var floatingWindowController: FloatingSubtitleWindowController?
    private var lyricsWindowController: DesktopLyricsWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        buildMenu()
        mainWindowController = MainWindowController()
        mainWindowController.showWindow(nil)
        mainWindowController.window?.center()
        NSApp.activate(ignoringOtherApps: true)

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .echoToggleFloatingWindow, object: nil, queue: .main) { [weak self] _ in self?.toggleFloatingWindow() })
        observers.append(center.addObserver(forName: .echoToggleLyricsWindow, object: nil, queue: .main) { [weak self] _ in self?.toggleLyricsWindow() })
        observers.append(center.addObserver(forName: .echoOpenSettings, object: nil, queue: .main) { [weak self] _ in self?.showSettings() })
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.saveCurrentProgress()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { mainWindowController.showWindow(nil) }
        return true
    }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 EchoSub", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        let preferences = NSMenuItem(title: "设置…", action: #selector(showSettingsMenu), keyEquivalent: ",")
        preferences.target = self
        appMenu.addItem(preferences)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "退出 EchoSub", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        let playbackItem = NSMenuItem()
        main.addItem(playbackItem)
        let playback = NSMenu(title: "播放")
        playback.addItem(menuItem("显示 / 隐藏悬浮字幕", action: #selector(toggleFloatingMenu), key: "f", modifiers: [.command, .shift]))
        playback.addItem(menuItem("显示 / 隐藏桌面歌词", action: #selector(toggleLyricsMenu), key: "d", modifiers: [.command, .shift]))
        playback.addItem(menuItem("锁定 / 解锁桌面歌词", action: #selector(toggleLyricsLock), key: "l", modifiers: [.command, .shift]))
        playbackItem.submenu = playback

        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = main
    }

    private func menuItem(_ title: String, action: Selector, key: String, modifiers: NSEvent.ModifierFlags) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        return item
    }

    private func toggleFloatingWindow() {
        if let controller = floatingWindowController, controller.window?.isVisible == true {
            controller.window?.orderOut(nil)
        } else {
            let isNew = floatingWindowController == nil
            let controller = floatingWindowController ?? FloatingSubtitleWindowController()
            floatingWindowController = controller
            controller.showWindow(nil)
            if isNew { controller.window?.center() }
            controller.window?.orderFrontRegardless()
        }
    }

    private func toggleLyricsWindow() {
        if let controller = lyricsWindowController, controller.window?.isVisible == true {
            controller.window?.orderOut(nil)
        } else {
            let isNew = lyricsWindowController == nil
            let controller = lyricsWindowController ?? DesktopLyricsWindowController()
            lyricsWindowController = controller
            controller.showWindow(nil)
            if isNew { controller.window?.center() }
            controller.window?.orderFrontRegardless()
        }
    }

    private func showSettings() {
        let controller = settingsWindowController ?? SettingsWindowController()
        settingsWindowController = controller
        controller.showWindow(nil)
        controller.window?.center()
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showSettingsMenu() { showSettings() }
    @objc private func toggleFloatingMenu() { toggleFloatingWindow() }
    @objc private func toggleLyricsMenu() { toggleLyricsWindow() }
    @objc private func toggleLyricsLock() {
        if lyricsWindowController?.window?.isVisible != true { toggleLyricsWindow() }
        lyricsWindowController?.toggleLockedState()
    }
}
