import XCTest
import Utils

final class MenuBarStyleTests: XCTestCase {
    func testReadsTheStoredBadgeSettings() {
        let cases: [(showAsRedBadge: Bool, showOnlyAppIcon: Bool, style: BadgeStyle)] = [
            (false, false, .number),
            (true, false, .redBadge),
            (false, true, .iconOnly),
            (true, true, .iconOnly),
        ]
        for c in cases {
            XCTAssertEqual(BadgeStyle(showAsRedBadge: c.showAsRedBadge, showOnlyAppIcon: c.showOnlyAppIcon), c.style, "\(c)")
        }
    }

    func testWritesOneBadgeSettingForEachStyle() {
        let cases: [(style: BadgeStyle, showAsRedBadge: Bool, showOnlyAppIcon: Bool)] = [
            (.number, false, false),
            (.redBadge, true, false),
            (.iconOnly, false, true),
        ]
        for c in cases {
            XCTAssertEqual(c.style.showAsRedBadge, c.showAsRedBadge, "\(c.style)")
            XCTAssertEqual(c.style.showOnlyAppIcon, c.showOnlyAppIcon, "\(c.style)")
        }
    }

    func testReadsTheStoredNothingNewSettings() {
        let cases: [(grayoutIcon: Bool, hide: Bool, style: NothingNewStyle)] = [
            (false, false, .show),
            (true, false, .dim),
            (false, true, .hide),
            (true, true, .hide),
        ]
        for c in cases {
            XCTAssertEqual(NothingNewStyle(grayoutIcon: c.grayoutIcon, hide: c.hide), c.style, "\(c)")
        }
    }

    func testWritesOneNothingNewSettingForEachStyle() {
        let cases: [(style: NothingNewStyle, grayoutIcon: Bool, hide: Bool)] = [
            (.show, false, false),
            (.dim, true, false),
            (.hide, false, true),
        ]
        for c in cases {
            XCTAssertEqual(c.style.grayoutIcon, c.grayoutIcon, "\(c.style)")
            XCTAssertEqual(c.style.hide, c.hide, "\(c.style)")
        }
    }
}
