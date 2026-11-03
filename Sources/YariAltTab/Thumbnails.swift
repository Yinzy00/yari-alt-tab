import AppKit
import ScreenCaptureKit

/// Window previews via ScreenCaptureKit (needs Screen Recording permission).
/// Previews are cached so reopening the switcher shows the last one instantly
/// while a fresh capture is in flight.
final class Thumbnails {
    static let shared = Thumbnails()

    private var cache: [CGWindowID: NSImage] = [:]
    /// Longest side of a preview, in points. Captured at 2x for Retina.
    private let maxDimension: CGFloat = 220

    var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    func cached(_ id: CGWindowID) -> NSImage? { cache[id] }

    /// Captures the given windows concurrently; `update` is called on the main
    /// thread as each preview arrives.
    func refresh(_ ids: [CGWindowID], update: @escaping (CGWindowID, NSImage) -> Void) {
        guard hasPermission, !ids.isEmpty else { return }
        let maxDimension = self.maxDimension

        Task {
            guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            else { return }
            let byID = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { a, _ in a })

            await withTaskGroup(of: Void.self) { group in
                for id in ids {
                    guard let window = byID[id], window.frame.width > 1, window.frame.height > 1 else { continue }
                    group.addTask {
                        let scale = min(1, maxDimension / max(window.frame.width, window.frame.height)) * 2
                        let config = SCStreamConfiguration()
                        config.width = max(1, Int(window.frame.width * scale))
                        config.height = max(1, Int(window.frame.height * scale))
                        config.showsCursor = false
                        config.ignoreShadowsSingleWindow = true

                        let filter = SCContentFilter(desktopIndependentWindow: window)
                        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                        else { return }

                        await MainActor.run {
                            let ns = NSImage(cgImage: image, size: .zero)
                            self.cache[id] = ns
                            update(id, ns)
                        }
                    }
                }
            }
        }
    }

    /// Drop previews of windows that no longer exist.
    func prune(keeping ids: Set<CGWindowID>) {
        cache = cache.filter { ids.contains($0.key) }
    }
}
