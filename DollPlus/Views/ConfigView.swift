import SwiftUI
import ServiceManagement
import Monitor
import Utils
import KeyboardShortcuts

private let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
// Five rows. A longer list scrolls, so the window fits on a laptop screen.
private let monitoredAppListMaxHeight: CGFloat = 170

private enum ConfigSheet: Identifiable {
    case add
    case app(MonitoredApp)
    case about

    var id: String {
        switch self {
        case .add: return "add"
        case .app(let app): return "app \(app.bundleId)"
        case .about: return "about"
        }
    }
}

struct ConfigView: View {

    @State private var accessibilityMissing = !AXIsProcessTrusted()
    @State private var items: [MonitoredApp] = []
    @State private var selection: MonitoredApp.ID?
    @State private var sheet: ConfigSheet?
    @State private var iconRevision = 0

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var badgeStyle = AppSettings.badgeStyle
    @State private var nothingNewStyle = AppSettings.nothingNewStyle
    @State private var hideWhenAppNotRunning = AppSettings.hideWhenAppNotRunning
    @State private var showAlertInFullScreenMode = AppSettings.showAlertInFullScreenMode

    private var iconOnly: Bool { badgeStyle == .iconOnly }

    var body: some View {
        Form {
            if accessibilityMissing {
                Section {
                    accessibilityBanner
                }
            }

            Section {
                monitoredAppList
                listButtons
            } header: {
                Text("Monitored apps")
            } footer: {
                Text("Double-click an app, or click its info button, for its icon and alert options.")
                    .foregroundStyle(.secondary)
            }

            Section("Menu bar") {
                badgePicker
                nothingNewPicker
                Toggle(isOn: $hideWhenAppNotRunning) {
                    Text("Hide while the app isn't running")
                    Text(LocalizedStringKey(iconOnly ? "Doesn't apply to Icon only." : "The icon comes back when the app starts."))
                }
                .disabled(iconOnly)
                .accessibilityIdentifier("hideWhenAppNotRunning")
                .onChange(of: hideWhenAppNotRunning) { enabled in
                    AppSettings.hideWhenAppNotRunning = enabled
                }
            }

            Section("Alerts") {
                Toggle(isOn: $showAlertInFullScreenMode) {
                    Text("Show alerts when the menu bar is hidden")
                    Text(LocalizedStringKey(iconOnly ? "Doesn't apply to Icon only." : "For example, while an app is full screen."))
                }
                .disabled(iconOnly)
                .accessibilityIdentifier("showAlertInFullScreenMode")
                .onChange(of: showAlertInFullScreenMode) { enabled in
                    AppSettings.showAlertInFullScreenMode = enabled
                }
            }

            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .accessibilityIdentifier("launchAtLogin")
                    .onChange(of: launchAtLogin) { enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            print("Error while updating launch at login", error)
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                LabeledContent {
                    KeyboardShortcuts.Recorder(for: .toggleConfigWindow)
                        .accessibilityIdentifier("toggleConfigWindowShortcut")
                } label: {
                    Text("Shortcut to open this window")
                    Text("Click the field, then press the keys.")
                }
            } header: {
                Text("General")
            } footer: {
                footer
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: configWindowWidth)
        .sheet(item: $sheet, onDismiss: { iconRevision += 1 }) { sheet in
            switch sheet {
            case .add:
                AddAppSheet(onAdd: add)
            case .app(let app):
                AppSheet(app: app)
            case .about:
                AboutView()
            }
        }
        .onReceive(MonitorEngine.shared.$monitoredApps) { monitoredApps in
            items = monitoredApps
            if let selection, !monitoredApps.contains(where: { $0.id == selection }) {
                self.selection = nil
            }
            if case .app(let app) = sheet, !monitoredApps.contains(app) {
                sheet = nil
            }
        }
        .onReceive(MonitorService.observerStatus) { attached in
            accessibilityMissing = !attached
        }
    }

    private var accessibilityBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: NSLocalizedString("%@ can't read Dock badges", comment: ""), Utils.appName))
                    .fontWeight(.semibold)
                Text(String(format: NSLocalizedString("Turn on %@ in Privacy & Security › Accessibility.", comment: ""), Utils.appName))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open System Settings") {
                NSWorkspace.shared.open(accessibilitySettingsURL)
            }
            .accessibilityIdentifier("openAccessibilitySettings")
        }
    }

    @ViewBuilder
    private var monitoredAppList: some View {
        if items.isEmpty {
            Text("No apps yet. Click + to choose one.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        } else {
            List(selection: $selection) {
                ForEach(items) { item in
                    MonitoredAppItemView(appItem: item, iconRevision: iconRevision) {
                        selection = item.id
                        sheet = .app(item)
                    }
                }
            }
            .contextMenu(forSelectionType: MonitoredApp.ID.self) { ids in
                Button("Remove") {
                    remove(ids)
                }
            } primaryAction: { ids in
                if let item = items.first(where: { ids.contains($0.id) }) {
                    sheet = .app(item)
                }
            }
            .onDeleteCommand(perform: removeSelection)
            // The Form disables the scroll of its content.
            .scrollDisabled(false)
            .frame(maxHeight: monitoredAppListMaxHeight)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var listButtons: some View {
        HStack(spacing: 2) {
            Button {
                sheet = .add
            } label: {
                Image(systemName: "plus")
                    .frame(width: 20, height: 16)
                    .contentShape(Rectangle())
            }
            .help("Add an app")
            .accessibilityLabel("Add an app")
            .accessibilityIdentifier("addApp")

            Divider()
                .frame(height: 14)

            Button(action: removeSelection) {
                Image(systemName: "minus")
                    .frame(width: 20, height: 16)
                    .contentShape(Rectangle())
            }
            .disabled(selection == nil)
            .help("Remove the selected app")
            .accessibilityLabel("Remove the selected app")
            .accessibilityIdentifier("removeApp")

            Spacer()
        }
        .buttonStyle(.borderless)
    }

    private var badgePicker: some View {
        Picker(selection: $badgeStyle) {
            Text("Number").tag(BadgeStyle.number)
            Text("Red badge").tag(BadgeStyle.redBadge)
            Text("Icon only").tag(BadgeStyle.iconOnly)
        } label: {
            Text("Badge")
            Text(badgeHint)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("badgeStyle")
        .onChange(of: badgeStyle) { style in
            AppSettings.badgeStyle = style
            MonitorEngine.shared.refreshDisplayModes()
        }
    }

    private var badgeHint: LocalizedStringKey {
        switch badgeStyle {
        case .number: return "The number of new notifications, next to the icon."
        case .redBadge: return "A red badge on the icon, like in the Dock."
        case .iconOnly: return "Only the icon. Some options below don't apply."
        }
    }

    private var nothingNewPicker: some View {
        Picker(selection: $nothingNewStyle.rejecting { iconOnly && $0 == .hide }) {
            Text("Show").tag(NothingNewStyle.show)
            Text("Dim").tag(NothingNewStyle.dim)
            Text("Hide").selectionDisabled(when: iconOnly).tag(NothingNewStyle.hide)
        } label: {
            Text("When there's nothing new")
            Text(nothingNewHint)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("nothingNewStyle")
        .onChange(of: nothingNewStyle) { style in
            AppSettings.nothingNewStyle = style
            MonitorEngine.shared.refreshDisplayModes()
        }
    }

    private var nothingNewHint: LocalizedStringKey {
        switch nothingNewStyle {
        case .show: return "The icon stays as it is."
        case .dim: return "The icon is dimmed."
        case .hide: return iconOnly ? "Hide doesn't apply to Icon only." : "The icon is hidden until something arrives."
        }
    }

    private var footer: some View {
        HStack {
            Text(verbatim: "\(Utils.appName) \(Utils.appVersion) ·")
                .foregroundStyle(.secondary)
            Button("About") {
                sheet = .about
            }
            .buttonStyle(.link)
            .accessibilityIdentifier("about")
            Spacer()
            Button(String(format: NSLocalizedString("Quit %@", comment: ""), Utils.appName)) {
                exit(0)
            }
            .accessibilityIdentifier("quit")
        }
        .padding(.top, 8)
    }

    private func add(_ app: MonitoredApp) {
        MonitorEngine.shared.monitor(newApp: app)
        selection = app.id
    }

    private func removeSelection() {
        remove(Set([selection].compactMap { $0 }))
    }

    private func remove(_ ids: Set<MonitoredApp.ID>) {
        items.filter { ids.contains($0.id) }.forEach {
            MonitorEngine.shared.statusBar(for: $0)?.destroy()
        }
    }
}
