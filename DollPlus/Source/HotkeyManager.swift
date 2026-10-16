//
//  HotKey.swift
//  Doll
//
//  Created by xiaogd on 2023/1/10.
//

import Foundation
import KeyboardShortcuts

@MainActor
enum HotkeyManager {
    static func setup() {
        KeyboardShortcuts.onKeyUp(for: .toggleConfigWindow) {
            MonitorEngine.shared.showConfigWindow()
        }
    }
}

#if DEBUG
// The shortcut belongs to the personal copy in /Applications.
private let initialToggleConfigWindowShortcut: KeyboardShortcuts.Shortcut? = nil
#else
private let initialToggleConfigWindowShortcut = KeyboardShortcuts.Shortcut(.d, modifiers: [.command, .shift])
#endif

extension KeyboardShortcuts.Name {
    static let toggleConfigWindow = Self("toggleConfigWindow", initial: initialToggleConfigWindowShortcut)
}
