import Cocoa
import Combine

public struct AppInfo {
    public var bundleId: String
    public var fullPath: String
    public var localizedName: String
    public var icon: NSImage?

    public static func displayName(ofAppAt url: URL) -> String {
        let name = (try? url.resourceValues(forKeys: [.localizedNameKey]))?.localizedName ?? url.lastPathComponent
        let appExtension = ".app"
        return name.hasSuffix(appExtension) ? String(name.dropLast(appExtension.count)) : name
    }
}

public class AppListService {
    var query = NSMetadataQuery()
    // By default the query gathers on the main thread. The icons of all apps then delay the drawing of the add sheet.
    private let queryQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    // The query starts later, on its queue, so isStarted can still be false on the next call.
    private var isSetUp = false

    @Published public var listOfInstalledApplication: [AppInfo] = []

    public static var shared = AppListService()

    // Spotlight does not list an app outside an indexed folder, or any app when indexing is off.
    public static var runningApplications: [AppInfo] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let bundleId = app.bundleIdentifier, let url = app.bundleURL else {
                return nil
            }
            return AppInfo(bundleId: bundleId, fullPath: url.path, localizedName: AppInfo.displayName(ofAppAt: url), icon: app.icon)
        }
    }

    public func setup() {
        if !isSetUp {
            isSetUp = true
            let predicate = NSPredicate(format: "kMDItemContentType == 'com.apple.application-bundle'")
            NotificationCenter.default.addObserver(self, selector: #selector(queryDidFinish(_:)), name: NSNotification.Name.NSMetadataQueryDidFinishGathering, object: query)
            query.predicate = predicate
            query.operationQueue = queryQueue
            queryQueue.addOperation { [query] in
                query.start()
            }
        }
    }

    @objc private func queryDidFinish(_ notification: NSNotification) {
        guard let query = notification.object as? NSMetadataQuery else {
            return
        }

        var appListDict: [String: AppInfo] = [:]
        appListDict.reserveCapacity(query.resultCount)

        for result in query.results {
            guard let item = result as? NSMetadataItem else {
                print("Result was not an NSMetadataItem, \(result)")
                continue
            }

            let bundleIdentifier = item.value(forAttribute: kMDItemCFBundleIdentifier as String) as? String
            let fullPath = item.value(forAttribute: kMDItemPath as String) as? String
            let icon = NSWorkspace.shared.icon(forFile: fullPath ?? "")

            if let id = bundleIdentifier, let path = fullPath {
                appListDict[id] = AppInfo(bundleId: id,
                        fullPath: path,
                        localizedName: AppInfo.displayName(ofAppAt: URL(fileURLWithPath: path)),
                        icon: icon)
            }
        }

        let apps = appListDict.map {
            $0.value
        }
        DispatchQueue.main.async {
            self.listOfInstalledApplication = apps
        }

        query.stop()
    }
}
