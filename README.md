# YariAltTab

A minimal, personal Windows-style alt-tab for macOS.
Pure Swift + AppKit, ~400 lines, no dependencies, no Xcode project needed.

## Keys

| Keys | Action |
| --- | --- |
| `⌥ Tab` | Open switcher / next window |
| `⌥ ⇧ Tab` | Previous window |
| release `⌥` | Switch to selected window |
| `←` / `→` | Move selection |
| `Esc` | Cancel |
| `W` | Close selected window |
| `Q` | Quit selected app |
| click | Switch to that window |

A quick `⌥ Tab` tap switches to the previous window without showing the panel.

## Build & install

```bash
./build.sh install
```

This builds `build/YariAltTab.app`, copies it to `~/Applications`, and launches it.
On first launch, grant **Accessibility** in System Settings → Privacy & Security → Accessibility.
It starts working within a second, no restart needed. The menu bar icon has **Launch at Login** and **Quit**.

For live window previews, also grant **Screen Recording** (Privacy & Security → Screen & System Audio Recording),
then quit and relaunch the app. Without it, tiles show the app icon instead. Minimized windows always show the icon.

### Keeping the permission across rebuilds

Ad-hoc signed builds change signature on every build, so macOS forgets the Accessibility and Screen Recording grants
(`build.sh install` resets the stale entries so you just re-tick them). To avoid this, create a
self-signed code-signing certificate once in Keychain Access (Certificate Assistant → Create a
Certificate → type "Code Signing", name it e.g. `YariAltTab Dev`) and build with:

```bash
SIGN_IDENTITY="YariAltTab Dev" ./build.sh install
```

## Code layout

- `HotkeyTap.swift`: CGEventTap that intercepts ⌥Tab and friends
- `WindowList.swift`: enumerates windows via the Accessibility API, ordered by z-order, and focuses them
- `Switcher.swift`: selection state
- `SwitcherPanel.swift`: the HUD
- `Thumbnails.swift`: window previews via ScreenCaptureKit, cached between opens
- `AppDelegate.swift`: menu bar item, permission prompt, launch at login
