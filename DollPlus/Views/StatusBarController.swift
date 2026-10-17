import AppKit
import Monitor
import SwiftUI
import Utils

let defaultIconSize: CGFloat = 20
let defaultIconFrameSize = NSSize(width: defaultIconSize, height: defaultIconSize)
let defaultIcon = #imageLiteral(resourceName: "DefaultStatusBarIcon")
private let notificationDuration: TimeInterval = 3

class StatusBarController {
    private var statusBar: NSStatusBar!
    private var isDark = false
    private(set) var latestBadgeText = ""
    private(set) var redrawCount = 0
    private(set) var redBadgeLabel: String?
    private var latestMessageCount = 0
    private var drawnState: DrawnState?

    private var giantBadgeController = GiantBadgeViewController()
    private var giantBadgePanel = NSPanel(contentRect: NSRect(origin: .zero, size: defaultWindowSize),
                              styleMask: [.nonactivatingPanel],
                              backing: .buffered, defer: false)
    private var lastTimeShowingGiantBadge = Date()
    private var notificationPanel: NSPanel?
    private var notificationHideWork: DispatchWorkItem?

    public var statusItem: NSStatusItem!
    public var monitoredApp: MonitoredApp? {
        didSet {
            refreshIcon()
        }
    }
    private var monitoredAppIcon: NSImage?
    private var position: StatusItemPosition? {
        monitoredApp.map { StatusItemPosition(bundleId: $0.bundleId) }
    }

    init() {
        setupStatusBar()
    }

    func setupStatusBar(icon: NSImage? = nil) {
        statusBar = .system
        statusItem = statusBar.statusItem(withLength: defaultIconSize)
        if let statusBarButton = statusItem.button {
            statusBarButton.sendAction(on: [.leftMouseUp, .rightMouseUp])
            statusBarButton.image = icon ?? defaultIcon
            statusBarButton.image?.size = defaultIconFrameSize
            statusBarButton.image?.isTemplate = false
            statusBarButton.imagePosition = .imageLeft
            statusBarButton.action = #selector(onIconClicked(sender:))
            statusBarButton.target = self
            statusBarButton.toolTip = NSLocalizedString("Hold option key ⌥ and click to config", comment: "")
        }

        giantBadgePanel.isOpaque = false
        giantBadgePanel.hasShadow = false
        giantBadgePanel.backgroundColor = NSColor.clear
        // The giant badge panel covers the status item, so the tooltip misses the mouse-exit event.
        giantBadgePanel.ignoresMouseEvents = true
    }

    func refreshIcon() {
        monitoredAppIcon = Storage.appIcon(for: monitoredApp?.bundleId ?? "")

        if(AppSettings.isIconMask(for: monitoredApp?.bundleId ?? "") && isDark) {
            monitoredAppIcon = monitoredAppIcon?.invert()
        }

        updateBadgeText(latestBadgeText, force: true)
    }

