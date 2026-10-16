import XCTest
@testable import Monitor

final class DockItemMatcherTests: XCTestCase {
    private func item(_ element: String, title: String?, bundleId: String?) -> DockItem<String> {
        DockItem(element: element, title: title, bundleId: bundleId)
    }

    func testMatchesByBundleIdWhenTheTitleDiffers() {
        let dock = [
            item("finder", title: "Finder", bundleId: "com.apple.finder"),
            item("outlook", title: "Microsoft Outlook", bundleId: "com.microsoft.Outlook"),
        ]

        XCTAssertEqual(DockItemMatcher.element(in: dock, bundleId: "com.microsoft.Outlook", appName: "Outlook"), "outlook")
    }

    func testPrefersTheBundleIdOverAnEarlierItemWithTheSameTitle() {
        let dock = [
            item("classic", title: "Teams", bundleId: "com.microsoft.teams"),
            item("new", title: "Teams", bundleId: "com.microsoft.teams2"),
        ]

        XCTAssertEqual(DockItemMatcher.element(in: dock, bundleId: "com.microsoft.teams2", appName: "Teams"), "new")
    }

    func testFallsBackToTheTitleOnlyForItemsWithNoBundleId() {
        let dock = [
            item("other", title: "Slack", bundleId: "com.example.notslack"),
            item("unknown", title: "Slack", bundleId: nil),
        ]

        XCTAssertEqual(DockItemMatcher.element(in: dock, bundleId: "com.tinyspeck.slackmacgap", appName: "Slack"), "unknown")
        XCTAssertNil(DockItemMatcher.element(in: Array(dock.prefix(1)), bundleId: "com.tinyspeck.slackmacgap", appName: "Slack"))
    }
}
