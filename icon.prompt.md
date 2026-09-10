# Icon prompt — Annotated

Design a macOS app icon for **Annotated**.

## What the app is

Annotated is a macOS utility that lets you draw on top of whatever is already on screen, screenshot the result, and throw it all away.

It has no window, no Dock icon and no menu bar item. It waits in the background until you press `⌥⌘A`, then drops a transparent canvas over every display. You draw freehand in red ink. Option-drag erases whole strokes, `⌘Z` undoes, `⇧⌘C` screenshots the whole display with your drawings on it, `⇧⌘R` picks a rectangle to capture, and `esc` throws everything away. Nothing is saved, nothing persists between sessions.

It is a marker you pick up for fifteen seconds while explaining something, then put down.

## Personality

- **Ephemeral, not archival.** This is not a notes app, a whiteboard, or a design tool. Nothing here is kept.
- **Instant and weightless.** Summoned by a keystroke, gone by a keystroke. No chrome, no ceremony, no settings.
- **The ink is the product.** A confident hand-drawn mark is the one thing the user actually makes.

Adjacent in spirit to CleanShot X, Shottr and Excalidraw. Not a Photoshop or Procreate sibling — no palettes, no brush libraries, no artist's toolbox.

## The mark

The app's own visual language, which the icon should draw from:

- **Ink: red** (`systemRed`). Strokes are pressure-tapered — thin where the pointer moves fast, thicker where it slows, tapered at both ends. They are rendered as filled outlines, not uniform-width lines, so they read as a felt-tip marker rather than a technical pen. This taper is the single most characteristic thing about the app; a constant-width stroke would be wrong.
- **Surface: glass.** The canvas is transparent; the on-screen furniture is a blue accent border and a Liquid Glass capsule.
- **Blue** (system accent) is the interface; **red** is the user's mark. Keep that split.

## Concepts to explore

Give me a few directions rather than one. Starting points, not a brief to follow literally:

1. **Stroke over glass.** A single confident red tapered stroke — a check, a circle, or a swoosh — sitting on or above a translucent glass panel, with real depth between the two layers.
2. **Marked-up screen.** A simplified screen or window rectangle with a red stroke drawn across it, breaking past the edge to show the ink is on top of the screen, not inside the app.
3. **Ink and crosshair.** The red stroke paired with the thin crosshair cursor the app switches to, suggesting "draw anywhere".

The strongest idea is likely the simplest: one gesture of red ink, given room to breathe.

## Constraints

- **Standard macOS app icon geometry** — the rounded-rectangle (squircle) form, with the usual safe-area margins rather than art running to the edge.
- **Legible at 16×16.** One dominant shape. No text, no thin hairlines, no fine detail that dissolves when small. Show me the 16 px and 32 px renderings, not just the large one.
- **Works on light and dark desktops**, and against a busy wallpaper.
- **macOS 26 era.** Layered depth and glass material are welcome; skeuomorphic pencils, paint tubes, easels, palettes and torn-paper textures are not.
- No lettering, no "A" monogram, no camera or shutter iconography — the capture is a consequence, not the point.

## Deliverables

- 1024×1024 master, plus the icon shown at 512, 128, 32 and 16 px so the small sizes can be judged.
- Two or three distinct directions before refining one.
- If layers are supported, keep the ink stroke on its own layer above the surface.
