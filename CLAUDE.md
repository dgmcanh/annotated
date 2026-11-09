# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Annotated is a macOS screen-annotation app: a background process with no UI of its own that opens a transparent drawing canvas over every display on a double-tap of `⌃`, and discards everything on one press of `esc`.

Closing is `esc`'s job alone. A double-tap while the canvas is already open clears the drawing rather than closing, so neither gesture can throw work away by accident: the clear is checkpointed and `⌘Z` brings it back.

## Working in this repo

Commit straight to `main`. No feature branches — this overrides the workspace rule about branching off the default branch.

## Commands

| Command | Does |
| --- | --- |
| `swift build` | Debug build. Swift 6.3 toolchain, macOS 14 deployment target, Swift 5 language mode (`swift-tools-version: 5.9` — Swift 6 strict concurrency would reject the AppKit globals). |
| `./build.sh` | Release build, runs the self-check, assembles and signs `Annotated.app`. |
| `INSTALL=1 ./build.sh` | The same, then replaces `/Applications/Annotated.app`. |
| `.build/release/Annotated --self-check` | The whole test suite. |
| `Annotated.app/Contents/MacOS/Annotated --show` | Opens the canvas without the hot key. |
| `open -n -a /Applications/Annotated.app --args --grant` | Asks for Accessibility permission, waits for it, exits. The only thing that asks. |

There is no test target and no single-test command. Checks live in `selfCheck()` in `Sources/Annotated/Board.swift`, run by `--self-check`, and use `precondition` rather than `assert` so they still bite in a release build. `build.sh` runs them, so a failing check fails the build.

**Use `INSTALL=1` whenever a build should take effect.** `/Applications/Annotated.app` is the copy that owns the Login Item, and a plain `./build.sh` leaves it stale. Two copies from different paths both run and both register `⌥⌘A`, giving two overlays on one keypress — LaunchServices only de-duplicates within a bundle path. `INSTALL=1` replaces the bundle but leaves the running copy on the old code: quit it and `open -a /Applications/Annotated.app` before trying the change.

## Layout

| Path | Holds |
| --- | --- |
| `Sources/Annotated/main.swift` | Entry point, `AppDelegate`, Login Item registration. |
| `Sources/Annotated/Hotkeys.swift` | `HotkeyCenter` (Carbon hot keys) and `DoubleModifierTap` (double-tap `⌃`). |
| `Sources/Annotated/Overlay.swift` | `OverlayWindow` (canvas), `HUDWindow`, `CanvasHostingView`, `OverlayController`. |
| `Sources/Annotated/Board.swift` | Stroke model, snapshot undo, object eraser, hit test, `selfCheck()`. Ink colour and width default here. |
| `Sources/Annotated/Freehand.swift` | Port of perfect-freehand. |
| `Resources/Annotated.icns` | App icon, copied into the bundle by `build.sh`. |
| `design/` | Icon sources: the design canvas artboards, `icon-full.svg` / `icon-small.svg`, and `render-icon.swift`, which rasterises an SVG to PNGs by snapshotting it in WebKit. Nothing here is built by `build.sh`. The icon sits on Apple's grid — an 824 px continuous-corner shape centred on the 1024 canvas — because macOS draws its own rim on that shape, and full-bleed art shows the rim as a broken line inside the edge. `icon-small.svg` is the 16 and 32 px art. |
| `docs/testing/` | Run records. |

## Architecture

One process, no window while idle. A Carbon hot key opens one `OverlayWindow` per `NSScreen`, each with its own `Board`, plus one `HUDWindow` per screen carrying the border and hint pill. `OverlayController` owns both sets and tears them down together.

`Board` is the model and the only thing worth unit-checking: strokes, a snapshot undo stack, and an object eraser that removes whole strokes rather than pixels. `CanvasHostingView` converts AppKit mouse events into `beginInput` / `extendInput` / `endInput` calls on it; a SwiftUI `Canvas` renders `strokes` plus the in-progress `live` stroke.

### Invariants

These are load-bearing and most were bugs first — `docs/testing/first-build.md` holds the evidence for the window ones.

