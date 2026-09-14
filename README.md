# AHK Master Hotkeys

A single-file AutoHotkey v2 script for Windows that bundles a set of global
launcher hotkeys, fullscreen-aware hotkey protection, an F12 master on/off
toggle, and a Bluetooth AirPods connect/disconnect shortcut with **real**
connection verification (not just a trusted exit code).

Everything lives in one file: `MyHotkeys.ahk`. Nothing else to install or
keep alongside it — the AirPods logic is embedded PowerShell that gets
written to a temp file and run only when you press the hotkey.

## Requirements

- Windows 10/11
- [AutoHotkey v2.0](https://www.autohotkey.com/) installed
- PowerShell (built into Windows) for the AirPods hotkeys
- Optional: a Bluetooth pairing CLI utility if you want the AirPods
  hotkeys to work (see [AirPods setup](#airpods-setup) below)

## Setup

1. Install [AutoHotkey v2](https://www.autohotkey.com/).
2. Download `MyHotkeys.ahk` (or clone this repo).
3. Open `MyHotkeys.ahk` in a text editor and edit the **USER
   CONFIGURATION** block at the top to match your setup (see below).
4. Double-click `MyHotkeys.ahk` to run it, or right-click → Run Script.
5. To run it automatically at login: create a **shortcut** to
   `MyHotkeys.ahk` (not a copy of the file) and place the shortcut in
   your Startup folder (`Win+R` → `shell:startup`). Using a shortcut
   means the script always runs from its real location, so future edits
   take effect without touching Startup again.

## Hotkeys

| Hotkey | Action |
|---|---|
| `Ctrl+N` | New Chrome tab (launches Chrome if it isn't running) |
| `Ctrl+Shift+T` | Reopen last closed Chrome tab (only while Chrome is active) |
| `Ctrl+Shift+S` | Open Spotify Web |
| `Ctrl+Shift+C` | Launch the installed ChatGPT Windows app |
| `Ctrl+Shift+L` | Launch the installed Claude Windows app |
| `Ctrl+Shift+D` | Open Discord |
| `Ctrl+Shift+G` | Open GitHub |
| `Ctrl+Shift+Y` | Open YouTube |
| `Ctrl+Shift+W` | Open WhatsApp Web |
| `Ctrl+Shift+V` | Launch VS Code |
| `Ctrl+Shift+F` | Open your Downloads folder |
| `Ctrl+Shift+X` | Launch XAMPP Control Panel |
| `Ctrl+Shift+M` | Open phpMyAdmin |
| `Ctrl+Shift+A` | Turn on Bluetooth if needed, connect your configured audio device, and verify it actually connected |
| `Ctrl+Shift+Alt+A` | Disconnect that device's audio and mute system volume (Bluetooth itself stays on) |
| `Ctrl+Shift+?` | Open this README |
| `Ctrl+Alt+F4` | Gracefully close all normal open windows (`WinClose`, never a forced kill) |
| `F12` | Turn all of the above on/off. Always works, even during fullscreen. |

## Fullscreen protection

All hotkeys except `F12` are automatically disabled while the active
window is in **true fullscreen** (e.g. a video player or game that
covers an entire monitor with no borders). A normally **maximized**
window (including a maximized browser) is *not* treated as fullscreen,
so hotkeys like `Ctrl+N` keep working normally when you'd expect them to.

## AirPods setup

The `Ctrl+Shift+A` / `Ctrl+Shift+Alt+A` hotkeys need three things
configured at the top of `MyHotkeys.ahk`:

```ahk
global AirPodsMac := "XX:XX:XX:XX:XX:XX"
global AirPodsNameMatch := "AirPods"
global BluetoothUtilityPath := "C:\Apps\BluetoothDevicePairing\BluetoothDevicePairing.exe"
```

- **`AirPodsMac`** — the Bluetooth MAC address of your already-paired
  audio device. This script only *connects/disconnects* an existing
  pairing; it does not pair a new device.
- **`AirPodsNameMatch`** — a substring of your device's audio endpoint
  name, used to verify the connection actually came up (see below).
  `"AirPods"` matches any AirPods model.
- **`BluetoothUtilityPath`** — full path to a command-line Bluetooth
  pairing utility. **This tool is not included in this repo.** The
  script expects it to support:
  - `<exe> pair-by-mac --mac <MAC> --type Bluetooth` (also works to
    reconnect an already-paired device)
  - `<exe> disconnect-bluetooth-audio-device-by-mac --mac <MAC> --type Bluetooth`

  If your tool uses different flags, adjust the two `& $exe ...` lines
  inside `AirPodsConnectScript()` / `AirPodsDisconnectScript()`.

### Why "verification" matters

Some Bluetooth CLI tools report a successful exit code even when the
audio connection never actually came up. This script does not trust
that: after asking the utility to connect, it independently checks
Windows' real Core Audio device list (via `IMMDeviceEnumerator`) for an
active playback or recording endpoint whose name contains
`AirPodsNameMatch`, and only then reports success. It will never show
"AirPods connected" unless it verified it.

Turning Bluetooth on uses the standard Windows Radio API
(`Windows.Devices.Radios`) — the same mechanism Windows Settings and
Action Center use. The script never unpairs your device, never touches
the registry, and never disables or restarts Bluetooth services.

## Notes

- `Ctrl+S` is left alone as the normal Windows Save shortcut — Spotify
  uses `Ctrl+Shift+S` instead.
- The Bluetooth pairing utility referenced above requires explicit
  `--mac` and `--type` flags; passing the MAC as a bare positional
  argument will fail silently against most CLI option parsers.

## License

MIT — see [LICENSE](LICENSE).
