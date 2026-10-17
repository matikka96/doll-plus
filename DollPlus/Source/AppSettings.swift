import Utils

class AppSettings {
    @UserDefaultSetting("SETTINGS_Hide_When_App_Not_Running")
    static var hideWhenAppNotRunning = false

    @UserDefaultSetting("SETTINGS_Hide_When_Nothing_Coming")
    static var hideWhenNothingComing = false

    @UserDefaultSetting("SETTINGS_Grayout_Icon_When_Nothing_Coming")
    static var grayoutIconWhenNothingComing = false

    @UserDefaultSetting("SETTINGS_SHOW_ALERT_IN_FULL_SCREEN_Mode")
    static var showAlertInFullScreenMode = true

    @UserDefaultSetting("SETTINGS_Show_As_Red_Badge")
    static var showAsRedBadge = false

    @UserDefaultSetting("SETTINGS_Show_Only_App_Icon")
    static var showOnlyAppIcon = false

    static var badgeStyle: BadgeStyle {
        get { BadgeStyle(showAsRedBadge: showAsRedBadge, showOnlyAppIcon: showOnlyAppIcon) }
        set {
            showAsRedBadge = newValue.showAsRedBadge
            showOnlyAppIcon = newValue.showOnlyAppIcon
        }
    }

    static var nothingNewStyle: NothingNewStyle {
        get { NothingNewStyle(grayoutIcon: grayoutIconWhenNothingComing, hide: hideWhenNothingComing) }
        set {
            grayoutIconWhenNothingComing = newValue.grayoutIcon
            hideWhenNothingComing = newValue.hide
        }
    }

    @UserDefaultSetting("SETTINGS_Giant_Badge_Enabled_Apps")
    static var giantBadgeConfigs: [String: Bool] = [:]

    static func toggleGiantBadge(for bundleId: String, value: Bool) {
        AppSettings.giantBadgeConfigs[bundleId] = value
    }

    static func isGiantBadgeEnabled(for bundleId: String) -> Bool {
        AppSettings.giantBadgeConfigs[bundleId] ?? false
    }

    @UserDefaultSetting("SETTINGS_APPS_ICON_MASK")
    static var iconMasksConfigs: [String: Bool] = [:]

    static func toggleIconMask(for bundleId: String, value: Bool) {
        AppSettings.iconMasksConfigs[bundleId] = value
    }

    static func isIconMask(for bundleId: String) -> Bool {
        AppSettings.iconMasksConfigs[bundleId] ?? false
    }

    static func migrateNameKeys(_ appNames: [String], to bundleId: String) {
        migrate(&giantBadgeConfigs, from: appNames, to: bundleId)
        migrate(&iconMasksConfigs, from: appNames, to: bundleId)
    }

    private static func migrate(_ configs: inout [String: Bool], from appNames: [String], to bundleId: String) {
        let migrated = SettingsMigration.copyingFirstValue(configs, from: appNames, to: bundleId)
        if migrated != configs {
            configs = migrated
        }
    }
}