- **`Freehand.swift` is a 1:1 port of perfect-freehand** with Excalidraw's options (`size = width * 4.25`, thinning 0.6, smoothing 0.5, streamline 0.5, easeOutSine, `last: true` when finished). Its output matches the npm package point for point on every stroke shape tested; changing the algorithm breaks that. Tapering and real pressure input are the two deliberately dropped features.
- **The canvas is an `NSPanel` with `.nonactivatingPanel`, at level `.screenSaver`, with a background alpha of 1/255.** A plain `NSWindow` cannot hold key focus from a background app under macOS 14+ cooperative activation; `isFloatingPanel = true` silently resets `level` to `.floating`, which puts the canvas behind a full-screen app; and the window server does not hit-test a fully transparent window, so a `.clear` background passes every click through to the app underneath.
- **Pointer input is AppKit, not SwiftUI.** `NSHostingView.hitTest` returns nil over transparent content, so `CanvasHostingView` overrides `hitTest` to claim every point. `.contentShape(Rectangle())` only fixes SwiftUI's internal gesture routing and is not enough.
- **Two ways in, on purpose.** Double-tap `⌃` is `DoubleModifierTap`, which watches `flagsChanged` and so needs Accessibility permission; `⌥⌘A` is a Carbon hot key that needs none and keeps the app usable when that permission is refused. Carbon cannot express a bare-modifier tap, which is why both exist.
- **Nothing asks for Accessibility permission except `--grant`.** The app launches at login, so a prompt at startup is a dialog on every boot; `applicationDidFinishLaunching` only checks. Run `--grant` through `open`, never as a binary from a shell: TCC credits the request to the responsible process, so a shell launch asks on Terminal's behalf and Annotated never reaches the list. The grant follows the code signature, and an ad-hoc one's designated requirement is a cdhash that changes on every build, so `build.sh` signs with the Apple Development identity (Team ID 7NYFB43WDM) instead and the grant survives rebuilds. A self-signed certificate has no Team ID, which leaves keychain items on a `cdhash:` partition that asks again on each rebuild. Decided 2026-10-24: every app in the workspace signs with Apple Development.
- **`esc` closes on one press and discards everything.** There is no confirmation: the ink was never saved, so nothing is lost that was ever kept, and a double-tap `⌃` clears rather than closes, so the two gestures cannot be confused.
- **The overlay's shortcuts are global hot keys, not window key handling** — registered while the canvas is up, released when it closes. Focus is not something this app can rely on holding.
- **Activation policy stays `.accessory` throughout.** Switching to `.regular` to win focus puts an icon in the Dock for as long as the canvas is up.
- **The app never captures the screen.** The canvas is an ordinary on-screen window, so the system screenshot shortcuts already include the ink. There is no capture code and the app needs no Screen Recording permission — but the HUD's border and hint pill land in those screenshots too.
- **Scrolling passes through the canvas through an event tap** (`OverlayController.filter`), so it needs Accessibility; without the permission the wheel stays on the canvas. Each scroll makes the canvases `ignoresMouseEvents` until 250 ms after the last one. The ink stays where it was drawn on screen; making it follow the content was tried and dropped. The toggle lands 5–60 ms late, so a scroll that still hits the canvas is re-posted with private field 51 (the target window) cleared, and a click while it is still click-through is held and replayed after 80 ms. `docs/testing/scroll-through.md` holds the evidence.
- **Nothing is persisted.** No preferences, no drawing storage, no state across sessions.
- **The Login Item registers only from `/Applications`**, so dev builds do not leave entries pointing at a build folder.
- **`RegisterEventHotKey` returns `noErr` even when another app already owns the combination**, so a hot key conflict cannot be detected; the "could not register" alert only catches a registration the system itself rejects.

## Verifying a change

Synthetic mouse and key events need Accessibility permission for the terminal. Where it is granted, `.build/debug/Annotated --show` can be driven end to end with events posted at `kCGHIDEventTap`; `docs/artifacts/scroll-through/drive.swift` does that. Where it is not, everything beneath the hot key and the pointer can still be driven: link the sources into a throwaway binary and call the real types directly — construct an `OverlayWindow`, send `NSEvent`s to its `contentView`, drive `Board`. `docs/artifacts/first-build/harness.swift` is that harness.

Two failure modes have wasted time in this repo and are worth guarding against:

- A shell one-liner where an early `cd` fails short-circuits the `&&` chain, so the edit never runs while a later command still reports success. Assert on the replacement text, not on the command exiting 0.
- For anything involving the window server, log the specific event you care about. `mouseMoved` is delivered to the key window regardless of what is under the cursor, so it proves nothing about hit-testing; only `mouseDown` does.
