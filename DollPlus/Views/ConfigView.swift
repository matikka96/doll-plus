import SwiftUI
import ServiceManagement
import Monitor
import Utils
import KeyboardShortcuts

private let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
// Five rows. A longer list scrolls, so the window fits on a laptop screen.
private let monitoredAppListMaxHeight: CGFloat = 170
private let emptyListHeight: CGFloat = 44

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
                SettingRow("Hide while the app isn't running", hint: "The icon comes back when the app starts.") { title in
                    Toggle(title, isOn: $hideWhenAppNotRunning)
                        .accessibilityIdentifier("hideWhenAppNotRunning")
                        .onChange(of: hideWhenAppNotRunning) { enabled in
                            AppSettings.hideWhenAppNotRunning = enabled
                        }
                }
            }

            Section("Alerts") {
                SettingRow("Show alerts when the menu bar is hidden",
                           hint: iconOnly ? "Doesn't apply to Icon only." : "For example, while an app is full screen.") { title in
                    Toggle(title, isOn: $showAlertInFullScreenMode)
                        .accessibilityIdentifier("showAlertInFullScreenMode")
                        .onChange(of: showAlertInFullScreenMode) { enabled in
                            AppSettings.showAlertInFullScreenMode = enabled
                        }
                }
                .disabled(iconOnly)
            }

            Section {
                SettingRow("Launch at login") { title in
                    Toggle(title, isOn: $launchAtLogin)
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
                }
                SettingRow("Shortcut to open this window", hint: "Click the field, then press the keys.") { title in
                    KeyboardShortcuts.Recorder(for: .toggleConfigWindow)
                        .accessibilityLabel(title)
                        .accessibilityIdentifier("toggleConfigWindowShortcut")
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
        HStack(spacing: 12) {
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

    private var monitoredAppList: some View {
        List(selection: $selection) {
            ForEach(items) { item in
                MonitoredAppItemView(appItem: item, iconRevision: iconRevision) {
                    selection = item.id
                    sheet = .app(item)
                }
            }
        }
        .overlay {
            if items.isEmpty {
                Text("No apps yet. Click + to choose one.")
                    .foregroundStyle(.secondary)
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
        .frame(minHeight: items.isEmpty ? emptyListHeight : nil, maxHeight: monitoredAppListMaxHeight)
        .fixedSize(horizontal: false, vertical: true)
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
        SettingRow("Badge", hint: badgeHint) { title in
            Picker(title, selection: $badgeStyle) {
                Text("Number").tag(BadgeStyle.number)
                Text("Red badge").tag(BadgeStyle.redBadge)
                Text("Icon only").tag(BadgeStyle.iconOnly)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("badgeStyle")
            .onChange(of: badgeStyle) { style in
                AppSettings.badgeStyle = style
                MonitorEngine.shared.refreshDisplayModes()
            }
        }
    }

    private var badgeHint: LocalizedStringKey {
        switch badgeStyle {
        case .number: return "Number next to the icon."
        case .redBadge: return "Red badge on the icon."
        case .iconOnly: return "Only the icon, with no alerts."
        }
    }

    private var nothingNewPicker: some View {
        SettingRow("When there's nothing new", hint: nothingNewHint) { title in
            Picker(title, selection: $nothingNewStyle) {
                Text("Show").tag(NothingNewStyle.show)
                Text("Dim").tag(NothingNewStyle.dim)
                Text("Hide").tag(NothingNewStyle.hide)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("nothingNewStyle")
            .onChange(of: nothingNewStyle) { style in
                AppSettings.nothingNewStyle = style
                MonitorEngine.shared.refreshDisplayModes()
            }
        }
    }

    private var nothingNewHint: LocalizedStringKey {
        switch nothingNewStyle {
        case .show: return "The icon stays as it is."
        case .dim: return "The icon is dimmed."
        case .hide: return "The icon is hidden until something arrives."
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
            Button("Quit") {
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
