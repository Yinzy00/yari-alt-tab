import AppKit
import ApplicationServices

/// Private but stable API (used by every window manager on macOS) to map an
/// AX window element to its CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

struct WindowItem {
    let app: NSRunningApplication
    let element: AXUIElement
    let windowID: CGWindowID
    let title: String
    let isMinimized: Bool

    var displayTitle: String {
        title.isEmpty ? (app.localizedName ?? "?") : title
    }
}

enum WindowList {
    /// All switchable windows, most recently used (front-most) first.
    static func current() -> [WindowItem] {
        let myPID = ProcessInfo.processInfo.processIdentifier
        var items: [WindowItem] = []

        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != myPID {
            let appEl = AXUIElementCreateApplication(app.processIdentifier)
            // Don't let a frozen app freeze the switcher.
            AXUIElementSetMessagingTimeout(appEl, 0.25)

            guard let windows: [AXUIElement] = attr(appEl, kAXWindowsAttribute) else { continue }
            for win in windows {
                guard let subrole: String = attr(win, kAXSubroleAttribute),
                      subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole
                else { continue }

                var wid: CGWindowID = 0
                _ = _AXUIElementGetWindow(win, &wid)

                items.append(WindowItem(
                    app: app,
                    element: win,
                    windowID: wid,
                    title: attr(win, kAXTitleAttribute) ?? "",
                    isMinimized: attr(win, kAXMinimizedAttribute) ?? false
                ))
            }
        }

        // Front-to-back z-order of on-screen windows ≈ most recently used order.
        let zOrder = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? [])
            .compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
        var rank: [CGWindowID: Int] = [:]
        for (i, id) in zOrder.enumerated() where rank[id] == nil { rank[id] = i }

        // Stable sort: visible windows by z-order, then hidden/minimized/other-space ones.
        return items.enumerated().sorted { a, b in
            let ra = rank[a.element.windowID] ?? Int.max
            let rb = rank[b.element.windowID] ?? Int.max
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }

    static func focus(_ item: WindowItem) {
        let appEl = AXUIElementCreateApplication(item.app.processIdentifier)
        if item.app.isHidden { item.app.unhide() }
        if item.isMinimized {
            AXUIElementSetAttributeValue(item.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementSetAttributeValue(item.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(item.element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(appEl, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        item.app.activate()
    }

    static func close(_ item: WindowItem) {
        if let button: AXUIElement = attr(item.element, kAXCloseButtonAttribute) {
            AXUIElementPerformAction(button, kAXPressAction as CFString)
        }
    }

    private static func attr<T>(_ el: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
