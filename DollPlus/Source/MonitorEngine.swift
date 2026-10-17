import Foundation
import SwiftUI
import Monitor
import Utils

let defaultWindowSize = NSSize(width: 900, height: 600)
let SETTING_MONITORED_APP_IDS = "SETTING_MONITORED_APP_IDS"
let configWindowFrameName = "DollPlusConfigWindow"
let configWindowContentSize = NSSize(width: 520, height: 740)

class MonitorEngine {

    static var shared = MonitorEngine()

    lazy var configWindow = makeConfigWindow()
    var statusBars: [StatusBarController] = []
    @Published var monitoredApps: [MonitoredApp] = []

    private init() {
    }

    func setup() {
        MonitorService.setupObservers()
        
        if let data = UserDefaults.standard.value(forKey: SETTING_MONITORED_APP_IDS) as? String {
            var seenAppIds = Set<String>()
            let monitoredAppIds = data.split(separator: ",").map(String.init).filter { seenAppIds.insert($0).inserted }
            let monitoredApps: [MonitoredApp] = monitoredAppIds.map { bundleId in
                guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
                    return MonitoredApp(bundleId, appName: bundleId)
                }

                let appName = AppInfo.displayName(ofAppAt: appURL)
                if let bundle = Bundle(url: appURL) {
                    AppSettings.migrateNameKeys(legacyAppNames(of: bundle, displayName: appName), to: bundleId)
                }
                return MonitoredApp(bundleId, appName: appName)
            }

            MonitorEngine.shared.monitoredApps = monitoredApps

            if monitoredApps.count == 0 {
                return showConfigWindow()
            }

            monitoredApps.forEach { app in
                let statusBar = createNewStatusBar()
                statusBar.monitorApp(app: app)
                statusBars.append(statusBar)
            }
        } else {
            showConfigWindow()
        }
    }

    func statusBar(for app: MonitoredApp) -> StatusBarController? {
        statusBars.first { $0.monitoredApp == app }
    }

    func monitor(newApp: MonitoredApp) {
        if (statusBars.contains {
            $0.monitoredApp == newApp
        }) {
            return
        }

        let firstTimeSetup = statusBars.count == 1 && statusBars[0].monitoredApp == nil
        let newStatusBar = firstTimeSetup ? statusBars[0] : createNewStatusBar()
        newStatusBar.monitorApp(app: newApp)
        statusBars.append(newStatusBar)
        monitoredApps.append(newApp)

        saveSelectedApps()
    }

    func refreshDisplayModes() {
        statusBars.forEach {
            $0.refreshDisplayMode()
        }
    }

    func unMonitor(app: MonitoredApp) {
        statusBars = statusBars.filter {
            $0.monitoredApp != app
        }
        monitoredApps = monitoredApps.filter { $0 != app }
        saveSelectedApps()

        if statusBars.count == 0 {
            showConfigWindow()
        }
    }

    func showConfigWindow() {
        // New content reads the settings again, for example a login item that changed in System Settings.
        if !configWindow.isVisible {
            let frame = configWindow.frame
            configWindow.contentViewController = NSHostingController(rootView: ConfigView())
            configWindow.setFrame(frame, display: false)
        }
        NSApp.activate(ignoringOtherApps: true)
        configWindow.makeKeyAndOrderFront(nil)
        configWindow.orderFrontRegardless()
    }

    private func makeConfigWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: configWindowContentSize), styleMask: [.closable, .titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = Utils.appName
        window.isOpaque = true
        if window.setFrameUsingName(configWindowFrameName) {
            // A saved frame can come from an older, larger window.
            let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
            window.setContentSize(configWindowContentSize)
            window.setFrameTopLeftPoint(topLeft)
        } else {
            window.center()
        }
        window.setFrameAutosaveName(configWindowFrameName)
        return window
    }

    private func saveSelectedApps() {
        let data = monitoredApps.map {
                    $0.bundleId
                }
                .joined(separator: ",")
        UserDefaults.standard.set(data, forKey: SETTING_MONITORED_APP_IDS)
        UserDefaults.standard.synchronize()
    }

    private func legacyAppNames(of bundle: Bundle, displayName: String) -> [String] {
        let relaunchName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        let pickName = (bundle.infoDictionary?["CFBundleDisplayName"] ?? bundle.infoDictionary?["CFBundleName"]) as? String
        let searchName = displayName.replacingOccurrences(of: ".app", with: "")
        return [relaunchName, pickName, searchName, displayName].compactMap { $0 }
    }

    private func createNewStatusBar() -> StatusBarController {
        let newStatusBar = StatusBarController()

        return newStatusBar
    }
}

class MonitoredApp: Equatable, Identifiable {
    var id: String { bundleId }
    let bundleId: String
    let appName: String

    init(_ bundleId: String, appName: String) {
        self.bundleId = bundleId
        self.appName = appName
    }

    static func ==(lhs: MonitoredApp, rhs: MonitoredApp) -> Bool {
        lhs.bundleId == rhs.bundleId
    }
}
