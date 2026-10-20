import Foundation

// The Doll key names are fixed, and the Doll Plus key names can change, so each value goes through AppSettings.
enum DollImport {
    private static let dollDomainArgument = "DollPlusDollDomain"
    private static let dollAppIconsArgument = "DollPlusDollAppIcons"
    private static let dollBundleId = "com.xiaogd.Doll"
    private static let dollMonitoredAppIdsKey = "SETTING_MONITORED_APP_IDS"

    private static let dollSettings: [String: (Any) -> Void] = [
        "SETTINGS_Hide_When_App_Not_Running": typedSetter { AppSettings.hideWhenAppNotRunning = $0 },
        "SETTINGS_Hide_When_Nothing_Coming": typedSetter { AppSettings.hideWhenNothingComing = $0 },
        "SETTINGS_Grayout_Icon_When_Nothing_Coming": typedSetter { AppSettings.grayoutIconWhenNothingComing = $0 },
        "SETTINGS_SHOW_ALERT_IN_FULL_SCREEN_Mode": typedSetter { AppSettings.showAlertInFullScreenMode = $0 },
        "SETTINGS_Show_As_Red_Badge": typedSetter { AppSettings.showAsRedBadge = $0 },
        "SETTINGS_Show_Only_App_Icon": typedSetter { AppSettings.showOnlyAppIcon = $0 },
        "SETTINGS_Giant_Badge_Enabled_Apps": typedSetter { AppSettings.giantBadgeConfigs = $0 },
        "SETTINGS_APPS_ICON_MASK": typedSetter { AppSettings.iconMasksConfigs = $0 },
    ]

    private static var dollDomain: String {
        UserDefaults.standard.string(forKey: dollDomainArgument) ?? dollBundleId
    }

    private static var dollAppIcons: URL {
        if let path = UserDefaults.standard.string(forKey: dollAppIconsArgument) {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return Storage.applicationDirectory.deletingLastPathComponent()
            .appendingPathComponent(dollBundleId, isDirectory: true)
            .appendingPathComponent("app_icons", isDirectory: true)
    }

    static func importOnFirstLaunch() -> Bool {
        guard !AppSettings.dollImportChecked else {
            return false
        }
        AppSettings.dollImportChecked = true
        let usedEarlierDollPlus = MonitorEngine.hasStoredMonitoredApps
        guard !usedEarlierDollPlus,
              let dollDefaults = UserDefaults.standard.persistentDomain(forName: dollDomain) else {
            return false
        }

        for (key, value) in dollDefaults {
            dollSettings[key]?(value)
        }
        let monitoredAppIds = (dollDefaults[dollMonitoredAppIdsKey] as? String).map(MonitorEngine.monitoredAppIds) ?? []
        MonitorEngine.storeMonitoredAppIds(monitoredAppIds)
        copyAppIcons()
        return true
    }

    private static func typedSetter<Value>(_ write: @escaping (Value) -> Void) -> (Any) -> Void {
        { value in
            if let value = value as? Value {
                write(value)
            }
        }
    }

    private static func copyAppIcons() {
        let fileManager = FileManager.default
        guard let icons = try? fileManager.contentsOfDirectory(at: dollAppIcons, includingPropertiesForKeys: nil) else {
            return
        }

        for icon in icons {
            try? fileManager.copyItem(at: icon, to: Storage.appIconsDirectory.appendingPathComponent(icon.lastPathComponent))
        }
    }
}
