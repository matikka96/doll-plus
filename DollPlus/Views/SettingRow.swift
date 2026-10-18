import SwiftUI

// The grouped Form aligns a control with the first line of its label, and moves the control below the label
// when the two don't fit side by side.
struct SettingRow<Control: View>: View {
    let title: LocalizedStringKey
    let hint: LocalizedStringKey?
    let control: Control

    init(_ title: LocalizedStringKey, hint: LocalizedStringKey? = nil, @ViewBuilder control: (LocalizedStringKey) -> Control) {
        self.title = title
        self.hint = hint
        self.control = control(title)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let hint {
                    Text(hint)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)

            // VoiceOver still reads the hidden label.
            control
                .labelsHidden()
                .accessibilityHint(hint ?? "")
                .fixedSize()
        }
    }
}
