import SwiftUI
import Utils

struct AddAppSheet: View {
    var onAdd: (MonitoredApp) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var keyword = ""
    @State private var allApps: [AppItem] = []
    @State private var selection: AppItem.ID?
    private let monitoredIds = Set(MonitorEngine.shared.monitoredApps.map(\.bundleId))

    private var filteredApps: [AppItem] {
        let key = keyword.trimmingCharacters(in: .whitespaces).lowercased()
        return allApps.filter { key.isEmpty || $0.localizedName.lowercased().contains(key) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose an app to monitor")
                .font(.headline)

            TextField("Search", text: $keyword, prompt: Text("Search"))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .accessibilityIdentifier("searchApps")
                .onChange(of: keyword) { _ in
                    selection = nil
                }

            ApplicationListView(apps: filteredApps, monitoredIds: monitoredIds, selection: $selection, onAdd: add)
                .frame(height: 300)
                .overlay {
                    if filteredApps.isEmpty && !keyword.isEmpty {
                        Text(String(format: NSLocalizedString("No app matches “%@”.", comment: ""), keyword))
                            .foregroundStyle(.secondary)
                    }
                }

            HStack {
                Button("Choose from Finder…", action: pickApplication)
                    .accessibilityIdentifier("chooseFromFinder")
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("cancelAdd")
                Button("Add") {
                    if let app = allApps.first(where: { $0.id == selection }) {
                        add(app)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil)
                .accessibilityIdentifier("confirmAdd")
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            AppListService.shared.setup()
        }
        .onReceive(AppListService.shared.$listOfInstalledApplication) { installedApps in
            var appsById: [String: AppInfo] = [:]
            for app in installedApps + AppListService.runningApplications {
                appsById[app.bundleId] = appsById[app.bundleId] ?? app
            }
            allApps = appsById.values
                .sorted { $0.localizedName.localizedCompare($1.localizedName) == .orderedAscending }
                .map { AppItem(bundleId: $0.bundleId, fullPath: $0.fullPath, localizedName: $0.localizedName, icon: $0.icon) }
        }
    }

    private func add(_ app: AppItem) {
        onAdd(MonitoredApp(app.bundleId, appName: app.localizedName))
        dismiss()
    }

    private func pickApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let appURL = panel.url, let bundleId = Bundle(url: appURL)?.bundleIdentifier else {
            return
        }
        onAdd(MonitoredApp(bundleId, appName: AppInfo.displayName(ofAppAt: appURL)))
        dismiss()
    }
}