    @objc func onIconClicked(sender: AnyObject) {
        hideGiantBadge()
        hideNotificationPanel()

        let noAppSelected = statusItem.button?.image == defaultIcon
        let isOptionKeyHolding = NSEvent.modifierFlags.contains(.option)
        let isRightClick = NSApp.currentEvent?.isRightClick == true
        let monitoredAppURL = monitoredApp.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleId) }

        if noAppSelected || monitoredAppURL == nil || isOptionKeyHolding || isRightClick {
            MonitorEngine.shared.showConfigWindow()
        } else if let monitoredAppBundleId = monitoredApp?.bundleId {
            MonitorService.toggleMonitoredApp(bundleId: monitoredAppBundleId)
        }
    }

    func monitorApp(app: MonitoredApp) {
        if monitoredApp != app {
            position?.forget()
        }
        let newPosition = StatusItemPosition(bundleId: app.bundleId)
        // macOS reads the position when the item gets its autosave name, and can drop it for a hidden item.
        newPosition.backUp()
        newPosition.restore()
        statusItem.autosaveName = newPosition.autosaveName
        monitoredApp = app
        statusItem.button?.toolTip = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId) == nil
            ? String(format: NSLocalizedString("%@ is not installed. Click to open the settings.", comment: ""), app.appName)
            : nil
        updateBadgeText(nil)

        MonitorService.observe(bundleId: app.bundleId, appName: app.appName) { [weak self] badge in
            let appRunning = MonitorService.isMonitoredAppRunning(bundleIdentifier: app.bundleId)
            let appIsNotRunningAndIconShouldBeHidden = AppSettings.hideWhenAppNotRunning && !appRunning
            let badgeIsEmptyAndIconShouldBeHidden = AppSettings.hideWhenNothingComing && (badge.isNil || badge?.isEmpty == true)

            if appIsNotRunningAndIconShouldBeHidden || badgeIsEmptyAndIconShouldBeHidden {
                self?.hideStatusBar()
            } else {
                let currentIsDark = self?.statusItem.button?.effectiveAppearance.name.rawValue.lowercased().contains("dark") ?? false
                if(self?.isDark != currentIsDark) {
                    self?.isDark = currentIsDark
                    self?.refreshIcon()
                }

                self?.updateBadgeText(badge)
            }

            if self?.giantBadgePanel.isVisible == true {
                self?.repositionGiantBadge()
            }
        }
    }

    func hideStatusBar() {
        guard statusItem.isVisible else {
            return
        }
        position?.backUp()
        hideNotificationPanel()
        statusItem.isVisible = false
    }

    func showStatusBar() {
        guard !statusItem.isVisible else {
            return
        }
        position?.restore()
        statusItem.isVisible = true
    }

    func updateBadgeText(_ text: String?, force: Bool = false) {
        showStatusBar()

        let newText = text ?? ""
        let state = DrawnState(text: newText,
                               showOnlyAppIcon: AppSettings.showOnlyAppIcon,
                               showAsRedBadge: AppSettings.showAsRedBadge,
                               grayOutWhenEmpty: AppSettings.grayoutIconWhenNothingComing)
        guard force || state != drawnState, let monitoredAppIcon else {
            return
        }
        drawnState = state

        let showsRedBadge = state.showAsRedBadge && !state.showOnlyAppIcon
        let showsText = !state.showAsRedBadge && !state.showOnlyAppIcon && !newText.isEmpty
        redBadgeLabel = showsRedBadge ? RedBadgeLabel.text(for: newText, fits: NSImage.redBadgeFits) : nil
        let icon = redBadgeLabel.map(monitoredAppIcon.addBadgeToImage(drawText:)) ?? monitoredAppIcon
        let adjustedIcon = (newText.isEmpty && state.grayOutWhenEmpty) ? (icon.grayOut() ?? icon) : icon
        updateBadgeIcon(icon: adjustedIcon, size: showsRedBadge ? nil : defaultIconFrameSize)
        statusItem.button?.title = showsText ? newText : ""
        statusItem.length = showsText ? NSStatusItem.variableLength : defaultIconSize

        guard !state.showOnlyAppIcon else {
            latestBadgeText = newText
            return
        }

        if newText.isEmpty {
            hideGiantBadge()
            hideNotificationPanel()
        }

        let newMessageCount = Int(newText) ?? 0
        if latestBadgeText != newText {
            if AppSettings.showAlertInFullScreenMode, !newText.isEmpty {
                tryShowNotificationPanel(newText: newText)
            }

            let frontmostAppIsMonitoredApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == monitoredApp?.bundleId
            if !frontmostAppIsMonitoredApp, AppSettings.isGiantBadgeEnabled(for: monitoredApp?.bundleId ?? "") {
                if newMessageCount >= latestMessageCount {
                    tryShowGiantBadge(text)
                } else {
                    hideGiantBadge()
                }
            } else {
                hideGiantBadge()
            }
        }

        latestBadgeText = newText
        latestMessageCount = newMessageCount
    }

    func refreshDisplayMode() {
        updateBadgeText(latestBadgeText, force: true)
    }

    func updateBadgeIcon(icon: NSImage?, size: CGSize? = nil) {
        redrawCount += 1
        statusItem.button?.image = icon
        if let iconSize = size ?? icon?.size {
            statusItem.button?.image?.size = iconSize
        }
    }

    func tryShowGiantBadge(_ text: String?) {
        let now = Date()
        if !giantBadgePanel.isVisible || now.timeIntervalSince(lastTimeShowingGiantBadge) >= 3 {
            lastTimeShowingGiantBadge = now

            if giantBadgePanel.contentViewController != nil {
                giantBadgeController.animationFlag.toggle()
            } else {
                let giantBadgeView = GiantBadgeView(controller: giantBadgeController)
                giantBadgePanel.contentViewController = NSHostingController(rootView: giantBadgeView)
                giantBadgePanel.setContentSize(giantBadgeSize)
            }

            repositionGiantBadge()
            giantBadgePanel.level = .popUpMenu
            giantBadgePanel.setIsVisible(true)
            giantBadgePanel.orderFrontRegardless()
        }
    }

    func repositionGiantBadge() {
        guard let activeScreen = NSScreen.screenWithMouse,
           let iconFrame = statusItem.button?.window?.frame else {
            return
        }

        var menubarOffset: CGFloat = 0
        if Utils.currentActiveWindowIsFullScreen {
            // In mac with notch, the menubar didn't affect window's size
            menubarOffset = activeScreen.hasTopNotchDesign ? 0 : Utils.menubarHeight
        }

        giantBadgePanel.setFrameOrigin(NSPoint(x: iconFrame.midX - giantBadgeSize.width / 2, y: activeScreen.visibleFrame.maxY - giantBadgeSize.height + menubarOffset + giantBadgeYOffset))
    }

    func hideGiantBadge() {
        giantBadgePanel.setIsVisible(false)
    }

    private func tryShowNotificationPanel(newText: String) {
        guard Utils.currentActiveWindowIsFullScreen,
              let iconWindow = statusItem.button?.window,
              let screen = iconWindow.screen ?? NSScreen.screenWithMouse else {
            return
        }

        let targetApp = monitoredApp
        let view = NotificationView(icon: monitoredAppIcon ?? defaultIcon, badgeText: newText) { [weak self] in
            self?.hideNotificationPanel()
            if let bundleId = targetApp?.bundleId {
                MonitorService.showMonitoredApp(bundleId: bundleId)
            }
        }
        let hostingView = FirstMouseHostingView(rootView: view)
        let size = hostingView.fittingSize
        let panel = notificationPanel ?? makeNotificationPanel()
        notificationPanel = panel
        panel.setFrame(notificationFrame(size: size, below: iconWindow.frame, on: screen), display: false)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView?.subviews = [hostingView]
        panel.orderFrontRegardless()

        notificationHideWork?.cancel()
        let hideWork = DispatchWorkItem { [weak self] in
            self?.hideNotificationPanel()
        }
        notificationHideWork = hideWork
        DispatchQueue.main.asyncAfter(deadline: .now() + notificationDuration, execute: hideWork)
    }

    private func notificationFrame(size: NSSize, below iconFrame: NSRect, on screen: NSScreen) -> NSRect {
        let x = min(max(iconFrame.midX - size.width / 2, screen.frame.minX), screen.frame.maxX - size.width)
        let y = min(iconFrame.minY, screen.frame.maxY) - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func hideNotificationPanel() {
        notificationHideWork?.cancel()
        notificationPanel?.orderOut(nil)
    }

    func destroy() {
        hideNotificationPanel()
        if let monitoredApp = monitoredApp {
            MonitorService.unObserve(bundleId: monitoredApp.bundleId)
            MonitorEngine.shared.unMonitor(app: monitoredApp)
            statusBar.removeStatusItem(statusItem)
            position?.forget()
            AppSettings.toggleGiantBadge(for: monitoredApp.bundleId, value: false)
        }
    }

    private func makeNotificationPanel() -> NSPanel {
        let panel = NonKeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false

        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true
        panel.contentView = background
        return panel
    }
}

