// Installs a ready-made Clone Hero (Rewired) mapping for the RiffMacster virtual guitar,
// so frets, strum, start/select, whammy and tilt work without manual binding.
//
// Clone Hero has no built-in guitar profiles on macOS. Rewired saves a manual mapping in
// Clone Hero's preferences under a key derived from the controller's name + PID + VID.
// The virtual guitar's identity never changes, so one saved mapping works for everyone.

import AppKit
import Foundation

enum CloneHero {
    static let bundleID = "com.srylain.CloneHero"
    static let appID = bundleID as CFString
    static let zeroGuid = "00000000-0000-0000-0000-000000000000"

    enum Outcome {
        case notInstalled          // no Clone Hero on this Mac: nothing to do
        case alreadyMapped         // user already has a mapping; left alone
        case cloneHeroRunning      // can't write now (Clone Hero overwrites prefs on quit)
        case installed
        case failed(String)

        var message: String {
            switch self {
            case .notInstalled: return "Clone Hero isn't installed, so no button mapping was needed."
            case .alreadyMapped: return "Clone Hero already has a mapping for the guitar; it was left as is."
            case .cloneHeroRunning: return "Clone Hero is open. The button mapping will be added automatically the next time you connect the guitar while Clone Hero is closed."
            case .installed: return "Clone Hero's button mapping for the guitar was installed."
            case .failed(let why): return "Couldn't install the Clone Hero mapping: \(why)"
            }
        }
    }

    static var isInstalled: Bool {
        !NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID).isEmpty
    }

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Rewired identifier of the virtual guitar ("OSX" + name + PID + VID). The real guitar's
    /// mapping ("…PDPRiffMasterGuitarforPS5…") uses a different identifier, so it never
    /// counts as a RiffMacster mapping.
    static let identifier = "OSXOSXRiffMaster(RiffMacster)02490E6F"

    /// True if any saved Rewired data (any player, map or calibration) mentions RiffMacster.
    static func hasRiffMacsterMapping(in keys: [String]) -> Bool {
        keys.contains { $0.hasPrefix("RewiredSaveData") && $0.contains("hardwareIdentifier=\(identifier)") }
    }

    /// Every key currently in Clone Hero's settings (~/Library/Preferences/com.srylain.CloneHero.plist).
    static var savedKeys: [String] {
        (CFPreferencesCopyKeyList(appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String]) ?? []
    }

    static func installPreset(force: Bool = false) -> Outcome {
        guard isInstalled else { return .notInstalled }
        guard let url = Bundle.main.url(forResource: "CloneHeroPreset", withExtension: "plist"),
              let preset = NSDictionary(contentsOf: url) as? [String: String],
              let id = preset["hardwareIdentifier"], id == identifier, let map = preset["controllerMap"],
              let known = preset["knownActionIds"], let calibration = preset["calibrationMap"]
        else { return .failed("the preset is missing from the app") }

        let calibrationKey = "RewiredSaveData|dataType=CalibrationMap|controllerType=Joystick|hardwareIdentifier=\(id)|hardwareGuid=\(zeroGuid)"
        func mapKey(_ player: Int, known: Bool) -> String {
            "RewiredSaveData|playerName=Player\(player)|dataType=ControllerMap\(known ? "_KnownActionIds" : "")|kv=2|controllerMapType=JoystickMap|categoryId=1|layoutId=3|hardwareGuid=\(zeroGuid)|hardwareIdentifier=\(id)|duplicate=0"
        }

        // Any existing RiffMacster mapping is the user's: never touch it.
        // (A mapping for the real RiffMaster doesn't count; ours is added alongside it.)
        if !force, hasRiffMacsterMapping(in: savedKeys) {
            return .alreadyMapped
        }
        // Clone Hero rewrites its preferences when it quits, which would undo our changes.
        if isRunning { return .cloneHeroRunning }

        var values: [String: String] = [calibrationKey: calibration]
        for player in 1...4 {
            values[mapKey(player, known: false)] = map
            values[mapKey(player, known: true)] = known
        }

        // Back up whatever we are about to overwrite.
        var backup: [String: Any] = [:]
        for key in values.keys {
            if let old = CFPreferencesCopyAppValue(key as CFString, appID) { backup[key] = old }
        }
        if !backup.isEmpty {
            let dir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/RiffMacster", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            (backup as NSDictionary).write(to: dir.appendingPathComponent("clonehero-backup-\(stamp).plist"), atomically: true)
        }

        for (key, value) in values {
            CFPreferencesSetAppValue(key as CFString, value as CFString, appID)
        }
        return CFPreferencesAppSynchronize(appID) ? .installed : .failed("Clone Hero's settings couldn't be saved")
    }
}
