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

The window has three lists, each with its own tabs.

| List | Tabs |
|---|---|
| **Objects** | **Core**: position, rotation, scale, color, mass, shape, visibility. **Advanced**: friction, bounce, flags, model, reindexing ids, map import, parked objects. **Thrust**: frames, direction, axes. **Generate**: rows, rings and grids of new objects. |
| **Joints** | **Link**: the two objects a joint connects. **Properties**: position, axis, range, strength, velocity, type. |
| **Players** | Start position, rotation, scale and body parts of each player. |

- Click objects in the world to select them. Shift + click adds to the selection.
- The gizmo (Move, Rotate, Scale) works on everything selected. Hold Ctrl while dragging to snap. The
  snap steps are in Settings.
- **Export** saves the selected objects (or a player's model) as an asset. **Import** adds one in
  front of the camera. Assets live in `mge/mge/assets/obj` and `mge/mge/assets/player`, and a few
  examples come with the download.
- **Save** writes the mod to `data/mod/modmaker/`. While you edit, MGE reloads a working copy
  (`mge-modmaker.tbm` / `mge-modmaker1.tbm`) so changes show in the game straight away.

### Map import (experimental)

Advanced tab → **Convert map** turns a Hammer `.vmf` or a compiled Source `.bsp` (CS:S, CS:GO, TF2,
HL2, Garry's Mod) into static boxes. Put maps in `mge/mge/assets/maps`. You pick the part of the map
to convert and where it goes in the world, then Convert adds the boxes. A mod holds 256 objects, so
pick a region (one bombsite, not a whole map).

The same converter runs outside the game:

```
lua5.1 mge/tools/mapconv.lua <map.vmf|map.bsp> [options]
```

`--help` lists the options. The result goes to `assets/obj`, and Import keeps its position.

### Parked objects and atmospheres (experimental)

A mod holds 256 objects. To build scenery beyond that, park objects: Advanced tab → **Park** takes the
selected objects out of the game and frees their ids. Parked objects stay in the mod file as comments
the game skips, and MGE draws them faint. They're listed after the objects as P1, P2…

- **Unpark** brings selected parked objects back while there are free ids. To edit a parked object,
  unpark it, edit, and park it again. Objects joined by a joint can't be parked.
- **Convert map** has two budgets: **Budget** is how many boxes become objects (up to the free ids),
  **Parked** is how many more get parked (the smaller boxes), up to 512 parked in all. Budget 0 parks
  every box and leaves the object ids free. The placement view draws parked boxes in purple.
- **Export atmo** writes the parked objects to `data/atmospheres/MGE - <mod>.atmo`. The game draws
  atmosphere objects but they don't collide. Players load the atmosphere themselves (main menu → Shaders &
  Atmos → Atmos); it doesn't come with the mod.

## Keyboard shortcuts

| Keys | Action |
|---|---|
| F1 | Hide / show the window |
| Shift + Q / W / E | Move / Rotate / Scale tool (press again to turn it off) |
| Shift + Z / Shift + Y | Undo / redo |
| Ctrl + S | Save |
| Ctrl + Shift + S | Save under another name |
| Ctrl + A | Select / deselect all (objects, players or joints, whichever list is shown) |
| Ctrl + N / Ctrl + D | New / duplicate (an object, player or joint, on the shown list) |
| Delete | Delete the selection on the shown list (asks first) |
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
