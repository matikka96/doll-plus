import AppKit
import ApplicationServices

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

func actions(of element: AXUIElement) -> [String] {
    var names: CFArray?
    AXUIElementCopyActionNames(element, &names)
    return names as? [String] ?? []
}

func role(_ element: AXUIElement) -> String? {
    attribute(element, kAXRoleAttribute) as? String
}

func subrole(_ element: AXUIElement) -> String? {
    attribute(element, kAXSubroleAttribute) as? String
}

func label(_ element: AXUIElement) -> String? {
    attribute(element, kAXDescriptionAttribute) as? String ?? attribute(element, kAXTitleAttribute) as? String
}

func printJSON(_ object: Any) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    print(String(data: data, encoding: .utf8)!)
}

func fail(_ message: String) -> Never {
    printJSON(["error": message])
    exit(1)
}

func poll<T>(timeout: TimeInterval, _ find: () -> T?) -> T? {
    let deadline = Date().addingTimeInterval(timeout)
    while true {
        if let found = find() {
            return found
        }
        if Date() > deadline {
            return nil
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
}

@discardableResult
func waitFor<T>(_ what: String, timeout: TimeInterval = 5, _ find: () -> T?) -> T {
    guard let found = poll(timeout: timeout, find) else {
        fail("\(what) not found")
    }
    return found
}

func poll(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
    poll(timeout: timeout) { condition() ? true : nil } ?? false
}

func waitFor(_ what: String, timeout: TimeInterval = 5, _ condition: () -> Bool) {
    waitFor(what, timeout: timeout) { condition() ? true : nil }
}

func identifier(_ element: AXUIElement) -> String? {
    attribute(element, "AXIdentifier") as? String
}

func element(_ id: String, in root: AXUIElement) -> AXUIElement? {
    descendants(of: root).first { identifier($0) == id }
}

func isEnabled(_ element: AXUIElement) -> Bool {
    attribute(element, kAXEnabledAttribute) as? Bool ?? true
}

let monitoredAppName = "monitoredAppName"
let installedAppName = "installedAppName"

struct Row {
    let element: AXUIElement
    let name: String
}

func rows(in root: AXUIElement, nameId: String = monitoredAppName) -> [Row] {
    descendants(of: root)
        .filter { subrole($0) == "AXOutlineRow" }
        .compactMap { row in
            guard let nameText = descendants(of: row).first(where: { identifier($0) == nameId }),
                  let name = attribute(nameText, kAXValueAttribute) as? String else {
                return nil
            }
            return Row(element: row, name: name)
        }
}

func row(named name: String, in root: AXUIElement, nameId: String = monitoredAppName) -> Row {
    waitFor("the row \(name)") { rows(in: root, nameId: nameId).first { $0.name == name } }
}

func isSelected(_ row: Row) -> Bool {
    attribute(row.element, kAXSelectedAttribute) as? Bool ?? false
}

// A selection while the window still loads can have no effect.
func select(_ name: String, in root: AXUIElement, nameId: String = monitoredAppName) -> Row {
    waitFor("the selected row \(name)") { () -> Row? in
        let target = row(named: name, in: root, nameId: nameId)
        if !isSelected(target) {
            AXUIElementSetAttributeValue(target.element, kAXSelectedAttribute as CFString, kCFBooleanTrue)
        }
        return poll(timeout: 0.5) { isSelected(row(named: name, in: root, nameId: nameId)) } ? target : nil
    }
}

func press(_ element: AXUIElement) {
    let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
    if result != .success {
        fail("AXPress failed with \(result.rawValue)")
    }
}

func press(_ id: String, in root: AXUIElement) {
    let target = waitFor("the control \(id)") { element(id, in: root) }
    waitFor("the enabled control \(id)") { isEnabled(target) }
    press(target)
}

func sheet(of window: AXUIElement) -> AXUIElement? {
    children(of: window).first { role($0) == "AXSheet" }
}

func texts(in element: AXUIElement) -> [String] {
    descendants(of: element).filter { role($0) == kAXStaticTextRole }.compactMap { attribute($0, kAXValueAttribute) as? String }
}

let usage = """
usage: config-driver PID rows | texts | select NAME | open NAME | sheet | toggle ID | pick ID LABEL | press ID | enabled ID
       | remove NAME | add NAME | frame | frame-of ID | show | move DX DY | close | activate
"""
let arguments = CommandLine.arguments
guard arguments.count >= 3, let pid = pid_t(arguments[1]) else {
    fail(usage)
}
let app = AXUIElementCreateApplication(pid)

func configWindow() -> AXUIElement? {
    children(of: app).first { subrole($0) == "AXStandardWindow" }
}

func frame(of element: AXUIElement) -> CGRect? {
    var origin = CGPoint.zero
    var size = CGSize.zero
    guard let positionValue = attribute(element, kAXPositionAttribute), let sizeValue = attribute(element, kAXSizeAttribute),
          AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin), AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
        return nil
    }
    return CGRect(origin: origin, size: size)
}

func frameJSON(_ frame: CGRect?) -> Any {
    frame.map { [$0.origin.x, $0.origin.y, $0.width, $0.height] } ?? NSNull()
}

