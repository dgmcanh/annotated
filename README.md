# Annotated

Draw on the macOS screen, then throw it away.

Annotated has no window, no Dock icon and no menu bar item. It sits in the background waiting for a shortcut, puts a transparent canvas over every display, and disappears again.

| Key | Does |
| --- | --- |
| `⌥⌘A` | Show the canvas / hide it again |
| drag | Draw |
| `⌥` + drag | Erase whole strokes you touch |
| `⌘Z` / `⇧⌘Z` | Undo / redo |
| `esc` | Close, discarding everything |

Strokes use a Swift port of [perfect-freehand](https://github.com/steveruizok/perfect-freehand) with Excalidraw's settings.

## Build and install

```sh
./build.sh
cp -R Annotated.app /Applications/
open /Applications/Annotated.app
```

Launched from `/Applications`, the app registers itself as a Login Item. Remove it in System Settings → General → Login Items.

To keep a screenshot, use the system screenshot shortcuts (`⇧⌘4`, `⇧⌘5`). The canvas is an ordinary on-screen window, so your drawings are captured along with everything under them.

## Checks

```sh
.build/release/Annotated --self-check    # geometry, hit test, undo/redo
Annotated.app/Contents/MacOS/Annotated --show   # open the canvas without the shortcut
```
