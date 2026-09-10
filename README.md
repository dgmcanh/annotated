# Annotated

Draw on the macOS screen, then throw it away.

Annotated has no window, no Dock icon and no menu bar item. It sits in the background waiting for a shortcut, puts a transparent canvas over every display, and disappears again.

| Key | Does |
| --- | --- |
| double-tap `⌘` | Show the canvas — or clear it, if it is already open |
| `⌥⌘A` | The same, without needing Accessibility permission |
| drag | Draw |
| `⌥` + drag | Erase whole strokes you touch |
| `⌘Z` / `⇧⌘Z` | Undo / redo |
| `esc` `esc` | Close, discarding everything. Two presses, within two seconds — the only way out |

Strokes use a Swift port of [perfect-freehand](https://github.com/steveruizok/perfect-freehand) with Excalidraw's settings.

## Build and install

```sh
./build.sh
cp -R Annotated.app /Applications/
open /Applications/Annotated.app
```

Launched from `/Applications`, the app registers itself as a Login Item. Remove it in System Settings → General → Login Items.

Double-tap `⌘` needs Accessibility permission — watching for a bare modifier means watching every key event. macOS asks on first launch; grant it under System Settings → Privacy & Security → Accessibility. The grant is tied to the code signature, so an ad-hoc build asks again after every rebuild. Sign with a stable identity to keep it:

```sh
CODESIGN_IDENTITY="Your Certificate Name" INSTALL=1 ./build.sh
```

`⌥⌘A` is a Carbon hot key and needs no permission, so the app still works if you refuse.

To keep a screenshot, use the system screenshot shortcuts (`⇧⌘4`, `⇧⌘5`). The canvas is an ordinary on-screen window, so your drawings are captured along with everything under them.

## Checks

```sh
.build/release/Annotated --self-check    # geometry, hit test, undo/redo
Annotated.app/Contents/MacOS/Annotated --show   # open the canvas without the shortcut
```
