import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let switcher = Switcher()
    private var hotkey: HotkeyTap?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        startWhenTrusted()
    }

    // MARK: - Accessibility permission

    private func startWhenTrusted() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(opts) {
            startHotkey()
            return
        }
        // Poll until the user grants permission in System Settings.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            if AXIsProcessTrusted() {
                t.invalidate()
                self?.startHotkey()
            }
        }
    }

    private func startHotkey() {
        hotkey = HotkeyTap(switcher: switcher)
        if hotkey?.start() != true {
            NSLog("YariAltTab: failed to create event tap")
        }
        // Optional: window previews. Without it we fall back to app icons.
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
        updateMenu()
    }

    // MARK: - Menu bar

    private func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "YariAltTab")
        updateMenu()
    }

    private func updateMenu() {
        let menu = NSMenu()
        let status = NSMenuItem(title: AXIsProcessTrusted() ? "⌥⇥ active" : "Waiting for Accessibility permission…", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        if AXIsProcessTrusted() && !CGPreflightScreenCaptureAccess() {
            let previews = NSMenuItem(title: "Enable Window Previews…", action: #selector(openScreenRecordingSettings), keyEquivalent: "")
            previews.target = self
            menu.addItem(previews)
        }
        menu.addItem(.separator())

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit YariAltTab", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func openScreenRecordingSettings() {
        // Screen Recording grants only take effect after a relaunch.
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("YariAltTab: launch at login failed: \(error)")
        }
        updateMenu()
    }
}
