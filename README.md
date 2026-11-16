# MGE: Mod Group Editor

A Toribash script for editing mods. The game's own editor changes one object at a time. MGE selects
many objects, players or joints and moves, rotates, scales or edits them together, with a gizmo in
the world and undo / redo.

Built for Toribash 5.76. Work in progress.

## Install

1. Download `mge.zip` and unzip it into Toribash's `data/script` folder. You get
   `data/script/mge/mge.lua` and `data/script/mge/mge/...`.
2. In game, load a mod, then type `/ls mge/mge.lua` in chat.

F1 hides or shows the window. Running `/ls mge/mge.lua` again shows the running window instead of
starting a second one.

## What it does

The window has five lists, each with its own tabs.

| List | Tabs |
|---|---|
| **Objects** | **Core**: position, rotation, scale, color, mass, shape, visibility, To atmo. **Advanced**: friction, bounce, flags, model. **Thrust**: frames, direction, axes. **Generate**: rows, rings and grids of new objects. |
| **Atmo** | **Core**: position, rotation, scale, color, shape, To objects, Save atmo. **Advanced**: depth, graphics levels, kept lines. **Generate**: as on Objects. |
| **Joints** | **Link**: the two objects a joint connects. **Properties**: position, axis, range, strength, velocity, type. |
| **Players** | Start position, rotation, scale and body parts of each player. |
| **Misc** | The mod's message, the atmo's shader, reindexing ids, map import. |

- Number fields apply what you type when you leave them (click elsewhere) or press Enter, then show the
  new value as their placeholder. Esc while typing drops it. The Generate tab's fields keep their text:
  Enter there generates.
- Click objects in the world to select them. Shift + click adds to the selection.
- The gizmo (Move, Rotate, Scale) works on everything selected. Hold Ctrl while dragging to snap
  (Ctrl + Shift: the fine step). The steps are in Settings > Snapping.
