import AppKit
import CryptoKit
import Monitor

enum DebugStateWriter {
    private static let stateFileArgument = "DollPlusStateFile"
    private static let writeInterval: TimeInterval = 0.25
    private static var timer: Timer?
    // tiffRepresentation takes up to 50 ms on the main thread.
    private static let imageDigests = NSMapTable<NSImage, NSString>(keyOptions: [.weakMemory, .objectPointerPersonality],
                                                                     valueOptions: .strongMemory)

    static func setup() {
        guard let path = UserDefaults.standard.string(forKey: stateFileArgument) else {
            return
        }

        ArrowFrameMeter.isOn = true
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
            "arrowAnimations": ArrowFrameMeter.animations,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }

    fileprivate static func digest(of image: NSImage) -> String {
        if let digest = imageDigests.object(forKey: image) {
            return digest as String
        }
        let digest = image.tiffRepresentation.map { SHA256.hash(data: $0).description } ?? ""
        imageDigests.setObject(digest as NSString, forKey: image)
        return digest
    }
}

enum ArrowFrameMeter {
    fileprivate static var isOn = false
    private static var duration: TimeInterval = 0
    private static var end: CFTimeInterval = 0
    private static var lastFrame: CFTimeInterval?
    private static var intervals: [Double] = []
    private static var pulseTimes: [Double] = []
    fileprivate private(set) static var animations: [[String: Any]] = []

    static func begin(duration: TimeInterval) {
        guard isOn else {
            return
        }
        self.duration = duration
        lastFrame = nil
        intervals = []
        pulseTimes = []
        animations.append(["startedAt": CACurrentMediaTime(), "duration": duration, "intervals": intervals,
                           "pulseTimes": pulseTimes])
    }

    static func recordFrame(pulseTime: TimeInterval) {
        guard isOn, !animations.isEmpty else {
            return
        }
        let now = CACurrentMediaTime()
        // SwiftUI starts the animation clock at the first frame, so the time before it loses no frame.
        guard let lastFrame else {
            // A view with a new identity renders once at the pulse time 0, before the animation starts.
            guard pulseTime > 0 else {
                return
            }
            lastFrame = now
            end = now + duration
            pulseTimes = [pulseTime]
            writeFrames()
            return
        }
        guard now <= end else {
            return
        }
        intervals.append(now - lastFrame)
        pulseTimes.append(pulseTime)
        writeFrames()
        self.lastFrame = now
    }

    private static func writeFrames() {
        animations[animations.count - 1]["intervals"] = intervals
        animations[animations.count - 1]["pulseTimes"] = pulseTimes
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
            "redBadgeLabel": redBadgeLabel ?? NSNull(),
            "imageDigest": button?.image.map(DebugStateWriter.digest(of:)) ?? "",
            "frame": [frame.minX, frame.minY, frame.width, frame.height],
            "arrowRefreshInterval": giantBadgePanel.screen?.minimumRefreshInterval ?? 0,
        ]
    }
}
