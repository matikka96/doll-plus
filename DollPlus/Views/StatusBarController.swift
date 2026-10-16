import AppKit
import Monitor
import SwiftUI

let defaultIconSize: CGFloat = 20
let defaultIcon = #imageLiteral(resourceName: "DefaultStatusBarIcon")
private let notificationDuration: TimeInterval = 3

class StatusBarController {
    private var statusBar: NSStatusBar!
    private var isDark = false
    private(set) var latestBadgeText = ""
    private(set) var redrawCount = 0
    private var latestMessageCount = 0

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

    init() {
        setupStatusBar()
    }

    func setupStatusBar(icon: NSImage? = nil) {
        statusBar = .system
        statusItem = statusBar.statusItem(withLength: defaultIconSize)
        if let statusBarButton = statusItem.button {
            statusBarButton.sendAction(on: [.leftMouseUp, .rightMouseUp])
            statusBarButton.image = icon ?? defaultIcon
            statusBarButton.image?.size = NSSize(width: defaultIconSize, height: defaultIconSize)
            statusBarButton.image?.isTemplate = false
            statusBarButton.imagePosition = .imageLeft
            statusBarButton.action = #selector(onIconClicked(sender:))
            statusBarButton.target = self
            statusBarButton.toolTip = NSLocalizedString("Hold option key ⌥ and click to config", comment: "")
        }

        giantBadgePanel.isOpaque = false
        giantBadgePanel.hasShadow = false
        giantBadgePanel.backgroundColor = NSColor.clear
        // The 1000×800 panel covers the status item, so its tooltip misses the mouse-exit event.
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

        let noAppSelected = statusItem.button?.image == defaultIcon
        let isOptionKeyHolding = NSEvent.modifierFlags.contains(.option)
        let isRightClick = NSApp.currentEvent?.isRightClick == true
        let monitoredAppURL = monitoredApp.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleId) }

        if noAppSelected || monitoredAppURL == nil || isOptionKeyHolding || isRightClick {
            MonitorEngine.shared.showConfigWindow()
        } else if let monitoredAppBundleId = monitoredApp?.bundleId, let monitoredAppURL {
            let appRunning = MonitorService.isMonitoredAppRunning(bundleIdentifier: monitoredAppBundleId)
            if !appRunning {
                NSWorkspace.shared.open(monitoredAppURL)
            } else {
                if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == monitoredAppBundleId {
                    NSWorkspace.shared.frontmostApplication?.hide()
                } else {
                    MonitorService.openMonitoredApp(bundleId: monitoredAppBundleId)
                }
            }
        }
    }

    func monitorApp(app: MonitoredApp) {
        monitoredApp = app
        statusItem.autosaveName = "DollPlus_\(app.bundleId)"
        statusItem.button?.toolTip = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId) == nil
            ? String(format: NSLocalizedString("%@ is not installed. Click to choose another app", comment: ""), app.appName)
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

            self?.repositionGiantBadge()
        }
    }

    func hideStatusBar() {
        statusItem.isVisible = false
    }

    func updateBadgeText(_ text: String?, force: Bool = false) {
        statusItem.isVisible = true

        guard !AppSettings.showOnlyAppIcon else {
            latestBadgeText = text ?? ""
            refreshAppIcon()
            return
        }

        guard force || statusItem.button?.title != text else {
            return
        }

        let textWidth = (text ?? "")
            .width(withConstrainedHeight: defaultIconSize, font: .systemFont(ofSize: 14))
        statusItem.length = defaultIconSize + textWidth

        // New notification comes in
        let newText = text ?? ""

        if newText.isEmpty {
            hideGiantBadge()
        }

        guard let monitoredAppIcon = monitoredAppIcon else {
            return
        }

        if AppSettings.showAsRedBadge {
            let defaultIcon = monitoredAppIcon.addBadgeToImage(drawText: newText)
            let adjustedIcon = (newText.isEmpty && AppSettings.grayoutIconWhenNothingComing) ? (defaultIcon.grayOut() ?? defaultIcon) : defaultIcon
            updateBadgeIcon(icon: adjustedIcon)
            statusItem.length = defaultIconSize
            statusItem.button?.title = ""
        } else {
            let defaultIcon = monitoredAppIcon
            let adjustedIcon = (newText.isEmpty && AppSettings.grayoutIconWhenNothingComing) ? (defaultIcon.grayOut() ?? defaultIcon) : defaultIcon
            updateBadgeIcon(icon: adjustedIcon)
            statusItem.length = defaultIconSize + textWidth
            updateBadgeIcon(icon: adjustedIcon, size: CGSize(width: defaultIconSize, height: defaultIconSize))
            statusItem.button?.title = newText
        }

        let newMessageCount = Int(newText) ?? 0
        if latestBadgeText != newText {
            if AppSettings.showAlertInFullScreenMode {
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
        if AppSettings.showOnlyAppIcon {
            refreshAppIcon()
        } else {
            updateBadgeText(latestBadgeText, force: true)
        }
    }

    func refreshAppIcon() {
        guard let monitoredAppIcon else { return }
        let adjustedIcon = (latestBadgeText.isEmpty && AppSettings.grayoutIconWhenNothingComing) ? (monitoredAppIcon.grayOut() ?? monitoredAppIcon) : monitoredAppIcon
        statusItem.length = defaultIconSize
        statusItem.button?.title = ""
        updateBadgeIcon(icon: adjustedIcon, size: CGSize(width: defaultIconSize, height: defaultIconSize))
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
        let iconFrame = iconWindow.frame

        let targetApp = monitoredApp
        let view = NotificationView(icon: monitoredAppIcon ?? defaultIcon, badgeText: newText) { [weak self] in
            self?.hideNotificationPanel()
            if let bundleId = targetApp?.bundleId {
                MonitorService.openMonitoredApp(bundleId: bundleId)
            }
        }
        let hostingView = FirstMouseHostingView(rootView: view)
        let size = hostingView.fittingSize
        let x = min(max(iconFrame.midX - size.width / 2, screen.frame.minX), screen.frame.maxX - size.width)
        let y = min(iconFrame.minY, screen.frame.maxY) - size.height
        let panel = notificationPanel ?? makeNotificationPanel()
        notificationPanel = panel
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: false)
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

// Never key, so the full-screen app keeps keyboard focus.
private final class NonKeyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// The panel never becomes key, so the first click must reach the view.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension String {
    func width(withConstrainedHeight height: CGFloat, font: NSFont) -> CGFloat {
        let constraintRect = CGSize(width: .greatestFiniteMagnitude, height: height)
        let boundingBox = self.boundingRect(with: constraintRect, options: .usesLineFragmentOrigin, attributes: [NSAttributedString.Key.font: font], context: nil)

        return ceil(boundingBox.width)
    }
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
