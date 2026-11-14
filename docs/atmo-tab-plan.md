# Atmo tab plan (parked objects → their own layer)

Status (2026-11-14): **Phases 1–4 built and offline-tested, not tried in game yet** (Phase 4 partly:
see below). Phase 0 is done, and the rotation bug it found is fixed (see Phase 0 answer 1). Next: the
in-game checks below, then the rest of Phase 5.

## Phase 5 so far (2026-11-14)

- **Generate into atmo:** the Atmo list has the Generate tab too (the same panel). Its pieces are
  atmo objects with the default object's look lines, added through `Assets.addAtmo` (one undo step,
  room checked). The Amount row is rebuilt per list: the Atmo list's has no joints field.
- **"Park" renamed to "atmo" everywhere:**
  - `utils/parking.lua` is now `utils/atmo_layer.lua` (`MGE.AtmoLayer`), and `tests/test_parking.lua` is
    now `tests/test_atmo_layer.lua`.
  - `ModData.parsed.parked` is now `.atmo`. `park` / `unpark` are now `moveIn` / `moveOut`, and
    `maxParked` is now `maxAtmo`.
  - The map converter's budget field is now **Atmo**, and the messages and comments were reworded.
- **The game's loaded atmo is unloaded** (`AtmoLayer.unloadGameAtmo`):
  - When it runs: once, when MGE starts. Doing it on every add too was dropped (user, 2026-11-14).
  - Why: a loaded `MGE - <mod>.atmo` would show every object twice.
  - How: it calls the game manager's `Atmospheres.Unload`, only when `_ATMO` says one is loaded, so the
    shader isn't reset for nothing.
  - `atmo.cfg` (the player's default) isn't touched.
- **Every atmo object is drawn** (user, 2026-11-14):
  - Why: the budget is now split 256 objects, 256 atmo (`maxAtmo`) and 256 for the rest, so there's
    nothing to ration.
  - Removed: the nearest-first sort in `utils/highlight.lua`, `drawLimit` / `atmoDrawLimit`, and
    Settings' Ghosts drawn.
  - Above 256 (Most atmo objects) it's the player's call, with lower graphics settings.
- **Still to do:** custom-model atmo objects, the optional Preview in game.

## Phases 2–4 as built (2026-11-14)

- **One edit path (D3, `utils/transforms.lua`):**
  - Atmo objects have `kind = "atmo"` (`AtmoLayer.isAtmo` checks it). For them every transform reads
    and writes their lines only. `inWorld` is false, the pos / sides / shape reads come from their lines,
    every `set_obj_*` is skipped, and joints only see objects.
  - The rows, the gizmo, camera framing (`Camera.bounds`) and the selection pivot all use this path.
    `ModData.getEditSelection()` returns the selected atmo objects while the Atmo list shows.
  - Tested: an atmo object with the **same id** as a game object gets the same `pos` / `rot` / `sides`
    lines as that object through move, rotate and scale (boxes, spheres, pills), with zero `set_obj_*`
    calls. `AtmoLayer.moveBy` / `rotateBy` / `scaleBy` stay only for drawing a gizmo drag's preview, and
    are tested equal.
- **The Atmo list (`ui/main.lua`, `ui/obj_selector.lua`):**
  - A list tab after Objects, cells A1, A2…, its own Select all, pages and keys (Ctrl + A / N / D,
    Delete).
  - Bottom bar: New (a default box in view), Duplicate (new names, same lines), Import (an `.atmo`
    from `assets/atmo` or `data/atmospheres`, switchable roots in the file picker; the file's header
    is taken when the atmo has none), Export (the selected ones to `assets/atmo/<name>.atmo`), Delete.
  - Atmo changes are an undo step and a list refresh, no reload.
  - The Objects list no longer lists atmo objects.
- **Editor tabs on the Atmo list:**
  - **Core:** the objects' Core panel on the atmo selection, without Mass and Visible.
  - **Atmo** (`ui/editor_atmo.lua`):
    - Depth: Normal / On top (`no_depth 1`).
    - Graphics: min / max level, the defaults 0 / 2 not written.
    - Kept: the lines MGE keeps without editing them.
    - To objects and Save atmo.
  - **Objects → Advanced:** the old Park / Unpark / Export atmo row is now "Atmo: To atmo", which moves
    the selection and shows the Atmo list.
- **World:**
  - Clicks and Shift + drag pick atmo objects on the Objects and Atmo lists.
  - A ghost clicked from Objects switches to Atmo with only it selected, and an object clicked on Atmo
    switches back. A box selects only the shown list's kind.
- **Drawing (D5):**
  - On the Atmo list, atmo objects are drawn in their own color, selected ones with the highlight's
    outline. Every one is drawn (see Phase 5: the nearest-first limit was dropped).
  - The mod's objects go see-through: their alpha is set live to `AtmoLayer.seeThroughAlpha`, put back on
    leaving the list or quitting, and applied again after a reload.
  - The Objects list draws atmo objects as plain ghosts.
- **Limits (D6):** Most atmo objects defaults to 256 (Settings "Atmo objects" section).
- **Assets:** `mge/assets/atmo/pillars.atmo`, a sample shipped with the release
  (`tools/package.ps1`), also creates the folder Export writes to. Scripts can't create folders.
- **In-game checks for Phases 2–4:**
  1. The Atmo list: New, select, then the Core rows and the gizmo move / rotate / scale it. Undo.
  2. Import `pillars.atmo` (`assets/atmo`) and an atmo from `data/atmospheres`. Export a selection.
  3. On the Atmo list the objects are see-through (`set_obj_color` alpha: Phase 0 answer 2). Back on
     Objects they're as before, and also after a save or reload.
  4. Clicks: a ghost from Objects opens Atmo, an object from Atmo opens Objects. Shift + drag on both.
  5. To atmo / To objects, then Save, and load the atmo in the main menu.
- **Not done yet:** Phase 5 (Generate into atmo, the map converter's wording, custom models,
  Preview in game).

## Phase 1 as built (2026-11-14)

- **`utils/atmo.lua`:** the `.atmo` reader and writer, Save's decision, the per-mod file name.
  - It keeps every line of an object in order, the object's name, the file's own lines (`shader`,
    `opt`...) and `player` sections. `size` is read as `sides` and written back as `size`. `rot` is
    unchanged.
  - Offline, all 37 atmos in `data/atmospheres` (the game's 34 and 3 of MGE's) read and write back
    with every line the game reads (`tests/test_atmo.lua`).
- **`.tbm` files never hold parked objects** (`utils/file_handler.lua`). The old `#mge parked` comment
  format is gone, read and write: MGE wasn't released with it (the user, 2026-11-14).
- **How the layer lives** (`ModData.parsed.atmo`):
  - Reloads, MGE's own and the game's, keep it in memory (`ModData.reloadObjects`). The working copy
    doesn't carry it.
  - A script restart takes it from the global `MGE_ATMO`.
  - Opening a mod reads its `MGE - <mod>.atmo` (`Atmo.load`).
- **Save** (`writeMod`) calls `Atmo.saveFor`. It writes when the layer's text differs from the last
  one read or written, or when the mod was saved under a new name.
- **An emptied layer:** Save asks, then **empties** the file. Scripts can't delete files: `os.remove`
  didn't work in game (the user, 2026-11-14), and the game has no delete for atmos. An empty atmo loads
  nothing. Chat says the file can be deleted by hand.
- **Unsaved changes** count the atmo layer too (`MGE.hasUnsavedChanges`, the footer).
- **Export atmo** writes the layer file now, without saving the mod.
- **Objects entering the layer** (Park, imports and conversions over the free ids) get their color
  limited to 0–2 (`Atmo.fromMod`), because above 2 the game reads atmo colors as 0–256. Their other
  lines stay: the game skips the ones atmos don't have.
- **Known change:** an object with `visible 0` is kept in the atmo file, and the game's atmo loader
  doesn't read `visible`, so the game draws it. The old export left such objects out.
- **In-game checks for Phase 1:**
  1. Park something and Save: the `.atmo` is written, and the `.tbm` has no `#mge` lines.
  2. Save again without changes: the `.atmo` isn't written again (no "saved data/atmospheres/..." line).
  3. Restart the script and reload: the atmo layer is still there.
  4. Delete all parked objects, then Save: it asks, and Enter empties the file.

## Answers (the user, 2026-11-14)

1. **Storage:** a separate `.atmo` per mod, **written only when the atmo layer changed** since it was
   last read or written (D1).
2. **Pieces:** Export writes to `mge/mge/assets/atmo/`. Import offers two root folders to pick from:
   `mge/mge/assets/atmo/` and `data/atmospheres/` (the game's atmos and the players' own, read only).
3. **Ghosting:** the mod's objects turn see-through on the Atmo tab (D5).
4. **Preview in game:** check whether a script can load an atmo, and whether that's more efficient.
   Checked offline, see "Loading an atmo from a script" below: it can, but it isn't more efficient.
5. **An emptied atmo layer:** when a mod with an `MGE - <mod>.atmo` is saved with no atmo objects left,
   Save asks, then deletes the file (MGE's confirmation popup: Enter deletes, Esc keeps the file).
   **Changed (2026-11-14):** scripts can't delete files (tried in game), so Enter empties it instead.

## Loading an atmo from a script (checked in the game's code, 2026-11-14)

- **Scripts can call it.** `Atmospheres` is a global, loaded by the main menu
  (`system/menu_main.lua` requires `system.atmospheres_manager`). The game's own tutorial calls
  `Atmospheres.LoadAtmo` from a script. Paths starting with `../` load from `data/`, so a script could
  load a file anywhere under `data/`.
- **It isn't more efficient.** `LoadAtmo` makes one `UIElement3D` per object. Every frame
  `UIElement3D.drawVisuals` draws each of them with the same `draw_box_m` / `draw_sphere_m` /
  `draw_capsule_m` calls MGE uses, with no culling, plus the UI framework's per-object work. So it uses
  the same drawing budget as MGE's own drawing and costs more CPU.
- **It changes the player's setup.** `LoadAtmo` first unloads the atmo the player has on, and can
  change shader options and game options (`opt` lines). Afterwards MGE would have to put the player's
  own atmo back (`Atmospheres.LoadDefaultAtmo`).
- **What it's good for:** showing exactly what players will see, including the extras MGE only keeps:
  graphics levels, `count` with random copies, `rotate` / `move` animation, and the file's shader.
- **So:** editing stays on MGE's own drawing. A **Preview in game** toggle could come in Phase 5, for
  checking those extras. It would turn off by itself on leaving the Atmo tab or quitting, and put the
  player's atmo back.

## Phase 0 answers (the user, 2026-11-14)

1. **Rotation: measured in game, ghosts and export fixed (2026-11-14).**
   - **What the user saw:** a box with `rot 10 -20 30`, parked and exported. The exported atmo matched
     the ghost, but both were turned differently from the original object.
   - **Measured with `mge/tools/rotcheck.lua`:** `get_obj_rot` for that box is exactly
     **rotX(-x) rotY(-y) rotZ(-z)** of its rot line, read the way `draw_box_m` takes it (r0 r1 r2 the
     first row). That's `Transforms.orientationOf`, not transposed. The selection highlights, drawn
     straight from `get_obj_rot`, sat right on the objects.
   - **Fixed in `utils/atmo_layer.lua`:**
     - `AtmoLayer.frameOf` (ghost drawing and picking) is now rotX(-x) rotY(-y) rotZ(-z). The original
       rotX(x) rotY(y) rotZ(z) had the opposite sign, so it was wrong even for one-axis turns. A first
       "fix" the same day, rotZ(z) rotY(y) rotX(x), was its transpose and also wrong.
     - **The export writes the rot line unchanged** (`AtmoLayer.atmoRot`). The game's atmo loader turns
       atmo angles e into rotX(-e1) rotY(-e2) rotZ(-e3) (checked by running toriui's `UIElement3D`
       offline), which is the same as for an object. The old export negated the angles.
     - Tests (`test_atmo_layer.lua`): "ghost rotation is the game's" (against the measured matrix and the
       transform code's orientation), "atmo rot is the mod file's", and "atmo rotation matches the mod
       file" (through the game's own atmo loader math).
   - **Confirmed in game by the user (2026-11-14):** the ghost and the exported atmo now sit exactly on
     the original. The check script was deleted afterwards. Atmos exported before 2026-11-14 with
     turned objects need re-exporting.
   - **Phase 1's atmo reader** reads rot unchanged too.
2. **Live transparency:** expected to work (`set_obj_color` with a low alpha). It gets confirmed in
   game when Phase 4 builds it. If it doesn't work, objects on the Atmo tab stay as they are.
3. **Drawing room:** the counts fit the original budget of 256 game objects + 512 drawn shapes:
   - 256 game objects (the game draws those itself)
   - up to 256 atmo objects drawn by MGE
   - 256 shapes left for everything else MGE draws (selection outlines, the Generate preview, the
     gizmo, ghosts)

## Idea (the user's, 2026-11-14)

Parked objects are already objects with fewer properties, but they're handled as a special case of
objects: comments inside the mod file, P cells at the end of the Objects list, Park / Unpark / Export
atmo buttons on the Advanced tab, and a separate code path for each edit. Replace that with an **Atmo
list tab** next to Objects / Joints / Players:

- The same grid list as Objects, showing the atmo objects.
- The same bottom bar. New, Duplicate, Select all and Delete work the same way. **Import** loads a
  `.atmo` file, **Export** writes one.
- The editor tabs show only the inputs that apply to atmo objects.
- On this tab the atmo objects are drawn in full color and the mod's objects become ghosts.
  The Objects tab does the reverse.
- Most atmo objects: **256 by default**. That leaves room for 256 more drawn shapes, which should be safe
  on any graphics setting.
- Consider an asset folder of its own for atmos, so atmo objects no longer live as comments in the mod.

## What we know (checked in this install)

- **The game's atmo loader** is `Atmospheres.ParseFile` in `system/atmospheres_manager.lua`.
  - Per object it reads `shape` (box / cube, sphere, cylinder / capsule, `custom <model>`), `pos`, `rot`,
    `size` or `sides`, and `color`. Colors above 2 count as 0–256.
  - It also reads `parent`, `rotate` / `move` (animation), `count` with `randompos` / `randomsize` /
    `randomcolor` and their `_precision` lines, `no_depth 1`, `min_level` / `max_level` (graphics
    levels 0–2), `queue_player`, and `drawfunc` / `framefunc`, which name functions in a sidecar
    `<name>.lua`.
  - File-level lines: `shader`, `shaderopt`, `opt`.
  - `player N` sections are skipped.
- **The game's 34 atmos** use 2733 `env_obj` blocks in all. Nearly every object has only
  `shape pos rot size color`. Only about 60 objects use `no_depth`, levels, functions or `count`.
- **Sizes:** spheres and capsules use the same order as mod files (x radius, y length). This was
  checked in `toriui/uielement3d.lua`: `drawCapsule` passes `size.y, size.x` to `draw_capsule_m`.
- **Rotation:** the game reads an atmo's `rot` the same way as a mod file's (measured in game
  2026-11-14, Phase 0 answer 1), so the angles carry over unchanged. MGE's old export negated them,
  which was wrong.
- **Atmos are client-side.** Each player loads an atmo themselves, and other players never see one
  through the mod. So keeping atmo objects inside the `.tbm` gains nothing in multiplayer.
- **Drawing limit:** how many shapes the game draws per frame depends on its graphics setting. On the
  lowest setting, 10 000 ghosts drew. The Generate preview is drawn first already, and the ghost and
  park limits are in Settings (2026-11-14).
- **MGE today:**
  - `utils/atmo_layer.lua` holds park / unpark, the atmo export, ghost drawing data, and parked move /
    rotate / scale.
  - The gizmo and world clicks support parked objects. Parked P5 shares its id with game object 5,
    so `AtmoLayer.isAtmo` tells them apart by membership in the parked list.
  - The editor rows (Pos, Rot, Scale, Color, Shape…) read and write the live game object: there are
    17 `get_obj_*` / `set_obj_*` calls in `ui/`. Parked objects can't use them.
- **The game can load an atmosphere itself:** `Atmospheres.LoadAtmo(filename)`, and scripts can call
  it. It draws through the same calls as MGE, so it uses the same budget. See "Loading an atmo from a
  script".

## Decisions (recommended, the user to confirm)

### D1. Storage: each mod's atmo is a real `.atmo` file, not comments in the mod

The working file is `data/atmospheres/MGE - <mod>.atmo`. Opening a mod reads it. Save writes it
alongside the `.tbm`, but **only when the atmo layer changed** since it was last read or written.

- **Changed means:** an atmo edit, import, delete, To atmo / To objects, or an undo / redo that changes
  the atmo layer.
- **How to tell:** compare the layer with the copy taken when the file was last read or written. History
  already keeps copies, so this is a list compare, not a flag every edit has to remember to set.
- **Saving a mod with no atmo objects** writes no file. If an `MGE - <mod>.atmo` already exists and the
  layer was emptied, Save asks, then empties the file (answer 5: scripts can't delete files).

Why:

- **The mod file stays small.** Every MGE save reloads the `.tbm`. 10 000 parked objects are about
  60 000 comment lines that the game has to read on every save.
- **No separate export step.** The file is already where the game's atmo menu lists it.
- **Atmos are client-side anyway** (see above).
- **No `#mge` comment format** to keep compatible.

What it costs:

- Two files per mod: sharing a mod with its atmo means sending both.
- Save as (rename) has to rename or copy the atmo file too.

The old `#mge parked` comment format isn't read at all: MGE wasn't released with it.

**Asset library:** `mge/mge/assets/atmo/` holds reusable pieces, as `assets/obj` does for objects.
Export writes the selected atmo objects there. Import offers two root folders: `assets/atmo` and
`data/atmospheres`. The second covers the game's atmos and the players' own. Importing copies the
objects; MGE never writes into `data/atmospheres` except the mod's own `MGE - <mod>.atmo`.

Alternative: keep the comments. That's one file per mod, but it keeps every cost listed above.

### D2. In memory, atmo objects are kept the way MGE keeps objects

- **Kind:** atmo objects get `kind = "atmo"`, which replaces the `isAtmo` membership check. History
  copies the kind, so undo keeps it.
- **Rotation:** `rot` is stored the way mod files keep it, so the transform math stays the same. It's
  written to and read from `.atmo` files unchanged (`AtmoLayer.atmoRot`).
- **Size:** stored in the `sides` line and written as `size`, like the game's own atmos.
- **Lines MGE doesn't edit** are kept as they are and written back unchanged: `count`, `random*`,
  `rotate`, `move`, `parent`, `drawfunc` and `framefunc`. So does the file header (`shader`, `opt`,
  `shaderopt`). Importing a game atmo and saving it loses nothing.
  - MGE draws such objects as their base shape. A `count` object is one shape at its base position.
- **Sidecar `.lua` files** are never written. If an imported atmo has one, MGE copies it unchanged when
  it writes that atmo.

### D3. One edit path for objects and atmo objects

Change `utils/transforms.lua` so every function works on lines only when the object isn't in the
world:

- **Detection:** `inWorld(obj)` is false for `kind == "atmo"`. That also guards against the id clash
  for good.
- **Reading values:** positions, sizes and shapes come from the `pos` / `sides` / `shape` lines
  instead of the game.
- **Writing:** `set_obj_*` is skipped.

The editor rows, the gizmo and the measured rows (Pos, Rot, Scale placeholders) then work on atmo
objects without a second copy of the math. `AtmoLayer.moveBy` / `rotateBy` / `scaleBy` are removed. The
current tests already compare the parked math with the object math, and they become tests of the
lines-only path.

### D4. Moving objects between the layers

**To atmo** (Objects tab) and **To objects** (Atmo tab) replace Park and Unpark. They keep the same
rules:

- Objects joined by joints stay.
- To objects only goes as far as there are free ids.
- Both are one undo step.

### D5. Drawing

- **Atmo tab:**
  - Atmo objects are drawn in their own color: selected ones with the highlight outline, the rest
    filled. Most atmo objects is 256 by default, so normally all of them are drawn.
  - The mod's objects are ghosted. The preferred way is the game drawing them translucent: their alpha
    set live only, and put back when leaving the tab, saving or quitting. That costs MGE no draws.
    It's expected to work and gets confirmed in game in Phase 4.
- **Objects tab:** atmo objects are drawn as ghosts, as parked objects are now. The nearest
  **Ghosts drawn** of them (Settings), and selected ones always.
- **Editing uses MGE's own drawing.** Loading the atmo through the game uses the same budget and more
  CPU (see "Loading an atmo from a script"). A Preview in game toggle, only for checking the extras MGE
  doesn't show, can come in Phase 5.

### D6. Limits

**Most atmo objects** (today's **Most parked**) defaults to 256, and Settings can raise it. The map
converter's **Parked** budget becomes **Atmo**.

## Atmo tab: what's on it

| Part | Objects tab | Atmo tab |
|---|---|---|
| List | ids 1…256 | A1, A2… (atmo objects), same grid, pages and Ctrl + A |
| New | default object in view | default atmo box in view |
| Duplicate / Delete | objects | atmo objects (Delete asks first, Enter / Esc) |
| Import | `assets/obj/*.tbm` | `.atmo` files from `assets/atmo` or `data/atmospheres` (two root folders), keeping their positions |
| Export | selected → `assets/obj` | selected → `assets/atmo` |
| Core tab | Move / Rotate / Resize, Pos / Rot / Scale, Color, Shape, Visible, … | the same transform rows, Color, Shape (Box / Sphere / Pill) |
| Advanced tab | Flags, Model, Ids, Map, (Parked) | an **Atmo** panel: Depth (`no_depth`), Shown at graphics (min / max level), "N lines kept" (the unedited extras), **To objects** |
| Thrust | yes | not shown |
| Generate | yes | later: Generate into atmo (Phase 5) |
| World click / Shift + drag | objects (ghosts of atmo objects too) | atmo objects. A click on an object switches to Objects, as other lists do now |

## Phases

| # | Work | Done when |
|---|---|---|
| 0 | In-game checks | ✅ done 2026-11-14. The rotation bug it found is fixed (Phase 0 answer 1) |
| 1 ✅ offline | **Data:** `utils/atmo.lua` replaces `parking.lua` for data and files. `.atmo` reader and writer keep unknown lines and the header. Rotations carried over unchanged (`AtmoLayer.atmoRot`). Save / open / rename of the mod's atmo file, written only when the layer changed. Undo. | offline: every game atmo reads and writes back with the same objects and lines. A save writes the `.atmo` and no `#mge` lines in the `.tbm`. A save with an unchanged layer doesn't write the `.atmo`. |
| 2 ✅ offline | **Edit path (D3):** `transforms.lua` lines-only for `kind == "atmo"`. Editor rows read lines. Gizmo, click and box select use the same path. The `AtmoLayer.*By` copies are removed. | offline: move / rotate / scale through the rows and through the gizmo give the same lines for an object and an atmo object. In game: rows and gizmo edit atmo objects. |
| 3 ✅ offline | **Atmo tab UI:** list tab, grid, bottom bar (Import / Export of `.atmo`), Core subset, Atmo panel, To objects / To atmo. The Advanced Parked row is removed. | in game: import a game atmo, edit it, save, load it from the game's atmo menu, and it looks the same |
| 4 ✅ offline | **Drawing (D5):** tab-dependent ghosting (objects see-through on the Atmo tab), the limits. | in game: 256 atmo + 256 objects draw on the lowest and highest graphics settings, with the Generate preview still visible |
| 5 | **Extras:** Generate into atmo, map conversion's Atmo budget wording, custom-model atmo objects (`shape custom`) shown as their model, optional Preview in game toggle. | per feature |

## In-game checks (Phase 0)

1. Rotation: measured in game, ghosts and export fixed (Phase 0 answer 1).
2. Live transparency: expected to work, confirmed in Phase 4.
3. Drawing room: 256 + 256 + 256 fits the budget.

## Testing

- **Offline (`mge/tests/`):**
  - Read and write back all 34 game atmos: same objects, same unedited lines, the same `rot` after a
    read and a write (the conversion and its inverse cancel out).
  - The rotation conversion against the game's own `UIElement3D` code (as the offline check on
    2026-11-14 did): the atmo object comes out turned like the game object.
  - Migrating old parked comments.
  - The lines-only transform path gives the same lines as the world path (today's parked tests,
    moved over).
  - Save / rename keeps the `.tbm` and the `.atmo` together.
  - Save writes the `.atmo` only when the layer changed, including after an undo that changed it.
- **In game:** the Phase 3 and Phase 4 checks above.

## Risks

- **Atmos exported before 2026-11-14** have every turned object turned wrong: the old export negated
  the angles. Re-exporting fixes them. Phase 1's reader reads `rot` unchanged, so an old file shows
  those objects turned the same wrong way as the game does.
- **Live transparency** isn't confirmed in game yet (Phase 0 answer 2). If `set_obj_color` alpha
  doesn't make objects see-through, the Atmo tab leaves them as they are.
- **Two files per mod.** A user may move or rename one of them outside MGE. Opening the mod then shows
  an empty atmo layer and says that no `MGE - <mod>.atmo` was found. Nothing is deleted.
- **Game atmos are read-only.** Importing one copies its objects. MGE never writes to a file without
  the `MGE - ` prefix.
- **Lines MGE doesn't understand** (random, animation, functions) are kept but not shown as the game
  shows them. The Atmo panel says how many lines each selected object keeps.

