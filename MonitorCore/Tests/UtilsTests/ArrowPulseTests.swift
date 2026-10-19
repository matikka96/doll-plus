import XCTest
import Utils

final class ArrowPulseTests: XCTestCase {
    // GiantBadgeView starts each pulse at the time 0, where the last pulse ended.
    func testEndsAtTheStartScale() {
        XCTAssertEqual(ArrowPulse.scale(at: ArrowPulse.duration), ArrowPulse.scale(at: 0), accuracy: 1e-9)
    }

    func testChangesWithNoJumpInScale() {
        let step = 1.0 / 240
        let times = stride(from: 0, through: ArrowPulse.duration, by: step)
        let scales = times.map(ArrowPulse.scale(at:))
        let largestChange = zip(scales, scales.dropFirst()).map { abs($1 - $0) }.max() ?? 0
        XCTAssertLessThan(largestChange, 0.01)
    }
}
