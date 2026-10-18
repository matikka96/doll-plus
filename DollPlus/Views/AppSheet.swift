import SwiftUI

private let sheetPadding: CGFloat = 20

struct AppSheet: View {
    let app: MonitoredApp

    @Environment(\.dismiss) private var dismiss
    @State private var iconIsMask: Bool
    @State private var showGiantBadge: Bool
    @State private var hasCustomIcon: Bool
    @State private var iconRevision = 0

    init(app: MonitoredApp) {
        self.app = app
        _iconIsMask = State(initialValue: AppSettings.isIconMask(for: app.bundleId))
        _showGiantBadge = State(initialValue: AppSettings.isGiantBadgeEnabled(for: app.bundleId))
        _hasCustomIcon = State(initialValue: Storage.hasCustomizedAppIcon(for: app.bundleId))
    }

    var body: some View {
        // The grouped Form has its own 20 pt margin, so the sheet padding goes only on the header and the buttons.
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: Storage.appIcon(for: app.bundleId))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 44, height: 44)
                    .id(iconRevision)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.appName)
                        .font(.headline)
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(MonitoredAppStatus(of: app).sheetText)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding([.horizontal, .top], sheetPadding)

            Form {
                SettingRow("Menu bar icon", hint: hasCustomIcon ? "Your own image." : "The app's own icon.") { _ in
                    HStack {
                        if hasCustomIcon {
                            Button("Reset", action: resetIcon)
                                .accessibilityIdentifier("resetIcon")
                        }
                        Button("Choose…", action: pickIconFile)
                            .accessibilityIdentifier("chooseIcon")
                    }
                }

                SettingRow("Invert the icon in Dark Mode", hint: "For dark, single-colour icons.") { title in
                    SettingSwitch(title, isOn: $iconIsMask)
                        .accessibilityIdentifier("iconIsMask")
                        .onChange(of: iconIsMask) { enabled in
                            AppSettings.toggleIconMask(for: app.bundleId, value: enabled)
                            refreshIcons()
                        }
                }

                SettingRow("Point to new notifications", hint: "A big red arrow under the icon while the app is in the background.") { title in
                    SettingSwitch(title, isOn: $showGiantBadge)
                        .accessibilityIdentifier("giantBadge")
                        .onChange(of: showGiantBadge) { enabled in
                            AppSettings.toggleGiantBadge(for: app.bundleId, value: enabled)
                        }
                }
            }
            .formStyle(.grouped)
            .toggleStyle(.switch)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(role: .destructive) {
                    MonitorEngine.shared.statusBar(for: app)?.destroy()
                    dismiss()
                } label: {
                    Text("Stop Monitoring")
                        .foregroundStyle(.red)
                }
                .accessibilityIdentifier("stopMonitoring")

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("done")
            }
            .padding([.horizontal, .bottom], sheetPadding)
        }
        .frame(width: 440)
    }

    private func pickIconFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .application]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        if let image = NSImage(contentsOf: url) {
            Storage.storeCustomizedAppIcon(for: app.bundleId, image: image)
        } else if let rep = NSWorkspace.shared.icon(forFile: url.path)
            .bestRepresentation(for: NSRect(x: 0, y: 0, width: 1024, height: 1024), context: nil, hints: nil) {
            let appIcon = NSImage(size: rep.size)
            appIcon.addRepresentation(rep)
            Storage.storeCustomizedAppIcon(for: app.bundleId, image: appIcon)
        }
        refreshIcons()
    }

    private func resetIcon() {
        Storage.removeCustomizedAppIcon(for: app.bundleId)
        refreshIcons()
    }

    private func refreshIcons() {
        MonitorEngine.shared.statusBars.forEach {
            $0.refreshIcon()
        }
        hasCustomIcon = Storage.hasCustomizedAppIcon(for: app.bundleId)
        iconRevision += 1
    }
}
