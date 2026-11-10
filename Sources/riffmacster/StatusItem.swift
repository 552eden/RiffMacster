// Menu bar icon shown while the helper is running (i.e. while the guitar is connected).
// "Quit until next connect" stops the helper; launchd starts it again the next time the
// guitar connects, because the matching event only fires when the device appears.

import AppKit

final class StatusItemController: NSObject {
    private var item: NSStatusItem?

    func show() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            // RiffMaster line-art template (asset catalog); macOS tints it for light/dark/highlight.
            let image = NSImage(named: "MenuBarIcon")
                ?? NSImage(systemSymbolName: "guitars", accessibilityDescription: "RiffMacster")
            image?.isTemplate = true
            image?.size = NSSize(width: 18, height: 18)
            image?.accessibilityDescription = "RiffMacster"
            button.image = image
            button.toolTip = "RiffMacster: Active"
        }

        let menu = NSMenu()
        let header = NSMenuItem(title: "RiffMacster: Guitar connected", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        let detail = NSMenuItem(title: "Whammy and Tilt: Active", action: nil, keyEquivalent: "")
        detail.isEnabled = false
        menu.addItem(detail)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit until next connect", action: #selector(quitUntilNextConnect), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        self.item = item
    }

    @objc private func quitUntilNextConnect() {
        say("quit from the menu bar; will start again on the next connect")
        if let vdev = virtualDevice { IOHIDUserDeviceCancel(vdev) }
        exit(0)
    }
}

let statusItem = StatusItemController()
