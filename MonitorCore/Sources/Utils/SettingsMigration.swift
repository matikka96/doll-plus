public enum SettingsMigration {
    public static func copyingFirstValue(_ configs: [String: Bool], from oldKeys: [String], to newKey: String) -> [String: Bool] {
        guard configs[newKey] == nil, let value = oldKeys.lazy.compactMap({ configs[$0] }).first else {
            return configs
        }

        var migrated = configs
        migrated[newKey] = value
        return migrated
    }
}
