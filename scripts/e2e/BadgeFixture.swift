import AppKit

final class BadgeFixture: NSObject, NSApplicationDelegate {
    private static let pollInterval: TimeInterval = 0.2

    private let controlFile: URL
    private var timer: Timer?

    init(controlFile: URL) {
        self.controlFile = controlFile
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.syncBadge()
        }
    }

    private func syncBadge() {
        let text = (try? String(contentsOf: controlFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let label = text.isEmpty ? nil : text
        if NSApp.dockTile.badgeLabel != label {
            NSApp.dockTile.badgeLabel = label
        }
    }
}

guard let controlPath = Bundle.main.object(forInfoDictionaryKey: "DollFixtureControlFile") as? String else {
    fatalError("Info.plist has no DollFixtureControlFile")
}

let app = NSApplication.shared
let fixture = BadgeFixture(controlFile: URL(fileURLWithPath: controlPath))
app.delegate = fixture
let isUIElement = Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool == true
app.setActivationPolicy(isUIElement ? .accessory : .regular)
app.run()
