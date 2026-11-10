# RiffMacster

Makes the **whammy bar and tilt sensor** of the **PDP RiffMaster for PlayStation 5**
work on macOS, in Clone Hero and any other game that reads controllers.

## Download

Get **RiffMacster-x.y.z.dmg** from [Releases](https://github.com/552eden/RiffMacster/releases/latest),
open it and drag RiffMacster to Applications. The app is signed with Developer ID and
notarized by Apple. Requires macOS 13 or later (Apple Silicon or Intel).

## Using it

1. Open **RiffMacster.app**. If it isn't in your Applications folder, it offers to copy
   itself there.
2. It registers a small background helper with macOS and shows a status window.
   - If macOS asks, allow RiffMacster under **System Settings → General → Login Items &
     Extensions**.
   - The first time the guitar connects, allow RiffMacster under **Privacy & Security →
     Device Control and Data Access**.
3. Plug in the guitar (or turn it on with its dongle connected) and play.

There's nothing to keep open. The helper starts by itself when the guitar connects and
quits when it disconnects. While it's running, a **guitar icon** sits in the menu bar; its
**Quit until next connect** item stops the helper with the guitar still plugged in, and it
starts again the next time the guitar connects. To remove RiffMacster, open the app again
and choose **Uninstall…**.

## Clone Hero

Clone Hero has no built-in guitar profiles on macOS, so it normally makes you bind every
button and calibrate whammy and tilt by hand. RiffMacster handles both:

- **Buttons are mapped automatically** if Clone Hero is installed. RiffMacster adds a
  ready-made mapping for the guitar to Clone Hero's settings, either when you open
  RiffMacster or the next time the guitar connects while Clone Hero is closed.
  An existing mapping is never overwritten.
- **No calibration, with or without Clone Hero.** Whammy and tilt rest at the center of
  their range (0 at rest, +1 fully pressed / neck up), which is what games assume by default.

## How it works

The guitar (USB `0E6F:0249`) sends whammy and tilt inside an undeclared, vendor-defined
block of its HID report, so macOS never exposes them to games:

| Report byte | Control | Range |
|---|---|---|
| 41 | Whammy | 0 (rest) → 255 (fully pressed) |
| 42 | Tilt | ~0–17 flat → 255 neck vertical (the guitar updates it only ~5×/s) |

The same offsets are used by [Clipper](https://github.com/Rosalie241/clipper) (Windows)
and the Linux `hid-sony` driver.

1. **Starts on connect.** The app bundles a LaunchAgent (registered with `SMAppService`)
   that launchd starts through an IOKit matching event when the guitar or its dongle appears.
2. **Takes over the guitar.** It opens the real guitar exclusively, so games don't see two
   guitars or doubled presses.
3. **Publishes a virtual twin.** It creates one virtual HID game controller,
   **"RiffMaster (RiffMacster)"**, with the guitar's own report descriptor, except that
   bytes 41 and 42 are declared as **Slider (whammy)** and **Dial (tilt)** center-rest axes.
4. **Forwards reports.** Every report is passed through with its original timestamp; only
   whammy and tilt are rescaled. Event-driven with no polling, so CPU and battery use are negligible.
5. **Stops on disconnect.** It removes the virtual guitar and exits.

RiffMacster creates only a game controller. It only ever opens the PDP RiffMaster, never
creates keyboard or mouse devices, never injects other input, and sends no data anywhere.

## Building

RiffMacster is an Xcode project. It needs the `com.apple.developer.hid.virtual.device`
entitlement (HID Virtual Device capability) on your Apple Developer team.

1. Open `RiffMacster.xcodeproj`.
2. Select the **RiffMacster** target → **Signing & Capabilities** → choose your **Team**.
3. Press **⌘R**. The app opens, offers to copy itself to Applications, and installs itself
   from there.

For debugging the helper, enable `--foreground` (run the helper in the console) or
`--selftest` (descriptor checks, no guitar needed) under **Product → Scheme → Edit
Scheme… → Run → Arguments**.

### Debug tools

- `tools/hiddump.swift`: dumps raw HID reports and prints only the bytes that changed.
- `tools/axes.swift`: prints the whammy/tilt values that games see on the virtual guitar.

```bash
swiftc -O tools/axes.swift -o build/axes && ./build/axes
```

## License

MIT. See [LICENSE](LICENSE).
