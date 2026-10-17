import SwiftUI

struct AppItemView: View {
    let item: AppItem
    let added: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.fullPath))
                .resizable()
                .frame(width: 26, height: 26)
                .opacity(added ? 0.4 : 1)
            Text(item.localizedName)
                .foregroundStyle(added ? .tertiary : .primary)
                .accessibilityIdentifier("installedAppName")
            Spacer()
            if added {
                Text("Added")
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
