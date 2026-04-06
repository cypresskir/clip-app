import AppKit
import SwiftUI
import Combine

class StatusBarController {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover
    private var progressCancellable: AnyCancellable?
    private var baseImage: NSImage?

    init(downloadViewModel: DownloadViewModel) {
        popover = NSPopover()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let hostingView = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(downloadViewModel)
        )
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .transient
        popover.contentViewController = hostingView

        if let button = statusItem?.button {
            if let appIcon = NSApp.applicationIconImage {
                let size = NSSize(width: 22, height: 22)
                let resized = NSImage(size: size, flipped: false) { rect in
                    appIcon.draw(in: rect)
                    return true
                }
                resized.isTemplate = false
                baseImage = resized
                button.image = resized
            } else {
                let fallback = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "Clip")
                baseImage = fallback
                button.image = fallback
            }
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        // Observe download progress to update icon
        progressCancellable = downloadViewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self, weak downloadViewModel] _ in
                guard let self = self, let downloadViewModel = downloadViewModel else { return }
                Task { @MainActor in
                    self.updateIcon(progress: downloadViewModel.overallProgress, activeCount: downloadViewModel.activeDownloadCount)
                }
            }
    }

    deinit {
        progressCancellable?.cancel()
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    private func updateIcon(progress: Double?, activeCount: Int) {
        guard let button = statusItem?.button else { return }

        if let progress = progress, activeCount > 0 {
            let size = NSSize(width: 22, height: 22)
            let img = NSImage(size: size, flipped: false) { rect in
                // Draw base icon dimmed
                self.baseImage?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.4)

                // Draw circular progress
                let center = NSPoint(x: rect.midX, y: rect.midY)
                let radius: CGFloat = 7
                let lineWidth: CGFloat = 2

                // Background circle
                let bgPath = NSBezierPath()
                bgPath.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
                bgPath.lineWidth = lineWidth
                NSColor.gray.withAlphaComponent(0.3).setStroke()
                bgPath.stroke()

                // Progress arc
                let startAngle: CGFloat = 90
                let endAngle = startAngle - CGFloat(progress) * 360
                let progressPath = NSBezierPath()
                progressPath.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
                progressPath.lineWidth = lineWidth
                NSColor(Color("ClipAccent")).setStroke()
                progressPath.stroke()

                return true
            }
            img.isTemplate = false
            button.image = img
        } else {
            button.image = baseImage
        }
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem?.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
