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

final class ReportingTextWindow: NSObject {
    private static let contentSize = NSSize(width: 480, height: 160)

    private let reportFile: URL
    private let field = NSTextField()
    private var clicks = 0
    private var monitor: Any?
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: contentSize),
                          styleMask: [.titled, .resizable, .miniaturizable], backing: .buffered, defer: false)

    init(reportFile: URL) {
        self.reportFile = reportFile
        super.init()
        window.title = Bundle.main.bundleURL.deletingPathExtension().lastPathComponent
        window.isRestorable = false
        window.collectionBehavior = .fullScreenPrimary
        field.frame = window.contentLayoutRect.insetBy(dx: 20, dy: 20)
        field.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(field)
        window.initialFirstResponder = field
        NotificationCenter.default.addObserver(self, selector: #selector(writeReport),
                                               name: NSControl.textDidChangeNotification, object: field)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.clicks += 1
            self?.writeReport()
            return event
        }
        writeReport()
    }

    @objc private func writeReport() {
        let report: [String: Any] = ["text": field.stringValue, "clicks": clicks]
        try? JSONSerialization.data(withJSONObject: report).write(to: reportFile, options: .atomic)
    }
}

guard let controlPath = Bundle.main.object(forInfoDictionaryKey: "DollFixtureControlFile") as? String else {
    fatalError("Info.plist has no DollFixtureControlFile")
}
let textWindow = (Bundle.main.object(forInfoDictionaryKey: "DollFixtureReportFile") as? String)
    .map { ReportingTextWindow(reportFile: URL(fileURLWithPath: $0)) }

let app = NSApplication.shared
let fixture = BadgeFixture(controlFile: URL(fileURLWithPath: controlPath))
app.delegate = fixture
let isUIElement = Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool == true
app.setActivationPolicy(isUIElement ? .accessory : .regular)
// An active accessory app with no window loses the activation a few seconds after a status item press.
let window = isUIElement ? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 80), styleMask: [.titled],
                                    backing: .buffered, defer: false) : nil
window?.title = Bundle.main.bundleURL.deletingPathExtension().lastPathComponent
window?.center()
window?.makeKeyAndOrderFront(nil)
textWindow?.window.center()
textWindow?.window.makeKeyAndOrderFront(nil)
app.run()
