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

    @Published public var listOfInstalledApplication: [AppInfo] = []

    public static var shared = AppListService()

    public func setup() {
        if !query.isStarted {
            let predicate = NSPredicate(format: "kMDItemContentType == 'com.apple.application-bundle'")
            NotificationCenter.default.addObserver(self, selector: #selector(queryDidFinish(_:)), name: NSNotification.Name.NSMetadataQueryDidFinishGathering, object: query)
            query.predicate = predicate
            query.start()
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

        listOfInstalledApplication = appListDict.map {
            $0.value
        }

        query.stop()
    }
}
