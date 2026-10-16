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
