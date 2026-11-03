import AppKit
import CoreGraphics

/// Global keyboard interception via a CGEventTap.
/// Option+Tab opens/advances, Option+Shift+Tab goes back,
/// releasing Option commits, Escape cancels.
/// While the switcher is open: ←/→ move, W closes the window, Q quits the app.
final class HotkeyTap {
    private let switcher: Switcher
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var watchdog: Timer?
    private var observers: [NSObjectProtocol] = []
    /// Tracked synchronously in the tap so fast key repeats never race the UI.
    private var active = false

    private let kTab: Int64 = 48
    private let kEscape: Int64 = 53
    private let kLeft: Int64 = 123
    private let kRight: Int64 = 124
    private let kQ: Int64 = 12
    private let kW: Int64 = 13

    init(switcher: Switcher) {
        self.switcher = switcher
    }

    func start() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<HotkeyTap>.fromOpaque(refcon!).takeUnretainedValue()
            return me.handle(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.source = source
        CGEvent.tapEnable(tap: tap, enable: true)
        startWatchdog()
        return true
    }

    /// Tear down and recreate the tap. Display changes and sleep/wake can leave
    /// a tap silently disabled or invalidated without any callback.
    func restart() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        resetState()
        if !start() { NSLog("YariAltTab: failed to recreate event tap") }
    }

    private func startWatchdog() {
        guard watchdog == nil else { return }
        watchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if let tap = self.tap, CFMachPortIsValid(tap) {
                if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
            } else {
                self.restart()
            }
        }

        let restartSoon: (Notification) -> Void = { [weak self] _ in
            // Give the WindowServer a moment to settle after the change.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.restart() }
        }
        let nc = NotificationCenter.default
        let wnc = NSWorkspace.shared.notificationCenter
        observers = [
            nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: restartSoon),
            wnc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: restartSoon),
            wnc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main, using: restartSoon),
            wnc.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main, using: restartSoon),
        ]
    }

    /// Forget any half-finished switch (e.g. the ⌥ release got lost).
    private func resetState() {
        if active {
            active = false
            DispatchQueue.main.async { self.switcher.cancel() }
        }
    }

    /// Runs on the main run loop. Heavy work is deferred with `async` so the
    /// tap callback returns fast (macOS disables taps that are too slow).
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let option = flags.contains(.maskAlternate)
        let otherMods = flags.contains(.maskCommand) || flags.contains(.maskControl)

        switch type {
        case .flagsChanged:
            if active && !option {
                active = false
                DispatchQueue.main.async { self.switcher.commit() }
            }
            return Unmanaged.passUnretained(event)

        case .keyDown:
            let key = event.getIntegerValueField(.keyboardEventKeycode)

            // ⌥ is no longer down but we never saw it released: drop the stale switch
            // instead of swallowing the user's typing.
            if active && !option { resetState() }

            if key == kTab && option && !otherMods {
                let back = flags.contains(.maskShift)
                if active && switcher.isOpen {
                    DispatchQueue.main.async { self.switcher.step(back ? -1 : 1) }
                } else {
                    active = true
                    DispatchQueue.main.async { self.switcher.show(reverse: back) }
                }
                return nil
            }

            guard active else { return Unmanaged.passUnretained(event) }

            switch key {
            case kEscape:
                active = false
                DispatchQueue.main.async { self.switcher.cancel() }
            case kLeft: DispatchQueue.main.async { self.switcher.step(-1) }
            case kRight: DispatchQueue.main.async { self.switcher.step(1) }
            case kQ: DispatchQueue.main.async { self.switcher.quitSelectedApp() }
            case kW: DispatchQueue.main.async { self.switcher.closeSelectedWindow() }
            default: break
            }
            // Swallow every key while the switcher is open.
            return nil

        case .keyUp:
            return active ? nil : Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }
}
