import AppKit
import Combine

let checkInterval: TimeInterval = 1.0

public struct MonitorService {
    public static let observerStatus = PassthroughSubject<Bool, Never>()
    private static var observedAppInfos: [String: ObservedAppInfo] = [:]
    private static var timer: Timer?
    private static var allObserversConfigured = false
    private static var appCreateObserver: AXObserver!
    private static var appDestroyObserver: AXObserver!
    private static let onElementCreateCallback = ObserverCallbackInfo {
        reloadAppElements()
    }
    private static let onElementDestroyCallback = ObserverCallbackInfo {
        observedAppInfos.keys.forEach { bundleId in
            if let appElement = observedAppInfos[bundleId]?.appElement {
                // The Dock element of an app that quit has no title.
                if attribute(kAXTitleAttribute, of: appElement) as? String == nil {
                    observedAppInfos[bundleId]?.onBadgeUpdate(nil)
                    observedAppInfos[bundleId]?.updateAppElement(nil)
                }
            }
        }
    }

    public static func setupObservers() {
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { timer in
            if appCreateObserver == nil || appDestroyObserver == nil {
                setupAxObserversOnDock()
            }

            observedAppInfos.keys.forEach { bundleId in
                observedAppInfos[bundleId]?.onBadgeUpdate(getBadgeText(bundleId: bundleId))
            }
        }
        timer?.fire()
    }

    public static func observe(bundleId: String, appName: String, onUpdate: @escaping (String?) -> Void) {
        let appElement = DockItemMatcher.element(in: dockItems(), bundleId: bundleId, appName: appName)
        observedAppInfos[bundleId] = ObservedAppInfo(appName: appName, appElement: appElement, onBadgeUpdate: onUpdate)
    }

    public static func unObserve(bundleId: String) {
        print("Un observe \(bundleId)")
        observedAppInfos.removeValue(forKey: bundleId)
    }

    public static func openMonitoredApp(bundleId: String) {
        if let cachedTargetAppElement = observedAppInfos[bundleId]?.appElement {
            AXUIElementPerformAction(cachedTargetAppElement, kAXPressAction as CFString)
        }
    }

    public static func isMonitoredAppRunning(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    public static func hasDockElement(bundleId: String) -> Bool {
        observedAppInfos[bundleId]?.appElement != nil
    }

    public static func getBadgeText(bundleId: String) -> String? {
        guard let targetAppElement = observedAppInfos[bundleId]?.appElement else {
            return nil
        }

        return attribute("AXStatusLabel", of: targetAppElement) as? String
    }

    private static func dockItems() -> [DockItem<AXUIElement>] {
        guard let dockProcessId = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").last?.processIdentifier,
              let dockChildren = getSubElements(root: AXUIElementCreateApplication(dockProcessId)) else {
            return []
        }

        let appItems = dockChildren.filter { attribute(kAXSubroleAttribute, of: $0) as? String == "AXApplicationDockItem" }
        return appItems.map { child in
            let url = attribute(kAXURLAttribute, of: child) as? URL
            return DockItem(element: child,
                            title: attribute(kAXTitleAttribute, of: child) as? String,
                            bundleId: url.flatMap { Bundle(url: $0)?.bundleIdentifier })
        }
    }

    private static func attribute(_ name: String, of element: AXUIElement) -> AnyObject? {
        var value: AnyObject?
        AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return value
    }

    private static func getSubElements(root: AXUIElement) -> [AXUIElement]? {
        var childrenCount: CFIndex = 0
        var err = AXUIElementGetAttributeValueCount(root, "AXChildren" as CFString, &childrenCount)
        var result: [AXUIElement] = []

        if case .success = err {
            var subElements: CFArray?;
            err = AXUIElementCopyAttributeValues(root, "AXChildren" as CFString, 0, childrenCount, &subElements)
            if case .success = err {
                if let children = subElements as? [AXUIElement] {
                    result.append(contentsOf: children)
                    children.forEach { element in
                        if let nestedChildren = getSubElements(root: element) {
                            result.append(contentsOf: nestedChildren)
                        }
                    }
                }

                return result
            }
        }

        print("Error \(err.rawValue)")
        return nil
    }

    private static func setupAxObserversOnDock() {
        guard let dockProcessId = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").last?.processIdentifier else {
            return
        }

        AXObserverCreateWithInfoCallback(dockProcessId, { (observer, element, notification, userData, refCon) in
            if let refCon = refCon {
                let callbackInfo = Unmanaged<ObserverCallbackInfo>.fromOpaque(refCon).takeUnretainedValue()
                callbackInfo.callback()
            }
        }, &appCreateObserver)

        AXObserverCreateWithInfoCallback(dockProcessId, { (observer, element, notification, userData, refCon) in
            if let refCon = refCon {
                let callbackInfo = Unmanaged<ObserverCallbackInfo>.fromOpaque(refCon).takeUnretainedValue()
                callbackInfo.callback()
            }
        }, &appDestroyObserver)

        if let observer = appCreateObserver {
            let callbackPTR = UnsafeMutableRawPointer(Unmanaged.passUnretained(onElementCreateCallback).toOpaque())

            if AXObserverAddNotification(observer, AXUIElementCreateApplication(dockProcessId), kAXCreatedNotification as CFString, callbackPTR) == .success {
                print("Successfully added element created Notification!")
            } else {
                appCreateObserver = nil
            }

            CFRunLoopAddSource(RunLoop.current.getCFRunLoop(), AXObserverGetRunLoopSource(observer), CFRunLoopMode.defaultMode)
        }

        if let observer = appDestroyObserver {
            let callbackPTR = UnsafeMutableRawPointer(Unmanaged.passUnretained(onElementDestroyCallback).toOpaque())

            if AXObserverAddNotification(observer, AXUIElementCreateApplication(dockProcessId), kAXUIElementDestroyedNotification as CFString, callbackPTR) == .success {
                print("Successfully added element destroyed Notification!")
            } else {
                appDestroyObserver = nil
            }

            CFRunLoopAddSource(RunLoop.current.getCFRunLoop(), AXObserverGetRunLoopSource(observer), CFRunLoopMode.defaultMode)
        }

        observerStatus.send(appCreateObserver != nil)
        if appCreateObserver != nil && appDestroyObserver != nil {
            reloadAppElements()
        }
    }

    private static func reloadAppElements() {
        let missingBundleIds = observedAppInfos.filter { $0.value.appElement == nil }.keys
        guard !missingBundleIds.isEmpty else {
            return
        }

        let items = dockItems()
        missingBundleIds.forEach { bundleId in
            guard let appName = observedAppInfos[bundleId]?.appName else {
                return
            }
            observedAppInfos[bundleId]?.updateAppElement(DockItemMatcher.element(in: items, bundleId: bundleId, appName: appName))
        }
    }
}

private struct ObservedAppInfo {
    let appName: String
    var appElement: AXUIElement?
    let onBadgeUpdate: (String?) -> Void

    mutating func updateAppElement(_ element: AXUIElement?) {
        appElement = element
    }
}

private class ObserverCallbackInfo {
    var callback: () -> Void

    init(callback: @escaping () -> Void) {
        self.callback = callback
    }
}
