import SwiftUI

extension Binding {
    // Before macOS 14, selectionDisabled(when:) does nothing, so the binding drops the value.
    func rejecting(_ isRejected: @escaping (Value) -> Bool) -> Binding<Value> {
        Binding {
            wrappedValue
        } set: { value in
            if !isRejected(value) {
                wrappedValue = value
            }
        }
    }
}

extension View {
    @ViewBuilder func selectionDisabled(when disabled: Bool) -> some View {
        if #available(macOS 14, *) {
            selectionDisabled(disabled)
        } else {
            self
        }
    }
}
