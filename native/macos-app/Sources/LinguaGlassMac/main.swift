import AppKit

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: MainWindowController?
    private var overlayWindow: OverlayPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyApplicationIcon()
        configureMainMenu()
        overlayWindow = OverlayPanelController()
        mainWindow = MainWindowController()
        mainWindow?.onOverlayVisibilityChange = { [weak self] visible in
            self?.overlayWindow?.setVisible(visible)
        }
        mainWindow?.onOverlayContentChange = { [weak self] english, chinese, partial in
            self?.overlayWindow?.update(english: english, chinese: chinese, partial: partial)
        }
        mainWindow?.onOverlayClickThroughChange = { [weak self] enabled in
            self?.overlayWindow?.setClickThrough(enabled)
        }
        mainWindow?.onOverlayAppearanceChange = { [weak self] isDark, accentIndex in
            self?.overlayWindow?.setAppearance(isDark: isDark, accentIndex: accentIndex)
        }
        overlayWindow?.onClose = { [weak self] in
            self?.mainWindow?.overlayWasClosed()
        }
        mainWindow?.showWindow(nil)
        mainWindow?.window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        mainWindow?.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func applyApplicationIcon() {
        guard let url = Bundle.main.url(forResource: "AppIconMono", withExtension: "icns"),
              let icon = NSImage(contentsOf: url)
        else { return }
        icon.isTemplate = false
        NSApp.applicationIconImage = icon
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu(title: "Main Menu")
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu(title: "LinguaGlass")
        appMenu.addItem(withTitle: "关于 LinguaGlass", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())

        let servicesItem = NSMenuItem(title: "服务", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "服务")
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)
        NSApp.servicesMenu = servicesMenu

        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 LinguaGlass", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "隐藏其他应用", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "全部显示", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 LinguaGlass", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = mainMenu
    }
}