// A second open sends a reopen event, and the reopen shows the config window.
func showConfigWindow() -> AXUIElement {
    if let window = configWindow() {
        return window
    }
    guard let bundle = NSRunningApplication(processIdentifier: pid)?.bundleURL else {
        fail("no app bundle for the PID \(pid)")
    }
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = [bundle.path]
    try! open.run()
    open.waitUntilExit()
    return waitFor("the config window", configWindow)
}

switch (arguments[2], arguments.count > 3 ? arguments[3] : nil) {
case ("rows", nil):
    printJSON(rows(in: showConfigWindow()).map { ["name": $0.name, "selected": isSelected($0)] })
case ("texts", nil):
    printJSON(["texts": texts(in: showConfigWindow())])
case ("frame", nil):
    printJSON(["frame": frameJSON(configWindow().flatMap(frame(of:)))])
case ("frame-of", let id?):
    let target = waitFor("the control \(id)") { element(id, in: showConfigWindow()) }
    printJSON(["frame": frameJSON(frame(of: target))])
case ("show", nil):
    printJSON(["frame": frameJSON(frame(of: showConfigWindow()))])
case ("move", _?):
    guard arguments.count == 5, let dx = Double(arguments[3]), let dy = Double(arguments[4]) else {
        fail(usage)
    }
    let window = showConfigWindow()
    let start = waitFor("the frame of the config window") { frame(of: window)?.origin }
    var origin = CGPoint(x: start.x + dx, y: start.y + dy)
    AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &origin)!)
    waitFor("the window at \(origin)") { frame(of: window)?.origin == origin }
    printJSON(["frame": frameJSON(frame(of: window))])
case ("close", nil):
    guard let closeButton = attribute(showConfigWindow(), kAXCloseButtonAttribute) else {
        fail("the config window has no close button")
    }
    press(closeButton as! AXUIElement)
    waitFor("the closed config window") { configWindow() == nil }
    printJSON(["ok": true])
case ("activate", nil):
    AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    waitFor("the frontmost Doll Plus") { attribute(app, kAXFrontmostAttribute) as? Bool == true }
    printJSON(["ok": true])
case ("select", let name?):
    _ = select(name, in: showConfigWindow())
    printJSON(["ok": true])
case ("open", let name?):
    let window = showConfigWindow()
    let target = row(named: name, in: window)
    guard let options = descendants(of: target.element).first(where: { identifier($0) == "monitoredAppOptions" }) else {
        fail("the row \(name) has no options button")
    }
    press(options)
    waitFor("the sheet of \(name)") { sheet(of: window) }
    printJSON(["ok": true])
case ("sheet", nil):
    let sheetTexts = sheet(of: showConfigWindow()).map(texts(in:)) ?? []
    printJSON(["open": sheet(of: showConfigWindow()) != nil, "texts": sheetTexts])
case ("toggle", let id?):
    let window = showConfigWindow()
    let value = { element(id, in: window).flatMap { attribute($0, kAXValueAttribute) as? Int } }
    let before = waitFor("the switch \(id)", value)
    press(id, in: window)
    waitFor("a new value of the switch \(id)") { value().map { $0 != before } ?? false }
    printJSON(["value": value().map { $0 as Any } ?? NSNull()])
case ("pick", let id?):
    guard arguments.count == 5 else {
        fail(usage)
    }
    let segmentLabel = arguments[4]
    let window = showConfigWindow()
    let segment = {
        element(id, in: window).flatMap { picker in children(of: picker).first { label($0) == segmentLabel } }
    }
    press(waitFor("the segment \(segmentLabel) of \(id)", segment))
    waitFor("the selected segment \(segmentLabel) of \(id)") { segment().flatMap { attribute($0, kAXValueAttribute) as? Int } == 1 }
    printJSON(["ok": true])
case ("press", let id?):
    press(id, in: showConfigWindow())
    printJSON(["ok": true])
case ("enabled", let id?):
    printJSON(["enabled": isEnabled(waitFor("the control \(id)") { element(id, in: showConfigWindow()) })])
case ("remove", let name?):
    let target = select(name, in: showConfigWindow())
    // The list shows the menu for the selected rows.
    guard let list = attribute(target.element, kAXParentAttribute).map({ $0 as! AXUIElement }),
          actions(of: list).contains(kAXShowMenuAction) else {
        fail("the list of the row \(name) has no context menu")
    }
    // NSMenu tracking delays the reply to AXShowMenu until the menu closes.
    AXUIElementSetMessagingTimeout(list, 0.5)
    AXUIElementPerformAction(list, kAXShowMenuAction as CFString)
    let item = waitFor("the Remove menu item") {
        descendants(of: app).first { role($0) == kAXMenuItemRole && label($0) == "Remove" }
    }
    press(item)
    printJSON(["ok": true])
case ("add", let name?):
    let window = showConfigWindow()
    press("addApp", in: window)
    let addSheet = waitFor("the add sheet") { sheet(of: window) }
    let search = waitFor("the search field") { element("searchApps", in: addSheet) }
    AXUIElementSetAttributeValue(search, kAXValueAttribute as CFString, name as CFString)
    _ = select(name, in: addSheet, nameId: installedAppName)
    press("confirmAdd", in: addSheet)
    waitFor("the closed add sheet") { sheet(of: window) == nil }
    printJSON(["ok": true])
default:
    fail(usage)
}
