import AppKit
import Monitor
import SwiftUI

let defaultIconSize: CGFloat = 20
let defaultIconFrameSize = NSSize(width: defaultIconSize, height: defaultIconSize)
let defaultIcon = #imageLiteral(resourceName: "DefaultStatusBarIcon")

class StatusBarController {
    private var statusBar: NSStatusBar!
    private var isDark = false
    private(set) var latestBadgeText = ""
    private(set) var redrawCount = 0
    private var latestMessageCount = 0
    private var drawnState: DrawnState?

    private var giantBadgeController = GiantBadgeViewController()
    private var giantBadgePanel = NSPanel(contentRect: NSRect(origin: .zero, size: defaultWindowSize),
                              styleMask: [.nonactivatingPanel],
                              backing: .buffered, defer: false)
    private var lastTimeShowingGiantBadge = Date()

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
            : NSLocalizedString("Hold option key ⌥ and click to config", comment: "")
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

    func showPopover(popover: NSPopover? = nil) {
        if let statusBarButton = statusItem.button {
            popover?.show(relativeTo: statusBarButton.bounds, of: statusBarButton, preferredEdge: .maxY)
            if let contentWindow = popover?.contentViewController?.view.window {
                // A little hack to prevent popover shitup with menubar
                // https://stackoverflow.com/a/35047661
                contentWindow.parent?.removeChildWindow(contentWindow)
            }
        }
    }

    func hidePopover(popover: NSPopover? = nil) {
        popover?.performClose(nil)
    }

    func hideStatusBar() {
        if statusItem.isVisible {
            statusItem.isVisible = false
        }
    }

    func updateBadgeText(_ text: String?, force: Bool = false) {
        if !statusItem.isVisible {
            statusItem.isVisible = true
        }

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
        let icon = showsRedBadge ? monitoredAppIcon.addBadgeToImage(drawText: newText) : monitoredAppIcon
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
        }

        let newMessageCount = Int(newText) ?? 0
        if latestBadgeText != newText {
            if AppSettings.showAlertInFullScreenMode {
                tryShowTheNewNotificationPopover(newText: newText)
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
                let giantBadgeView = GiantBadgeView(controller: giantBadgeController) { [weak self] in
                    guard let self = self else { return }
                    self.onIconClicked(sender: self)
                }
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

    func tryShowTheNewNotificationPopover(newText: String) {
        if Utils.currentActiveWindowIsFullScreen {

            let notificationPopover = createNotificationPopover(newText: newText)
            showPopover(popover: notificationPopover)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.hidePopover(popover: notificationPopover)
            }
        }
    }

    func destroy() {
        if let monitoredApp = monitoredApp {
            MonitorService.unObserve(bundleId: monitoredApp.bundleId)
            MonitorEngine.shared.unMonitor(app: monitoredApp)
            statusBar.removeStatusItem(statusItem)
            AppSettings.toggleGiantBadge(for: monitoredApp.bundleId, value: false)
        }
    }

    private func createNotificationPopover(newText: String) -> NSPopover {
        let notificationPopover = NSPopover()
        let textWidth = newText
                .width(withConstrainedHeight: defaultIconSize, font: .systemFont(ofSize: 14))
        let horizonPadding: CGFloat = 32
        let verticalPadding: CGFloat = 16
        notificationPopover.contentSize = NSSize(width: defaultIconSize + textWidth + horizonPadding, height: defaultIconSize + verticalPadding)
        notificationPopover.behavior = .transient
        notificationPopover.setValue(true, forKeyPath: "shouldHideAnchor")

        let targetApp = monitoredApp
        let view = NotificationView(icon: monitoredAppIcon ?? defaultIcon, badgeText: newText) {
            if let bundleId = targetApp?.bundleId {
                MonitorService.openMonitoredApp(bundleId: bundleId)
            }
        }
        notificationPopover.contentViewController = NSHostingController(rootView: view)

        return notificationPopover
    }
}

private struct DrawnState: Equatable {
    let text: String
    let showOnlyAppIcon: Bool
    let showAsRedBadge: Bool
    let grayOutWhenEmpty: Bool
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
