struct DockItem<Element> {
    let element: Element
    let title: String?
    let bundleId: String?
}

enum DockItemMatcher {
    static func element<Element>(in items: [DockItem<Element>], bundleId: String, appName: String) -> Element? {
        if let item = items.first(where: { $0.bundleId == bundleId }) {
            return item.element
        }

        return items.first { $0.bundleId == nil && $0.title == appName }?.element
    }
}
