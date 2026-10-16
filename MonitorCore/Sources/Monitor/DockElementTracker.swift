struct StaleDockElement: Error {}

protocol Dock {
    associatedtype Element

    func items() -> [DockItem<Element>]
    func statusLabel(of element: Element) throws -> String?
}

final class DockElementTracker<D: Dock> {
    private struct ObservedApp {
        let appName: String
        var element: D.Element?
        let onBadgeUpdate: (String?) -> Void
    }

    private let dock: D
    private var observedApps: [String: ObservedApp] = [:]

    init(dock: D) {
        self.dock = dock
    }

    func observe(bundleId: String, appName: String, onBadgeUpdate: @escaping (String?) -> Void) {
        observedApps[bundleId] = ObservedApp(appName: appName, element: nil, onBadgeUpdate: onBadgeUpdate)
        resolveElements(for: [bundleId])
    }

    func unObserve(bundleId: String) {
        observedApps.removeValue(forKey: bundleId)
    }

    func element(for bundleId: String) -> D.Element? {
        observedApps[bundleId]?.element
    }

    func resolveMissingElements() {
        resolveElements(for: observedApps.filter { $0.value.element == nil }.map(\.key))
    }

    func resolveAllElements() {
        resolveElements(for: Array(observedApps.keys))
    }

    func resolveElements(for bundleIds: [String]) {
        let observedBundleIds = bundleIds.filter { observedApps[$0] != nil }
        // The Dock always shows Finder, so no app items means that the Dock is not ready.
        let items = observedBundleIds.isEmpty ? [] : dock.items()
        guard !items.isEmpty else {
            return
        }

        for bundleId in observedBundleIds {
            if let appName = observedApps[bundleId]?.appName {
                observedApps[bundleId]?.element = DockItemMatcher.element(in: items, bundleId: bundleId, appName: appName)
            }
        }
    }

    func publishBadges() {
        var badges: [String: String] = [:]
        var staleBundleIds: [String] = []
        for (bundleId, app) in observedApps {
            guard let element = app.element else {
                continue
            }
            do {
                badges[bundleId] = try dock.statusLabel(of: element)
            } catch {
                staleBundleIds.append(bundleId)
            }
        }

        resolveElements(for: staleBundleIds)
        for bundleId in staleBundleIds {
            badges[bundleId] = observedApps[bundleId]?.element.flatMap { try? dock.statusLabel(of: $0) }
        }

        for (bundleId, app) in observedApps {
            app.onBadgeUpdate(badges[bundleId])
        }
    }
}
