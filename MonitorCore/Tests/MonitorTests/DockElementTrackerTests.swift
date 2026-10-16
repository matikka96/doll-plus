import XCTest
@testable import Monitor

private final class FakeDock: Dock {
    var dockItems: [DockItem<String>] = []
    var badges: [String: String] = [:]
    var deadElements: Set<String> = []

    func items() -> [DockItem<String>] {
        dockItems.filter { !deadElements.contains($0.element) }
    }

    func statusLabel(of element: String) throws -> String? {
        if deadElements.contains(element) {
            throw StaleDockElement()
        }
        return badges[element]
    }

    func restart(withBadge badge: String) {
        deadElements.formUnion(dockItems.map(\.element))
        dockItems = [finder, DockItem(element: "new", title: "Slack", bundleId: "com.tinyspeck.slackmacgap")]
        badges["new"] = badge
    }

    let finder = DockItem(element: "finder", title: "Finder", bundleId: "com.apple.finder")
}

final class DockElementTrackerTests: XCTestCase {
    private let dock = FakeDock()
    private lazy var tracker = DockElementTracker(dock: dock)
    private var published: [String?] = []

    override func setUp() {
        dock.dockItems = [dock.finder, DockItem(element: "old", title: "Slack", bundleId: "com.tinyspeck.slackmacgap")]
        dock.badges["old"] = "1"
        tracker.observe(bundleId: "com.tinyspeck.slackmacgap", appName: "Slack") { [unowned self] in published.append($0) }
    }

    func testReplacesADeadElementAfterTheDockRestarts() {
        dock.restart(withBadge: "2")

        tracker.publishBadges()

        XCTAssertEqual(published, ["2"])
        XCTAssertEqual(tracker.element(for: "com.tinyspeck.slackmacgap"), "new")
    }

    func testDropsADeadElementThatTheDockNoLongerHas() {
        dock.deadElements = ["old"]

        tracker.publishBadges()

        XCTAssertEqual(published, [nil])
        XCTAssertNil(tracker.element(for: "com.tinyspeck.slackmacgap"))
    }

    func testKeepsTheElementWhileTheRestartedDockHasNoItems() {
        dock.deadElements = ["finder", "old"]

        tracker.publishBadges()
        dock.restart(withBadge: "3")
        tracker.publishBadges()

        XCTAssertEqual(published, [nil, "3"])
    }
}
