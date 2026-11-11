import AppKit
import SwiftUI
import UserNotifications

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let manager = AppsManager()
    private let hotKeys = HotKeys()
    private var statusItem: NSStatusItem!
    private var panel: KeyPanel!
    private var prefsWindow: NSWindow?
    private var flagsMonitor: Any?
    private var lastHide = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = quitterLogo()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)

        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 480), styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: true)
        // Show on the current Space, including full-screen ones; without this it opens on the desktop Space.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: MenuView(
            m: manager, openPrefs: { [weak self] in self?.showPrefs() }, close: { [weak self] in self?.hidePanel() }))

        reloadHotKeys()
        NotificationCenter.default.addObserver(self, selector: #selector(reloadHotKeys),
                                               name: UserDefaults.didChangeNotification, object: nil)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { NSLog("Quitter: notifications unavailable: %@", error.localizedDescription) }
        }
        if !UserDefaults.standard.bool(forKey: K.welcomed) {
            UserDefaults.standard.set(true, forKey: K.welcomed)
            showPrefs()
        }
    }

    @objc private func reloadHotKeys() {
        let d = UserDefaults.standard
        func shortcut(_ key: String) -> Shortcut? { d.string(forKey: key).flatMap(Shortcut.init(rawValue:)) }
        hotKeys.set(1, shortcut(K.shortcutActivate)) { [weak self] in self?.togglePanel() }
        hotKeys.set(2, shortcut(K.shortcutQuit)) { [weak self] in self?.manager.quitSelected(force: false) }
        hotKeys.set(3, shortcut(K.shortcutForceQuit)) { [weak self] in self?.manager.quitSelected(force: true) }
    }

    @objc private func togglePanel() {
        // A status-item click first resigns the panel (hiding it); don't reopen it on the same click.
        guard Date().timeIntervalSince(lastHide) > 0.3 else { return }
        if panel.isVisible { return hidePanel() }
        guard let button = statusItem.button, let window = button.window else { return }
        let r = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen?.visibleFrame ?? r
        let x = min(max(r.midX - panel.frame.width / 2, screen.minX + 8), screen.maxX - panel.frame.width - 8)
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: r.minY - 4))

        manager.optionHeld = NSEvent.modifierFlags.contains(.option)
        manager.startSampling()
        panel.makeKeyAndOrderFront(nil) // non-activating panel: becomes key without activating the app
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            self?.manager.optionHeld = e.modifierFlags.contains(.option)
            return e
        }
    }

    private func hidePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        lastHide = Date()
        manager.stopSampling()
        manager.optionHeld = false
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        flagsMonitor = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        if notification.object as? NSWindow === panel { hidePanel() }
    }

    private func showPrefs() {
        hidePanel()
        if prefsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: PrefsView(m: manager)))
            w.title = "Quitter Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            prefsWindow = w
        }
        NSApp.activate()
        prefsWindow?.center()
        prefsWindow?.makeKeyAndOrderFront(nil)
    }
}
