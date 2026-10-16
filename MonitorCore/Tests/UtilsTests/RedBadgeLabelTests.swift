import XCTest
import Utils

final class RedBadgeLabelTests: XCTestCase {
    private func label(_ badge: String) -> String {
        RedBadgeLabel.text(for: badge) { $0.count <= 3 }
    }

    func testKeepsABadgeThatFits() {
        for badge in ["", "1", "99", "007", "9+", "99+", "1.5", "new", "•••"] {
            XCTAssertEqual(label(badge), badge, badge)
        }
    }

    func testShowsACountAbove99As99Plus() {
        for badge in ["100", "123", "999+", "1,234", "1 234", "12345678901234567890"] {
            XCTAssertEqual(label(badge), "99+", badge)
        }
    }

    func testShowsADotForATextThatDoesNotFit() {
        for badge in ["hello", "1a2b", "+1234", ",1234"] {
            XCTAssertEqual(label(badge), "•", badge)
        }
    }
}
