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

struct Row {
    let element: AXUIElement
    let content: AXUIElement
    let name: String
}

func rows(in window: AXUIElement) -> [Row] {
    descendants(of: window)
        .filter { subrole($0) == "AXOutlineRow" }
        .compactMap { row in
            guard let content = descendants(of: row).first(where: { label($0) != nil }), let name = label(content) else {
                return nil
            }
            return Row(element: row, content: content, name: name)
        }
}

func row(named name: String, in window: AXUIElement) -> Row {
    waitFor("the row \(name)") { rows(in: window).first { $0.name == name } }
}

func isSelected(_ row: Row) -> Bool {
    attribute(row.element, kAXSelectedAttribute) as? Bool ?? false
}

func press(_ element: AXUIElement) {
    let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
    if result != .success {
        fail("AXPress failed with \(result.rawValue)")
    }
}

let usage = "usage: config-driver PID rows | buttons | open NAME | toggle LABEL | remove NAME"
let arguments = CommandLine.arguments
guard arguments.count >= 3, let pid = pid_t(arguments[1]) else {
    fail(usage)
}
let app = AXUIElementCreateApplication(pid)

func configWindow() -> AXUIElement? {
    children(of: app).first { subrole($0) == "AXStandardWindow" }
}

// Each activation of Doll Plus rebuilds the content of the config window: the row selection and the detail pane go away.
let window = configWindow() ?? {
    AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    return waitFor("the config window", configWindow)
}()

switch (arguments[2], arguments.count > 3 ? arguments[3] : nil) {
case ("rows", nil):
    printJSON(rows(in: window).map { ["name": $0.name, "selected": isSelected($0)] })
case ("buttons", nil):
    printJSON(descendants(of: window).filter { role($0) == kAXButtonRole }.compactMap(label))
case ("open", let name?):
    // A press while the window still loads can have no effect.
    waitFor("the selected row \(name)") { () -> Bool in
        let target = row(named: name, in: window)
        if isSelected(target) {
            return true
        }
        AXUIElementPerformAction(target.content, kAXPressAction as CFString)
        return poll(timeout: 0.5) { isSelected(row(named: name, in: window)) }
    }
    printJSON(["ok": true])
case ("toggle", let checkboxLabel?):
    let checkbox = { descendants(of: window).first { role($0) == kAXCheckBoxRole && label($0) == checkboxLabel } }
    let value = { checkbox().flatMap { attribute($0, kAXValueAttribute) as? Int } }
    let before = waitFor("the checkbox \(checkboxLabel)", value)
    press(waitFor("the checkbox \(checkboxLabel)", checkbox))
    waitFor("a new value of the checkbox \(checkboxLabel)") { value().map { $0 != before } ?? false }
    printJSON(["ok": true])
case ("remove", let name?):
    let target = row(named: name, in: window)
    guard let menuOwner = ([target.content, target.element] + descendants(of: target.element))
        .first(where: { actions(of: $0).contains(kAXShowMenuAction) }) else {
        fail("the row \(name) has no context menu")
    }
    // NSMenu tracking delays the reply to AXShowMenu until the menu closes.
    AXUIElementSetMessagingTimeout(menuOwner, 0.5)
    AXUIElementPerformAction(menuOwner, kAXShowMenuAction as CFString)
    let item = waitFor("the Remove menu item") {
        descendants(of: app).first { role($0) == kAXMenuItemRole && label($0) == "Remove" }
    }
    press(item)
    printJSON(["ok": true])
default:
    fail(usage)
}
