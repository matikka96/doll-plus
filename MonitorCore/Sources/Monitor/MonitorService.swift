import AppKit
import Combine

let checkInterval: TimeInterval = 1.0
let ticksPerFullResolve = 10

public struct MonitorService {
    public static let observerStatus = PassthroughSubject<Bool, Never>()
    private static let tracker = DockElementTracker(dock: AXDock())
    private static var timer: Timer?
    private static var ticksSinceFullResolve = 0
    private static var observedDockProcessId: pid_t?
    private static var appCreateObserver: AXObserver?
    private static var appDestroyObserver: AXObserver?
    private static let onElementCreateCallback = ObserverCallbackInfo {
        tracker.resolveMissingElements()
    }
    private static let onElementDestroyCallback = ObserverCallbackInfo {
        tracker.publishBadges()
    }

    public static func setupObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                if let bundleId = app?.bundleIdentifier {
                    tracker.resolveElements(for: [bundleId])
                }
            }
        }

        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { _ in
            if AXDock.processId != observedDockProcessId || appCreateObserver == nil || appDestroyObserver == nil {
                setupAxObserversOnDock()
            }

            ticksSinceFullResolve += 1
            if ticksSinceFullResolve >= ticksPerFullResolve {
                resolveAllElements()
            }

            tracker.publishBadges()
        }
        timer?.fire()
    }

    public static func observe(bundleId: String, appName: String, onUpdate: @escaping (String?) -> Void) {
        tracker.observe(bundleId: bundleId, appName: appName, onBadgeUpdate: onUpdate)
    }

    public static func unObserve(bundleId: String) {
        print("Un observe \(bundleId)")
        tracker.unObserve(bundleId: bundleId)
    }

    public static func toggleMonitoredApp(bundleId: String) {
        let instances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        if let activeInstance = instances.first(where: \.isActive) {
            activeInstance.hide()
        } else {
            showMonitoredApp(bundleId: bundleId)
        }
    }

    public static func showMonitoredApp(bundleId: String) {
        // Launch Services can start a second instance from another path, so prefer the running copy.
        let runningURL = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first?.bundleURL
        guard let url = runningURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return
        }
        // Unlike activate(), an open sends the reopen event of a Dock click, so an app with no window shows one.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    public static func isMonitoredAppRunning(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    public static func hasDockElement(bundleId: String) -> Bool {
        tracker.element(for: bundleId) != nil
    }

    private static func setupAxObserversOnDock() {
        [appCreateObserver, appDestroyObserver].compactMap { $0 }.forEach { observer in
            CFRunLoopRemoveSource(RunLoop.current.getCFRunLoop(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }

        observedDockProcessId = AXDock.processId
        guard let dockProcessId = observedDockProcessId else {
            appCreateObserver = nil
            appDestroyObserver = nil
            return
        }

        appCreateObserver = makeObserver(dockProcessId: dockProcessId, notification: kAXCreatedNotification, callback: onElementCreateCallback)
        appDestroyObserver = makeObserver(dockProcessId: dockProcessId, notification: kAXUIElementDestroyedNotification, callback: onElementDestroyCallback)

        observerStatus.send(appCreateObserver != nil)
        if appCreateObserver != nil && appDestroyObserver != nil {
            resolveAllElements()
        }
    }

    private static func resolveAllElements() {
        tracker.resolveAllElements()
        ticksSinceFullResolve = 0
    }

    private static func makeObserver(dockProcessId: pid_t, notification: String, callback: ObserverCallbackInfo) -> AXObserver? {
        var observer: AXObserver?
        AXObserverCreateWithInfoCallback(dockProcessId, { _, _, _, _, refCon in
            if let refCon {
                Unmanaged<ObserverCallbackInfo>.fromOpaque(refCon).takeUnretainedValue().callback()
            }
        }, &observer)

        guard let observer else {
            return nil
        }

        let callbackPointer = Unmanaged.passUnretained(callback).toOpaque()
        guard AXObserverAddNotification(observer, AXUIElementCreateApplication(dockProcessId), notification as CFString, callbackPointer) == .success else {
            return nil
        }

        CFRunLoopAddSource(RunLoop.current.getCFRunLoop(), AXObserverGetRunLoopSource(observer), .defaultMode)
        return observer
    }
}

private class ObserverCallbackInfo {
    var callback: () -> Void

    init(callback: @escaping () -> Void) {
        self.callback = callback
    }
}
