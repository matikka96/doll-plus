import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 6) {
            Text(Utils.appName)
                .font(.headline)
            Text(String(format: NSLocalizedString("Version %@", comment: ""), Utils.appVersion))
                .foregroundStyle(.secondary)
            Text("Shows the Dock badges of your apps in the menu bar. Based on [Doll](https://github.com/xiaogdgenuine/Doll).")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
            Text("Icon from [Darius Dan - Flaticon](https://www.flaticon.com/free-icons/reminder)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            Button("OK") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("closeAbout")
            .padding(.top, 12)
        }
        .padding(24)
        .frame(width: 300)
    }
}
