import SwiftUI

@main
struct ClipApp: App {
    @NSApplicationDelegateAdaptor(ClipAppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ClipAppDelegate.downloadVM)
                .frame(minWidth: 500, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 600, height: 700)

        Settings {
            SettingsView(updateService: ClipAppDelegate.updateService)
        }
    }
}

class ClipAppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static let downloadVM = DownloadViewModel()
    @MainActor static let clipboardMonitor = ClipboardMonitor()
    @MainActor static let updateService = UpdateService()
    private static var statusBarController: StatusBarController?
    private static var didFinishLaunching = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.didFinishLaunching else {
            NSLog("[Clip] applicationDidFinishLaunching called again — ignoring")
            return
        }
        Self.didFinishLaunching = true
        NSLog("[Clip] applicationDidFinishLaunching")

        let showInMenuBar = UserDefaults.standard.object(forKey: "showInMenuBar") as? Bool ?? true
        if showInMenuBar {
            enableMenuBar()
        }

        let showInDock = UserDefaults.standard.object(forKey: "showInDock") as? Bool ?? true
        if !showInDock {
            NSApp.setActivationPolicy(.accessory)
        }

        ClipAppDelegate.clipboardMonitor.start()

        // Check for updates on launch (after a short delay)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            await ClipAppDelegate.updateService.checkForUpdate()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClipAppDelegate.clipboardMonitor.stop()
        ClipAppDelegate.downloadVM.terminateAll()
    }

    func enableMenuBar() {
        NSLog("[Clip] enableMenuBar called")
        if Self.statusBarController == nil {
            Self.statusBarController = StatusBarController(downloadViewModel: ClipAppDelegate.downloadVM)
        }
    }

    func disableMenuBar() {
        Self.statusBarController = nil
    }
}