// On macOS 27 a status item NSPopover takes keyboard focus from the active app (upstream Doll 67).
private final class NonKeyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// In a window that is not key, AppKit gives the first click to the view only with acceptsFirstMouse.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct StatusItemPosition {
    let bundleId: String

    var autosaveName: String { "DollPlus_\(bundleId)" }
    // macOS removes this key when the item hides (Apple feedback FB9052637).
    private var systemKey: String { "NSStatusItem Preferred Position \(autosaveName)" }
    private var backupKey: String { "DollPlus_SavedPosition_\(bundleId)" }

    func backUp() {
        if let position = UserDefaults.standard.object(forKey: systemKey) {
            UserDefaults.standard.set(position, forKey: backupKey)
        }
    }

    func restore() {
        guard UserDefaults.standard.object(forKey: systemKey) == nil,
              let backup = UserDefaults.standard.object(forKey: backupKey) else {
            return
        }
        UserDefaults.standard.set(backup, forKey: systemKey)
    }

    func forget() {
        UserDefaults.standard.removeObject(forKey: backupKey)
    }
}

private struct DrawnState: Equatable {
    let text: String
    let showOnlyAppIcon: Bool
    let showAsRedBadge: Bool
    let grayOutWhenEmpty: Bool
}

extension NSScreen {
    static var screenWithMouse: NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let screenWithMouse = (screens.first {
            NSMouseInRect(mouseLocation, $0.frame, false)
        })

        return screenWithMouse
    }
    var hasTopNotchDesign: Bool {
        guard #available(macOS 12, *) else { return false }
        return safeAreaInsets.top != 0
    }
}
