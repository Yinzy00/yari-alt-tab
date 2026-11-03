import AppKit

/// The floating HUD with one tile per window.
final class SwitcherPanel {
    var onClick: ((Int) -> Void)?

    private let window: NSPanel
    private let blur = NSVisualEffectView()
    private var tiles: [TileView] = []

    private let tileSize = TileView.size
    private let spacing: CGFloat = 8
    private let padding: CGFloat = 16

    var isVisible: Bool { window.isVisible }

    init() {
        window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        window.level = .popUpMenu
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 18
        blur.layer?.masksToBounds = true
        window.contentView = blur
    }

    func present(_ items: [WindowItem], selected: Int) {
        tiles.forEach { $0.removeFromSuperview() }
        tiles = []

        // Screens can briefly be missing while displays are being (dis)connected.
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let maxWidth = screen.visibleFrame.width * 0.9 - padding * 2
        let perRow = max(1, min(items.count, Int((maxWidth + spacing) / (tileSize.width + spacing))))
        let rows = Int(ceil(Double(items.count) / Double(perRow)))

        let width = CGFloat(perRow) * tileSize.width + CGFloat(perRow - 1) * spacing + padding * 2
        let height = CGFloat(rows) * tileSize.height + CGFloat(rows - 1) * spacing + padding * 2

        for (i, item) in items.enumerated() {
            let row = i / perRow, col = i % perRow
            let x = padding + CGFloat(col) * (tileSize.width + spacing)
            let y = height - padding - CGFloat(row + 1) * tileSize.height - CGFloat(row) * spacing
            let tile = TileView(origin: NSPoint(x: x, y: y), item: item,
                                thumbnail: Thumbnails.shared.cached(item.windowID))
            tile.onClick = { [weak self] in self?.onClick?(i) }
            blur.addSubview(tile)
            tiles.append(tile)
        }
        select(selected)

        let f = screen.visibleFrame
        window.setFrame(NSRect(x: f.midX - width / 2, y: f.midY - height / 2, width: width, height: height), display: true)
        window.orderFrontRegardless()
    }

    func select(_ index: Int) {
        for (i, tile) in tiles.enumerated() { tile.isSelected = i == index }
    }

    func setThumbnail(_ image: NSImage, for windowID: CGWindowID) {
        for tile in tiles where tile.windowID == windowID { tile.setThumbnail(image) }
    }

    func dismiss() {
        window.orderOut(nil)
        tiles.forEach { $0.removeFromSuperview() }
        tiles = []
    }
}

/// A window preview with a small app icon badge and the title underneath.
/// Falls back to a large app icon when there's no preview (no permission,
/// minimized window, or capture still in flight).
private final class TileView: NSView {
    static let size = NSSize(width: 236, height: 176)
    private static let inset: CGFloat = 8
    private static let titleHeight: CGFloat = 18

    let windowID: CGWindowID
    var onClick: (() -> Void)?
    var isSelected = false { didSet { needsDisplay = true } }

    private let preview = NSImageView()
    private let badge = NSImageView()
    private let appIcon: NSImage?

    init(origin: NSPoint, item: WindowItem, thumbnail: NSImage?) {
        windowID = item.windowID
        appIcon = item.app.icon
        super.init(frame: NSRect(origin: origin, size: Self.size))

        let inset = Self.inset
        let previewFrame = NSRect(x: inset, y: inset + Self.titleHeight + 4,
                                  width: bounds.width - inset * 2,
                                  height: bounds.height - inset * 2 - Self.titleHeight - 4)
        preview.frame = previewFrame
        preview.imageAlignment = .alignCenter
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 6
        preview.layer?.masksToBounds = true
        if item.isMinimized || item.app.isHidden { preview.alphaValue = 0.5 }
        addSubview(preview)

        badge.frame = NSRect(x: previewFrame.minX + 4, y: previewFrame.minY + 4, width: 32, height: 32)
        badge.image = appIcon
        addSubview(badge)

        let label = NSTextField(labelWithString: item.displayTitle)
        label.frame = NSRect(x: inset, y: inset, width: bounds.width - inset * 2, height: Self.titleHeight)
        label.alignment = .center
        label.font = .systemFont(ofSize: 12)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)

        toolTip = "\(item.app.localizedName ?? "") — \(item.displayTitle)"

        if let thumbnail { setThumbnail(thumbnail) } else { showIconFallback() }
    }

    required init?(coder: NSCoder) { fatalError() }

    func setThumbnail(_ image: NSImage) {
        preview.image = image
        preview.imageScaling = .scaleProportionallyDown
        badge.isHidden = false
    }

    private func showIconFallback() {
        // Copy so we don't resize the app's shared icon instance.
        let icon = appIcon?.copy() as? NSImage
        icon?.size = NSSize(width: 80, height: 80)
        preview.image = icon
        preview.imageScaling = .scaleNone
        badge.isHidden = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isSelected else { return }
        NSColor.labelColor.withAlphaComponent(0.15).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
}
