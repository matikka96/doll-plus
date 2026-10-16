import XCTest
import Utils

final class AppDisplayNameTests: XCTestCase {
    func testRemovesOnlyTheTrailingAppExtension() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = directory.appendingPathComponent("My.app Tools.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertEqual(AppInfo.displayName(ofAppAt: app), "My.app Tools")
    }
}
