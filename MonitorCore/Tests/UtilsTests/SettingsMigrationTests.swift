import XCTest
import Utils

final class SettingsMigrationTests: XCTestCase {
    func testCopiesTheFirstLegacyValueToTheBundleId() {
        let configs = ["Microsoft Outlook": false, "Outlook": true]

        let migrated = SettingsMigration.copyingFirstValue(configs, from: ["Outlook", "Microsoft Outlook"], to: "com.microsoft.Outlook")

        XCTAssertEqual(migrated["com.microsoft.Outlook"], true)
    }

    func testKeepsAnExistingBundleIdValue() {
        let configs = ["Outlook": true, "com.microsoft.Outlook": false]

        let migrated = SettingsMigration.copyingFirstValue(configs, from: ["Outlook"], to: "com.microsoft.Outlook")

        XCTAssertEqual(migrated, configs)
    }
}
