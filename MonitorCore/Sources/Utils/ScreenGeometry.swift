import CoreGraphics

public enum ScreenGeometry {
    // The Accessibility API puts the origin at the top-left corner of the main screen, with y down.
    // `screenFrames` are the `NSScreen.screens` frames, with the main screen first.
    public static func indexOfScreen(holding axFrame: CGRect, screenFrames: [CGRect]) -> Int? {
        guard let mainScreen = screenFrames.first else { return nil }
        let appKitFrame = CGRect(x: axFrame.minX, y: mainScreen.maxY - axFrame.maxY, width: axFrame.width, height: axFrame.height)
        let overlaps = screenFrames.indices.map { (index: $0, area: area(of: screenFrames[$0].intersection(appKitFrame))) }
        return overlaps.filter { $0.area > 0 }.max { $0.area < $1.area }?.index
    }

    private static func area(of rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }
}
