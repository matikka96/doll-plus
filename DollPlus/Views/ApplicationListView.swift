import SwiftUI

struct ApplicationListView: View {
    var apps: [AppItem]
    var monitoredIds: Set<AppItem.ID>
    @Binding var selection: AppItem.ID?
    var onAdd: (AppItem) -> Void

    var body: some View {
        List(selection: $selection.rejecting { $0.map(monitoredIds.contains) ?? false }) {
            ForEach(apps) { app in
                AppItemView(item: app, added: monitoredIds.contains(app.id))
                    .selectionDisabled(when: monitoredIds.contains(app.id))
            }
        }
        // primaryAction runs on a double-click; the menu stays empty.
        .contextMenu(forSelectionType: AppItem.ID.self) { _ in
        } primaryAction: { ids in
            if let app = apps.first(where: { ids.contains($0.id) && !monitoredIds.contains($0.id) }) {
                onAdd(app)
            }
        }
    }
}

struct AppItem: Identifiable {
    var id: String {
        bundleId
    }

    var bundleId: String
    var fullPath: String
    var localizedName: String
    var icon: NSImage?
}
