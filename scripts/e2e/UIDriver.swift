import AppKit
import ApplicationServices

// Quartz global coordinates: the origin is the top-left corner of the main display, and y grows down.

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return value
}

func children(of element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

func descendants(of element: AXUIElement) -> [AXUIElement] {
    let direct = children(of: element)
    return direct + direct.flatMap(descendants(of:))
}

func printJSON(_ object: Any) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    print(String(data: data, encoding: .utf8)!)
}

func fail(_ message: String) -> Never {
    printJSON(["error": message])
    exit(1)
}

func json(_ rect: CGRect) -> [String: Double] {
    ["x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height]
}

func windowList() -> [[String: Any]] {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    return windows.compactMap { info in
        guard let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsInfo) else {
            return nil
        }
        return [
            "pid": info[kCGWindowOwnerPID as String] as? Int ?? 0,
            "owner": info[kCGWindowOwnerName as String] as? String ?? NSNull(),
            "layer": info[kCGWindowLayer as String] as? Int ?? 0,
            "alpha": info[kCGWindowAlpha as String] as? Double ?? 1,
            "bounds": json(bounds),
        ]
    }
}

func screens() -> [[String: Double]] {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetActiveDisplayList(count, &displays, &count)
    return displays.map { json(CGDisplayBounds($0)) }
}

let keyInterval: TimeInterval = 0.03

func post(_ event: CGEvent?) {
    event?.post(tap: .cghidEventTap)
}

func movePointer(to point: CGPoint) {
    post(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left))
}

func click(at point: CGPoint) {
    movePointer(to: point)
    Thread.sleep(forTimeInterval: 0.1)
    post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left))
    Thread.sleep(forTimeInterval: 0.05)
    post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left))
}

func typeText(_ text: String) {
    for character in text {
        let units = Array(String(character).utf16)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: keyDown)
            event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            post(event)
        }
        Thread.sleep(forTimeInterval: keyInterval)
    }
}

func mainWindow(of pid: pid_t) -> AXUIElement {
    let app = AXUIElementCreateApplication(pid)
    let main = attribute(app, kAXMainWindowAttribute).flatMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
    guard let window = main ?? (attribute(app, kAXWindowsAttribute) as? [AXUIElement])?.first else {
        fail("the app \(pid) has no window")
    }
    return window
}

func windowState(_ window: AXUIElement) -> [String: Any] {
    var position = CGPoint.zero
    var size = CGSize.zero
    if let value = attribute(window, kAXPositionAttribute) {
        AXValueGetValue(value as! AXValue, .cgPoint, &position)
    }
    if let value = attribute(window, kAXSizeAttribute) {
        AXValueGetValue(value as! AXValue, .cgSize, &size)
    }
    return [
        "fullScreen": attribute(window, "AXFullScreen") as? Bool ?? false,
        "bounds": json(CGRect(origin: position, size: size)),
    ]
}

func setAttribute(_ window: AXUIElement, _ name: String, _ value: AnyObject) {
    let result = AXUIElementSetAttributeValue(window, name as CFString, value)
    if result != .success {
        fail("the set of \(name) failed with \(result.rawValue)")
    }
}

func staticTexts(at point: CGPoint) -> [String] {
    var element: AXUIElement?
    guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &element) == .success,
          var top = element else {
        return []
    }
    while let parent = attribute(top, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID(),
          attribute(parent as! AXUIElement, kAXRoleAttribute) as? String != kAXApplicationRole {
        top = parent as! AXUIElement
    }
    return ([top] + descendants(of: top))
        .filter { attribute($0, kAXRoleAttribute) as? String == kAXStaticTextRole }
        .compactMap { attribute($0, kAXValueAttribute) as? String }
}

let usage = """
    usage: ui-driver windows | screens | move X Y | click X Y | type TEXT | texts-at X Y
                     | window PID | fullscreen PID on|off | place PID X Y WIDTH HEIGHT
    """
let arguments = Array(CommandLine.arguments.dropFirst())
guard AXIsProcessTrusted() else {
    fail("this process has no Accessibility permission")
}

func number(_ index: Int) -> Double {
    guard index < arguments.count, let value = Double(arguments[index]) else {
        fail(usage)
    }
    return value
}

func point(at index: Int) -> CGPoint {
    CGPoint(x: number(index), y: number(index + 1))
}

func pid(at index: Int) -> pid_t {
    pid_t(number(index))
}

switch arguments.first {
case "windows":
    printJSON(windowList())
case "screens":
    printJSON(screens())
case "move":
    movePointer(to: point(at: 1))
    printJSON(["ok": true])
case "click":
    click(at: point(at: 1))
    printJSON(["ok": true])
case "type" where arguments.count == 2:
    typeText(arguments[1])
    printJSON(["ok": true])
case "texts-at":
    printJSON(staticTexts(at: point(at: 1)))
case "window":
    printJSON(windowState(mainWindow(of: pid(at: 1))))
case "fullscreen" where arguments.count == 3 && ["on", "off"].contains(arguments[2]):
    setAttribute(mainWindow(of: pid(at: 1)), "AXFullScreen", (arguments[2] == "on" ? kCFBooleanTrue : kCFBooleanFalse)!)
    printJSON(["ok": true])
case "place":
    let window = mainWindow(of: pid(at: 1))
    var origin = point(at: 2)
    var size = CGSize(width: number(4), height: number(5))
    setAttribute(window, kAXPositionAttribute, AXValueCreate(.cgPoint, &origin)!)
    setAttribute(window, kAXSizeAttribute, AXValueCreate(.cgSize, &size)!)
    printJSON(windowState(window))
default:
    fail(usage)
}
