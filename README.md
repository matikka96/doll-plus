# Doll Plus is a Mac app that helps you catch up on important messages!

Doll Plus is a maintained fork of [Doll](https://github.com/xiaogdgenuine/Doll) by [xiaogd](https://github.com/xiaogdgenuine), updated for current versions of macOS.

In **macOS**, It feels really great when you hide the **Dock**, open a **full screen** window and focus on your task.

But we are not living in an ideal world, your teammates may need your help anytime, and when you are in focus mode, occasionally you just _**forgot to respond**_!

Message apps like **Mail**, **Slack** and **Microsoft Teams** don't even offer a **_menu bar icon_** at all, so if you're working in a full screen window, or looking at another extra Monitor screen which can't show the Dock, there is no way you will notice the unread messages!

![Basic usage](./DollPlus/Docs/Images/dock-only.png)
 
(Sorry the notification center did notice you, but they will soon dismiss after a short period, if you miss that, you miss the message)

![Notification center](./DollPlus/Docs/Images/notification.png)

It would be great if we could put the icon and badge of these apps into the **_Menu bar_**, that way we can always easily notice new messages across screens, just like this:

![Show case](./DollPlus/Docs/Images/showcase.png)

# Why "Doll"?
The original author explains the name: in their favorite animation [《Darker than dark》](https://en.wikipedia.org/wiki/Darker_than_Black), if a **_Contractor_** use his power and never willing to pay the cost, eventually he will lose control of his power, become an emotionless **_Doll_**.

If we use too much **focus power** without paying the cost, what will we become >>__<<.

# Install
Doll Plus does not have a release yet. Build it from source:

1. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set your team ID. A stable signing identity keeps the Accessibility permission after each install.
2. Check out `main` with a clean tree.
3. Run `python3 -I scripts/install.py`. It builds the Release configuration, quits the running Doll Plus, replaces `/Applications/Doll Plus.app` and launches it.

Minimum system requirement: **_macOS 13.0_** (Ventura)

## Development builds
The Debug configuration builds "Doll Plus Dev" with the bundle ID `com.matikka96.DollPlus.dev`. It has its own settings, its own Accessibility entry and no default hotkey, so it does not change the installed Doll Plus. Its config window title ends with "(Dev)".

`python3 -I scripts/e2e.py --help` lists the end-to-end commands. `python3 -I scripts/e2e.py clean-registrations` removes the Launch Services registrations of the development and test copies.

# How to use?
It's simple, click on "+" button at the left bottom corner, search and select the app you want to monitor:

![Add monitor](./DollPlus/Docs/Images/usage-0.png)

![Search and select](./DollPlus/Docs/Images/search-and-select.png)

Then Doll Plus will ask for your permission to use the Accessibility API: 

![ask-for-permission.png](./DollPlus/Docs/Images/ask-for-permission.png)

Please make sure you grant that permission to **Doll Plus.app** otherwise nothing will be monitored!

![grant-permission.png](./DollPlus/Docs/Images/grant-permission.png)

Done, you are all setup!
Doll Plus now will monitor all the badge update in the Dock, and sync the numbers into the menu bar!

![running.png](./DollPlus/Docs/Images/running.png)

Doll Plus also can show new notification as red badge, just like in dock!

![show as badge](./DollPlus/Docs/Images/show-as-badge.png)

# I want to change the Monitor apps
If the monitored app is running, click on the menu bar icon will simply open that app.

But if you want to change stuffs, use right click, or left click while holding the "**_Option key(⌥)_**".

![config.png](./DollPlus/Docs/Images/config.png)

# Security concern about the permission?
**_Never! Ever! Trust! Anybody! in Internet!_**

**Doll Plus** is open source, you are free to download, review, modify and compile your own version of the app, go ahead and happy coding~


# How the app works?
**Doll Plus** uses the [macOS Accessibility API](https://developer.apple.com/library/archive/documentation/Accessibility/Conceptual/AccessibilityMacOSX/OSXAXmodel.html#//apple_ref/doc/uid/TP40001078-CH208-TPXREF101), it will sync the latest badge text to menu bar from every Monitored app in the **Dock** element.

Due to the limitation of Accessibility API(Can't watch for element's attribute value change), Doll Plus has to sync badges by every second(Yep, the infamy **_Polling_** style).

But don't worry about the performance, after all the synchronization happens only 86400 times per day, and all it does is just read and set few element's text, that's an operation executed less than **1ms**!

If you found any potential Bug or Performance issue, feel free to submit a PR!

# Love this app?
Doll Plus exists because of the work of the original author of Doll. Support them here:

<a href="https://www.buymeacoffee.com/xiaogd" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/arial-yellow.png" alt="Buy Me A Coffee" width="217px" ></a>
