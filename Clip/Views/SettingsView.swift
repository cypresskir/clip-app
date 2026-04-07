import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("showInMenuBar") private var showInMenuBar = true
    @AppStorage("showInDock") private var showInDock = true
    @AppStorage("preferredFormat") private var preferredFormat = "MP4"
    @AppStorage("preferredResolution") private var preferredResolution = 1080
    @AppStorage("maxConcurrentDownloads") private var maxConcurrent = 3
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @ObservedObject var updateService: UpdateService
    @StateObject private var diagModel = BinaryDiagnosticsModel()

    var body: some View {
        Form {
            Section {
                Toggle("Show in menu bar", isOn: $showInMenuBar)
                    .onChange(of: showInMenuBar) { _, newValue in
                        if let delegate = NSApp.delegate as? ClipAppDelegate {
                            if newValue {
                                delegate.enableMenuBar()
                            } else {
                                delegate.disableMenuBar()
                            }
                        }
                    }

                Toggle("Show in Dock", isOn: $showInDock)
                    .onChange(of: showInDock) { _, newValue in
                        if newValue {
                            NSApp.setActivationPolicy(.regular)
                        } else {
                            NSApp.setActivationPolicy(.accessory)
                        }
                    }

                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            openAtLogin = !newValue
                        }
                    }
            } header: {
                Text("Appearance")
            }

            Section {
                HStack {
                    Text("Download folder")
                    Spacer()
                    Text(ClipAppDelegate.downloadVM.saveDirectory.abbreviatingWithTilde)
                        .foregroundStyle(.secondary)
                    Button("Change...") {
                        ClipAppDelegate.downloadVM.chooseSaveDirectory()
                    }
                }

                Picker("Preferred format", selection: $preferredFormat) {
                    ForEach(OutputFormat.allCases) { format in
                        Text(format.rawValue).tag(format.rawValue)
                    }
                }

                Picker("Preferred resolution", selection: $preferredResolution) {
                    ForEach(OutputResolution.allCases) { res in
                        Text(res.displayName).tag(res.rawValue)
                    }
                }

                Stepper("Max simultaneous downloads: \(maxConcurrent)", value: $maxConcurrent, in: 1...10)
            } header: {
                Text("Downloads")
            }

            Section {
                HStack {
                    Text("Clip")
                    Spacer()
                    Text("v\(UpdateService.currentVersion)")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Updates")
                    Spacer()
                    if updateService.isChecking {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking...")
                            .foregroundStyle(.secondary)
                    } else if let release = updateService.updateAvailable {
                        Text("v\(release.version) available")
                            .foregroundStyle(ClipTheme.accent)
                        Button("Update") {
                            Task { await updateService.downloadAndInstall() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Text("Up to date")
                            .foregroundStyle(.secondary)
                        Button("Check Now") {
                            Task { await updateService.checkForUpdate() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            } header: {
                Text("About")
            }

            Section {
                ForEach(diagModel.entries) { entry in
                    HStack {
                        Text(entry.label)
                        Spacer()
                        Text(entry.value)
                            .foregroundStyle(entry.ok ? .secondary : ClipTheme.coral)
                            .textSelection(.enabled)
                    }
                }
            } header: {
                Text("Diagnostics")
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 520)
        .onAppear { diagModel.runChecks() }
    }

}

extension String {
    var abbreviatingWithTilde: String {
        replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
