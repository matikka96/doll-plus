import XCTest
import Utils

final class ScreenGeometryTests: XCTestCase {
    func testFindsTheScreenThatHoldsMostOfTheWindow() {
        let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let right = CGRect(x: 1512, y: 0, width: 2560, height: 1440)
        let above = CGRect(x: 0, y: 982, width: 1920, height: 1080)
        let screenFrames = [main, right, above]
        let cases: [(name: String, axFrame: CGRect, index: Int?)] = [
            ("full screen below the notch of the main screen", CGRect(x: 0, y: 33, width: 1512, height: 949), 0),
            ("full screen on the taller screen at the right", CGRect(x: 1512, y: -458, width: 2560, height: 1440), 1),
            ("full screen on the screen above", CGRect(x: 0, y: -1080, width: 1920, height: 1080), 2),
            ("across the main screen and the screen at the right", CGRect(x: 1400, y: 100, width: 400, height: 300), 1),
            ("on no screen", CGRect(x: -5000, y: 0, width: 100, height: 100), nil),
        ]
        for c in cases {
            XCTAssertEqual(ScreenGeometry.indexOfScreen(holding: c.axFrame, screenFrames: screenFrames), c.index, c.name)
        }
    }
}
