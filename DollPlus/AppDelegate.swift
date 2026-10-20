import SwiftUI

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        Storage.setup()
        let importedFromDoll = DollImport.importOnFirstLaunch()
        MonitorEngine.shared.setup()
        HotkeyManager.setup()
        DebugStateWriter.setup()

       if AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) {
           print("Trusted by client")
       } else if importedFromDoll {
           // The Accessibility permission of Doll does not apply to Doll Plus. The config window shows a banner for it.
           MonitorEngine.shared.showConfigWindow()
       }
    }

    private var isFirstActivation = true

    // Upstream: Doll 4. A launch from Finder or Spotlight activates Doll Plus. A launch at login does not.
    func applicationWillBecomeActive(_ notification: Notification) {
        guard isFirstActivation else {
            return
        }
        isFirstActivation = false
        MonitorEngine.shared.showConfigWindow()
    }

    // A second launch from Spotlight or Finder.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MonitorEngine.shared.showConfigWindow()
        return false
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
}
