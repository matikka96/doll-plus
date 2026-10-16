import AppKit
import ApplicationServices

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return value
}

func descendants(of element: AXUIElement) -> [AXUIElement] {
    guard let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else {
        return []
    }
    return children + children.flatMap(descendants(of:))
}

func printJSON(_ object: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    print(String(data: data, encoding: .utf8)!)
}

let shouldPrompt = CommandLine.arguments.contains("--prompt")
let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
guard AXIsProcessTrustedWithOptions([promptKey: shouldPrompt] as CFDictionary) else {
    printJSON(["trusted": false])
    exit(2)
}

func argument(after flag: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: flag), index + 1 < CommandLine.arguments.count else {
        return nil
    }
    return CommandLine.arguments[index + 1]
}

if let pid = argument(after: "--press-status-item").flatMap(pid_t.init) {
    let extrasMenuBar = attribute(AXUIElementCreateApplication(pid), "AXExtrasMenuBar")
        .flatMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
    guard let item = extrasMenuBar.flatMap({ attribute($0, kAXChildrenAttribute) as? [AXUIElement] })?.first else {
        printJSON(["trusted": true, "pressed": false])
        exit(4)
    }
    let result = AXUIElementPerformAction(item, kAXPressAction as CFString)
    printJSON(["trusted": true, "pressed": result == .success])
    exit(result == .success ? 0 : 5)
}

func onScreenWindowCount(pid: pid_t) -> Int {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return windows.filter { $0[kCGWindowOwnerPID as String] as? pid_t == pid }.count
}

if let bundleId = argument(after: "--app-state") {
    let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
    printJSON([
        "trusted": true,
        "running": app != nil,
        "active": app?.isActive ?? false,
        "hidden": app?.isHidden ?? false,
        "on_screen_windows": app.map { onScreenWindowCount(pid: $0.processIdentifier) } ?? 0,
    ])
    exit(0)
}

guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").last else {
    printJSON(["trusted": true, "items": []])
    exit(3)
}

let items: [[String: Any]] = descendants(of: AXUIElementCreateApplication(dock.processIdentifier))
    .filter { attribute($0, kAXRoleAttribute) as? String == "AXDockItem" }
    .map { item in
        [
            "title": attribute(item, kAXTitleAttribute) as? String ?? NSNull(),
            "subrole": attribute(item, kAXSubroleAttribute) as? String ?? NSNull(),
            "url": (attribute(item, kAXURLAttribute) as? URL)?.path ?? NSNull(),
            "statusLabel": attribute(item, "AXStatusLabel") as? String ?? NSNull(),
        ]
    }

printJSON(["trusted": true, "dockPid": dock.processIdentifier, "items": items])
