import AppKit

/// Owns the switcher state: the window list, the selection and the panel.
final class Switcher {
    private var items: [WindowItem] = []
    private var selected = 0
    private let panel = SwitcherPanel()
    private var pendingShow: DispatchWorkItem?

    var isOpen: Bool { !items.isEmpty }

    /// A quick ⌥⇥ tap switches without flashing the panel, like the native ⌘⇥.
    private let showDelay: TimeInterval = 0.1

    init() {
        panel.onClick = { [weak self] index in
            self?.selected = index
            self?.commit()
        }
    }

    func show(reverse: Bool) {
        items = WindowList.current()
        guard !items.isEmpty else { return }
        // Index 0 is the current window, so start on the previous one.
        selected = reverse ? items.count - 1 : min(1, items.count - 1)

        // Start capturing right away so previews are mostly ready when the panel appears.
        Thumbnails.shared.prune(keeping: Set(items.map(\.windowID)))
        Thumbnails.shared.refresh(items.filter { !$0.isMinimized }.map(\.windowID)) { [weak self] id, image in
            self?.panel.setThumbnail(image, for: id)
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.panel.present(self.items, selected: self.selected)
        }
        pendingShow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + showDelay, execute: work)
    }

    func step(_ delta: Int) {
        guard !items.isEmpty else { return }
        selected = (selected + delta + items.count) % items.count
        panel.select(selected)
    }

    func commit() {
        let target = items.indices.contains(selected) ? items[selected] : nil
        hide()
        if let target { WindowList.focus(target) }
    }

    func cancel() {
        hide()
    }

    func closeSelectedWindow() {
        guard items.indices.contains(selected) else { return }
        WindowList.close(items[selected])
        removeSelected()
    }

    func quitSelectedApp() {
        guard items.indices.contains(selected) else { return }
        let app = items[selected].app
        app.terminate()
        items.removeAll { $0.app == app }
        selected = min(selected, max(items.count - 1, 0))
        refreshPanel()
    }

    private func removeSelected() {
        items.remove(at: selected)
        selected = min(selected, max(items.count - 1, 0))
        refreshPanel()
    }

    private func refreshPanel() {
        if items.isEmpty { panel.dismiss() } else if panel.isVisible { panel.present(items, selected: selected) }
    }

    private func hide() {
        pendingShow?.cancel()
        pendingShow = nil
        panel.dismiss()
        items = []
    }
}