- **Export** saves the selected objects (or a player's model) as an asset. **Import** adds one in
  front of the camera. Assets live in `mge/mge/assets/obj` and `mge/mge/assets/player`, and a few
  examples come with the download.
- **Settings** (UI size, camera follow, snapping steps, max atmo objects) and the color picker's saved colors
  are kept in `mge/mge/config.cfg`, so they stay between game sessions and over updates.
- **Save** writes the mod to `data/mod/modmaker/`. While you edit, MGE reloads a working copy
  (`mge-modmaker.tbm` / `mge-modmaker1.tbm`) so changes show in the game straight away.

### Map import (experimental)

Misc list → **Convert map** turns a Hammer `.vmf` or a compiled Source `.bsp` (CS:S, CS:GO, TF2,
HL2, Garry's Mod) into static boxes. Put maps in `mge/mge/assets/maps`. You pick the part of the map
to convert and where it goes in the world, then Convert adds the boxes. A mod holds 256 objects, so
pick a region (one bombsite, not a whole map).

### Atmo: scenery beyond 256 objects (experimental)

A mod holds 256 objects. Scenery beyond that goes in the mod's **atmo**: objects the game draws without
collisions. Players load an atmo themselves (main menu → Shaders & Atmos → Atmos); it doesn't come with
the mod.

- **The Atmo list** (next to Objects) shows the atmo objects as A1, A2… with the same grid and bottom bar:
  - **New** adds a box in front of the camera, **Duplicate** and **Delete** work on the selected ones.
  - **Import** reads an `.atmo` from `assets/atmo` or `data/atmospheres` (the game's atmos and your own)
    and adds its objects where the file has them. **Export** writes the selected ones to `assets/atmo`.
  - On this list the atmo objects are drawn in their own color and the mod's objects turn see-through.
- **Editing:** the **Core** tab is the objects' Core tab (Pos, Rot, Scale, Color, Shape), on the selected
  atmo objects. The gizmo, clicks and Shift + drag work the same. Its last row has **To objects** and **Save atmo**.
  The **Advanced** tab has what only atmos have: **Depth** (drawn on top), **Graphics** (the graphics levels
  it shows at) and the lines MGE keeps without editing them. The **Generate** tab works as on Objects, and its pieces
  go to the atmo (no joints field there: atmos have none).
- **To atmo** (Objects → Core) moves the selected objects into the atmo and frees their ids. **To
  objects** moves atmo objects back while there are free ids. Objects joined by a joint stay.
- **Saving:** Save keeps the atmo in `data/atmospheres/MGE - <mod>.atmo`, next to the mod, and opening the
  mod reads it back. Save writes that file only when the atmo changed. If you remove every atmo object,
  Save asks before emptying the file. Scripts can't delete files, so delete it by hand if you don't want it.
  **Save atmo** writes it without saving the mod.
- **The game's own atmo** is unloaded when MGE starts, so the saved copy loaded in game doesn't show on
  top of the one you're editing. Your default atmo setting isn't changed.
- **Drawing:** the game draws only so many shapes per frame, and how many depends on its graphics settings.
  MGE draws every atmo object: in color on the Atmo list, as faint ghosts on the Objects list. The atmo
  holds 256 by default, which leaves room for the mod's 256 objects and 256 more shapes (outlines, the
  Generate preview, which is always drawn first). **Settings → Max atmo objects** raises it. Above 256
  you may need lower graphics settings to see them all. On the Atmo list the selected atmo objects show in
  the highlight color (no extra shape each), so every selected one shows however many there are.
- **Convert map** has two budgets: **Budget** is how many boxes become objects (up to the free ids),
  **Atmo** is how many more go to the atmo (the smaller boxes). Budget 0 puts every box in the atmo and
  leaves the object ids free. The placement view draws those boxes in purple.

## Keyboard shortcuts

| Keys | Action |
|---|---|
| F1 | Hide / show the window |
| Alt + Q / W / E | Move / Rotate / Scale tool (press again to turn it off) |
| Shift + Z / Shift + Y | Undo / redo |
| Ctrl + S | Save |
| Ctrl + Shift + S | Save under another name |
| Ctrl + A | Select / deselect all (objects, atmo objects, players or joints, whichever list is shown) |
| Ctrl + N / Ctrl + D | New / duplicate (an object, atmo object, player or joint, on the shown list) |
| Delete | Delete the selection on the shown list (asks first) |
| Shift + drag | Box select: adds what the box shows (the front ones) |
| Ctrl + Shift + drag | Box select through: adds everything inside the box, hidden ones too (fast on big atmos) |
| Mouse wheel over a number field | +0.5 up, -0.5 down (Shift: 0.05; Rot fields: 15 degrees, Shift: 1; whole-number fields like Frames or Amount: 1), from the typed number or the current value, applied right away. Steps in Settings > Snapping, shared with the gizmo's Ctrl snap. One undo step until the mouse leaves the field. On the Generate tab it only changes the field |
| Esc | Close the open popup, prompt or overlay |

Ctrl + Z / Y are taken by the game, so undo and redo use Shift.

## Limits

These come from the game:

- 256 objects in a mod. Only ids 1-48 can move, ids above 48 are static.
- 24 joints, and a joint can only link objects with ids 1-48. Linking a higher one reindexes it down.
- Objects never get a zero-sized side, since that breaks the physics.

## Development

- The code is Lua 5.1 (the game's version). Each module registers itself on the global `MGE` table,
  see `mge/main.lua`.
- Tests: `lua5.1 mge/tests/run.lua` checks file parsing, the matrix math and the map converter,
  without the game. Everything else is checked in game.
- Release zip: `powershell -ExecutionPolicy Bypass -File mge/tools/package.ps1` runs the tests and
  writes `data/script/mge.zip`.
- The map importer's design notes and status are in `docs/map-import-plan.md`.

## License

MIT, see [LICENSE](LICENSE).
