//
//  Utils.swift
//  Doll
//
//  Created by huikai on 2022/6/11.
//

import Foundation
import AppKit
import Utils

enum Utils {

    static func getAppIcon(bundleId: String) -> NSImage {
        let defaultIcon = #imageLiteral(resourceName: "DefaultStatusBarIcon")
        guard let appFullPath = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)?.absoluteURL.path else {
            return defaultIcon
        }

        return NSWorkspace.shared.icon(forFile: appFullPath)
    }

    static var currentActiveWindowIsFullScreen: Bool {
        let screens = NSScreen.screens
        guard let activeWindow = frontmostWindowAX,
              let windowFrame = frameAX(of: activeWindow),
              let screenIndex = ScreenGeometry.indexOfScreen(holding: windowFrame, screenFrames: screens.map(\.frame)) else {
            return false
        }
        let windowScreen = screens[screenIndex]

        // In Mac with notch on menubar, this is the only way I found to detect either current window is in fullscreen
        if windowFrame.height == windowScreen.frame.size.height - (NSApplication.shared.mainMenu?.menuBarHeight ?? 0) {
            return true
        }

        var fullScreenButton: AnyObject?
        AXUIElementCopyAttributeValue(
            activeWindow, kAXFullScreenButtonAttribute as CFString, &fullScreenButton
        )
        if let fullScreenButton,
           let fullScreenButtonPosition = positionAX(of: fullScreenButton as! AXUIElement),
           let mainScreen = screens.first {
            
            // If mac connected to multiple displays,
            
            /*
             * Which coordinator system kAXPositionAttribute value use:
             *
             * 0, 0 (Main screen's top-left corner)
             *  ┌── ── ── ── ── ── ── ── ── ── ── ── ── ─►
             *  │
             *  │
             *  │
             *  │
             *  │
             *  │
             *  │
             *  │
             *  │
             *  │
             *  │
             *  ▼
             *
             * The coordinator system macOS used to arrange multiple screens (https://stackoverflow.com/a/14779155/2357513):
             *                        ▲
             *                        │
             *                        │
             *                        │
             *                        │
             *    ┌───────────────────┤
             *    │                   │
             *    │                   ├────────────┐
             *    │                   │            │
             *    │                   │            ├─────────────┐
             *    │   Third Screen    │            │             │
             *    │                   │ Main Screen│             │
             *    │                   │            │             │
             *    │                   │            │Second Screen│
             *    └───────────────────┴────────────┼─────────────┼─►
             * -200, 0               0, 0          │             │
             * (Screen.frame.origin)               └─────────────┘
             *                                  50, -20(Screen.frame.origin)
             *
             * So a coordinator converting logic is needed:
             *  ▲
             *  │
             *  │
             *  │
             *  │
             *  │
             *  │
             *  ├────────────┐
             *  │            │
             *  │   Menubar  ├─────────────┐
             *  ├────────────┤    Menubar  │
             *  │  50 x 50   ├─────────────┤
             *  │            │             │
             *  │            │  50 x 50    │
             *  └────────────┼─────────────┼─►
             * 0, 0          │             │
             *               └─────────────┘
             *            50, -20(Screen2.frame.origin)
             *
             *
             *  Screen2.visibleFrame.minY = -20
             *  Screen2.visibleFrame.maxY = -20 + 50(Screen2.visibleFrame.height) = 30
             *  Screen2.menubar.frame.maxY = 50(MainScreen.frame.maxY) - 30(Screen2.visibleFrame.maxY) = 20
             */
            let menubarYPositionThresholdInActiveScreen = mainScreen.frame.maxY - windowScreen.visibleFrame.maxY
            // If a window is fullscreen, it's fullscreen button(The whole toolbar actually) y offset is less than menubar.frame.maxY
            return fullScreenButtonPosition.y < menubarYPositionThresholdInActiveScreen
        }
        
        return false
    }

    private static func frameAX(of element: AXUIElement) -> CGRect? {
        guard let position = positionAX(of: element), let size = sizeAX(of: element) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private static func positionAX(of element: AXUIElement) -> CGPoint? {
        guard let valueAX = attributeAX(of: element, kAXPositionAttribute) else { return nil }
        var position = CGPoint.zero
        AXValueGetValue(valueAX, .cgPoint, &position)
        return position
    }

    private static func sizeAX(of element: AXUIElement) -> CGSize? {
        guard let valueAX = attributeAX(of: element, kAXSizeAttribute) else { return nil }
        var size = CGSize.zero
        AXValueGetValue(valueAX, .cgSize, &size)
        return size
    }

    private static func attributeAX(of element: AXUIElement, _ attribute: String) -> AXValue? {
        var valueAX: AnyObject?
        AXUIElementCopyAttributeValue(element, attribute as CFString, &valueAX)
        return valueAX.map { $0 as! AXValue }
    }

    static var frontmostProcessId: pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    static var frontmostApplicationAX: AXUIElement? {
        guard let frontmostPid = frontmostProcessId else { return nil }
        return AXUIElementCreateApplication(frontmostPid)
    }

    static var frontmostWindowAX: AXUIElement? {
        guard let appElement = frontmostApplicationAX else { return nil }

        var frontmostWindowAX: AnyObject?
        AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &frontmostWindowAX)

        if frontmostWindowAX != nil {
            return (frontmostWindowAX as! AXUIElement)
        }

        return nil
    }

    static var appName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? "Doll Plus"
    }

    static var appVersion: String {
        Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String
    }

}
