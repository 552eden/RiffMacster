# RiffMacster

Makes the **whammy bar and tilt sensor** of the **PDP RiffMaster for PlayStation 5**
work on macOS, in Clone Hero and any other game that reads controllers.

> **Status: work in progress.** The helper is built and tested up to creating the virtual
> guitar. That step needs Apple's HID Virtual Device entitlement, so a signed
> `RiffMacster.app` is next.

## The problem

The guitar (USB `0E6F:0249`) sends whammy and tilt inside an undeclared, vendor-defined
block of its HID report:

| Report byte | Control | Range |
|---|---|---|
| 41 | Whammy | 0 (rest) → 255 (fully pressed) |
| 42 | Tilt | ~0–17 flat → 255 neck vertical (the guitar updates it only ~5×/s) |

macOS only exposes declared HID usages, so games never see these bytes. The same
offsets are used by [Clipper](https://github.com/Rosalie241/clipper) (Windows) and the
Linux `hid-sony` driver.

## How it works

1. **Starts on connect.** launchd launches `riffmacster` through an IOKit matching event
   when the guitar or its dongle appears. Nothing runs while it's unplugged.
2. **Takes over the guitar.** It opens the real guitar exclusively, so games don't see
   two guitars or doubled presses.
3. **Publishes a virtual twin.** It creates one virtual HID game controller,
   **"RiffMaster (RiffMacster)"**, with the guitar's own report descriptor, except that
   bytes 41 and 42 are labeled as **Slider (whammy)** and **Dial (tilt)** axes.
4. **Forwards reports unchanged.** Every report is copied byte-for-byte with its
   original timestamp. Event-driven with no polling, so CPU and battery use are negligible.
5. **Stops on disconnect.** It removes the virtual guitar and exits.

RiffMacster creates only a game controller. It never creates keyboard or mouse devices,
never injects other input, and sends no data anywhere.

## Requirements

- macOS on Apple Silicon (tested on macOS 27.2) and a PS5 PDP RiffMaster.
- To create the virtual guitar, the binary must be signed with the
  `com.apple.developer.hid.virtual.device` entitlement. macOS refuses it even for root
  otherwise. A signed app bundle is in progress.

## Building (developers)

```bash
make            # build build/riffmacster
make test       # descriptor self-test (no guitar needed)
make logs       # stream the helper's logs
```

The self-test checks that the patched descriptor puts whammy at byte 41 and tilt at
byte 42 and leaves every original button and axis unchanged.

### Tools

- `tools/hiddump.swift`: dumps raw HID reports and prints only the bytes that changed.
- `tools/axes.swift`: prints the whammy/tilt values that games see on the virtual guitar.

```bash
swiftc -O tools/hiddump.swift -o build/hiddump && ./build/hiddump 30
```

## License

MIT. See [LICENSE](LICENSE).
