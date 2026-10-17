import Foundation
import Monitor

struct MonitoredAppStatus {
    let running: Bool
    let badge: String

    init(of app: MonitoredApp) {
        running = MonitorService.isMonitoredAppRunning(bundleIdentifier: app.bundleId)
        badge = MonitorEngine.shared.statusBar(for: app)?.latestBadgeText ?? ""
    }

    var rowText: String {
        if !running {
            return NSLocalizedString("Not running", comment: "")
        }
        return badge.isEmpty ? NSLocalizedString("Nothing new", comment: "") : newText
    }

    var sheetText: String {
        let runningText = running ? NSLocalizedString("Running", comment: "") : NSLocalizedString("Not running", comment: "")
        let badgeText = badge.isEmpty ? NSLocalizedString("nothing new", comment: "") : newText
        return "\(runningText) · \(badgeText)"
    }

    private var newText: String {
        String(format: NSLocalizedString("%@ new", comment: ""), badge)
    }
}
