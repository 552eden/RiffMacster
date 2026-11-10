// What happens when the user opens RiffMacster.app (double-click, or ⌘R in Xcode):
//  1. make sure the app lives in an Applications folder (so the background helper's path is stable),
//  2. register the background helper with macOS (SMAppService LaunchAgent; it starts only
//     when the guitar connects and exits when it disconnects),
//  3. install the Clone Hero button mapping if Clone Hero is installed,
//  4. show a short status window, then quit.

import AppKit
import ServiceManagement

enum Setup {
    static let agentPlist = "com.riffmacster.helper.plist"
    static let agentLabel = "com.riffmacster.helper"
    static let agent = SMAppService.agent(plistName: agentPlist)

    static func run() -> Int32 {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)

        if !isInApplicationsFolder {
            return offerMoveToApplications()
        }

        // Stop a helper that may be running from an older build, then (re)register so
        // launchd picks up this copy. Registering also fires for a guitar that's already
        // plugged in, so it starts working right away.
        stopRunningHelper()
        if agent.status == .enabled { try? agent.unregister() }

        var lines: [String] = []
        var needsApproval = false
        do {
            try agent.register()
        } catch {
            if agent.status != .requiresApproval {
                alert("RiffMacster couldn't be set up", "macOS refused to register the background helper:\n\(error.localizedDescription)", buttons: ["Quit"])
                return 1
            }
        }
        switch agent.status {
        case .enabled:
            lines.append("✓ RiffMacster is active. It starts automatically when your RiffMaster connects and quits when it disconnects. Nothing runs in the meantime.")
        case .requiresApproval:
            needsApproval = true
            lines.append("One more step: allow RiffMacster under System Settings → General → Login Items & Extensions.")
        default:
            lines.append("The background helper is in an unexpected state (\(agent.status.rawValue)).")
        }
        lines.append(CloneHero.installPreset().message)
        
        var buttons = needsApproval ? ["Open Login Items", "Later"] : ["OK"]
        buttons.append("Uninstall…")
        let choice = alert("RiffMacster", lines.joined(separator: "\n\n"), buttons: buttons)
        if needsApproval && choice == 0 { SMAppService.openSystemSettingsLoginItems() }
        if choice == buttons.count - 1 { return uninstall() }
        return 0
    }

    // MARK: - Uninstall

    static func uninstall() -> Int32 {
        let confirm = alert("Uninstall RiffMacster?",
                            "The background helper will be removed and the guitar goes back to how macOS sees it by default. You can then move RiffMacster to the Trash.",
                            buttons: ["Uninstall", "Cancel"])
        guard confirm == 0 else { return 0 }
        stopRunningHelper()
        try? agent.unregister()
        alert("RiffMacster was uninstalled", "You can now move RiffMacster to the Trash.", buttons: ["OK"])
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        return 0
    }

    // MARK: - Applications folder

    static var isInApplicationsFolder: Bool {
        let parent = Bundle.main.bundleURL.deletingLastPathComponent().standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return parent == "/Applications" || parent == home + "/Applications"
    }

    static func offerMoveToApplications() -> Int32 {
        let choice = alert("Copy RiffMacster to Applications?",
                           "RiffMacster needs to live in your Applications folder so it can start by itself when your guitar connects.",
                           buttons: ["Copy and Open", "Quit"])
        guard choice == 0 else { return 0 }

        let fm = FileManager.default
        let candidates = [URL(fileURLWithPath: "/Applications"),
                          fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        var lastError: Error?
        for dir in candidates {
            let dest = dir.appendingPathComponent(Bundle.main.bundleURL.lastPathComponent)
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                try fm.copyItem(at: Bundle.main.bundleURL, to: dest)
                let config = NSWorkspace.OpenConfiguration()
                config.createsNewApplicationInstance = true
                let done = DispatchSemaphore(value: 0)
                NSWorkspace.shared.openApplication(at: dest, configuration: config) { _, _ in done.signal() }
                _ = done.wait(timeout: .now() + 10)
                return 0
            } catch {
                lastError = error
            }
        }
        alert("Couldn't copy RiffMacster", lastError?.localizedDescription ?? "Unknown error", buttons: ["Quit"])
        return 1
    }

    // MARK: - Helpers

    static func stopRunningHelper() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["kill", "SIGTERM", "gui/\(getuid())/\(agentLabel)"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }

    @discardableResult
    static func alert(_ title: String, _ text: String, buttons: [String]) -> Int {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        buttons.forEach { a.addButton(withTitle: $0) }
        NSApp.activate(ignoringOtherApps: true)
        return a.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
    }
}
