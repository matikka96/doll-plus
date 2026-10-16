import AppKit

let dockBundleId = "com.apple.dock"

struct AXDock: Dock {
    static var processId: pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: dockBundleId).last?.processIdentifier
    }

    func items() -> [DockItem<AXUIElement>] {
        guard let dockProcessId = AXDock.processId,
              let dockChildren = subElements(of: AXUIElementCreateApplication(dockProcessId)) else {
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

    func statusLabel(of element: AXUIElement) throws -> String? {
        var value: AnyObject?
        switch AXUIElementCopyAttributeValue(element, "AXStatusLabel" as CFString, &value) {
        case .success:
            return value as? String
        case .invalidUIElement, .cannotComplete:
            throw StaleDockElement()
        default:
            return nil
        }
    }

    private func attribute(_ name: String, of element: AXUIElement) -> AnyObject? {
        var value: AnyObject?
        AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return value
    }

    private func subElements(of root: AXUIElement) -> [AXUIElement]? {
        var children: AnyObject?
        guard AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &children) == .success,
              let children = children as? [AXUIElement] else {
            return nil
        }

        return children + children.flatMap { subElements(of: $0) ?? [] }
    }
}
