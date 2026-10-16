import AppKit
import Monitor

enum DebugStateWriter {
    private static let stateFileArgument = "DollPlusStateFile"
    private static let writeInterval: TimeInterval = 0.25
    private static var timer: Timer?

    static func setup() {
        guard let path = UserDefaults.standard.string(forKey: stateFileArgument) else {
            return
        }

        let url = URL(fileURLWithPath: path)
        timer = Timer.scheduledTimer(withTimeInterval: writeInterval, repeats: true) { _ in
            write(to: url)
        }
    }

    private static func write(to url: URL) {
        let state: [String: Any] = [
            "pid": ProcessInfo.processInfo.processIdentifier,
            "accessibilityTrusted": AXIsProcessTrusted(),
            "updatedAt": Date().timeIntervalSince1970,
            "mainScreenHeight": NSScreen.screens.first?.frame.height ?? 0,
            "apps": MonitorEngine.shared.statusBars.compactMap(\.debugState),
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }
}

private extension StatusBarController {
    var debugState: [String: Any]? {
        guard let app = monitoredApp else {
            return nil
        }

        let button = statusItem.button
        let frame = button?.window?.frame ?? .zero
        return [
            "bundleId": app.bundleId,
            "appName": app.appName,
            "badge": latestBadgeText,
            "dockElementFound": MonitorService.hasDockElement(bundleId: app.bundleId),
            "visible": statusItem.isVisible,
            "title": button?.title ?? "",
            "length": statusItem.length,
            "neededWidth": button?.cell?.cellSize.width ?? 0,
            "width": button?.bounds.width ?? 0,
            "redrawCount": redrawCount,
            "frame": [frame.minX, frame.minY, frame.width, frame.height],
        ]
    }
}
