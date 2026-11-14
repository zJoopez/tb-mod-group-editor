# Map import plan (brush maps → Toribash mod)

Status (2026-11-12): **Phase 0 answered. Phases 1 and 4 and the `.bsp` reader are built and offline-tested, but none has been tried in game yet.** Phase 1 is the converter and command-line tool. Phase 4 is the in-game Advanced tab → Map → Convert map overlay. The `.bsp` reader handles compiled Source maps (CS:S, CS:GO, TF2...) without a decompiler. Next step: convert `mapconv_test.vmf` and `tf2_test2.bsp` (both in `mge/mge/assets/maps/`) in game and walk on them, then dust2 from CS:GO Legacy.

Update (2026-11-13, after the user's in-game testing): **props, the ledge-shell join, see-through red clips and the overlay's Nogrip toggle were removed.** Clips are now always colored like the geometry they cover. The props code (`mapconv/props.lua`: static props, `.vpk` / packed-zip model reading, the `.models` cache) is in git history at commit `de2ce06`. The sections below keep their measurements, marked where a feature is gone. The `.models` files in `assets/maps` aren't read any more and can be deleted.

Goal: a community tool that turns a brush-based level from another game (Source `.vmf`, later Quake-family `.map`) into:

1. **Collision**: up to ~250 static `env_obj` boxes, imported through MGE like any asset and fine-tuned by hand.
2. **Visuals**: one or a few `.obj` models (+ one `.tga` each) in `data/mod_assets`, carried by invisible static objects.

We ship only the converter, never converted maps. Users run it on files they have.

---

## What we know (checked in this install)

| Fact | Where |
|---|---|
| A mod holds at most 256 objects. Ids 1-48 are for dynamic/joint objects, and static objects prefer 49-256 but fall back to low ids. | [mge/utils/mod_export.lua](../mge/utils/mod_export.lua) `MAX_ENV_OBJECTS`, `allocateIds` |
| Collision shapes are only box, sphere and capsule. | `SHAPE` enum, same file |
| A model is one `NAME.obj` plus one `NAME.tga` with the same name. No `.mtl` is shipped, so **there is one texture per model**. | `data/mod_assets/Noki/bowling.*` |
| A big model works: `bowling.obj` has about 6k faces, quads included, and its 2048² RLE TGA is 8.7 MB. | same |
| The carrier pattern: `Bowling_Noki.tbm` env_obj 1 is a `box`, `visible 0`, `flag 24` (static + ungrippable), `sides 1 1 1`, `use_model 1`, `model_name ../Noki/bowling`. Its model is about 40 units across in world units. | `data/mod/Bowling_Noki.tbm` |
| The model **seems to scale by the object's sides**. The PinTori model is ±0.6 wide, but its objects are 0.2 × 0.2 × 0.75 and pins look pin-sized. This needs confirming in game. | `mge/assets/obj/pins.tbm` |
| `model_name` is relative to `mod_assets/<mod name>/`, so `../Folder/name` points to `mod_assets/Folder/name.obj`. | `ModData.toModelName` |
| MGE's Import (`assets.lua: importAssetFromFile`) always **moves objects in front of the camera** (`inView = true`). A map needs to keep its positions. | [mge/ui/assets.lua](../mge/ui/assets.lua) |
| Rotation output: `Mat3.toEulerXYZ` then `RotatingOld.SetRotOffset(0,0,0, …)` turns a matrix into a `rot` line, the same way the Generate tab does. Both are pure Lua. | [mge/utils/shape_gen.lua](../mge/utils/shape_gen.lua) |

## Phase 0 answers (from the user, 2026-11-12)

| Question | Answer | What it means |
|---|---|---|
| Does a model scale with its carrier's `sides`? | **Yes** | The carrier can use `sides 1 1 1` with the OBJ already scaled, or carry the scale itself. |
| How many faces can one model have? | **Make it a variable** | Phase 2 gets a `maxFacesPerModel` option to adjust from test results. |
| Can the ground at z=0 be removed? | **No** | The anchor decides what sits on the ground. The converter counts the boxes that end up under it and says so. |
| How tall is a tori, and so what scale? | **Make it a variable** | `--scale`, default `0.035`. Shipped mods put a standing tori's head at z≈2.2–2.65, so about 2.5 / 72. |
| Do physics, camera and drawing work 50-100 units out? | **Yes** | Full-size areas are fine. |

Still unchecked: whether an OBJ without `vt`/`vn` loads, what happens with a missing `.tga` (Phase 2), and performance with about 250 static rotated boxes (the first Phase 1 import will show this).

---

## Architecture

The core is pure Lua with no engine calls. Modules register on `MGE.MapConv` the way other MGE modules do, and they use `MGE.Mat3`, `MGE.FileHandler` and `mod_export.lua`'s constants. The command-line tool builds a stub `MGE` table and loads them with `dofile`, and Phase 4 can load them in game unchanged. The code runs on Lua 5.1 and 5.4.

```
mge/mge/mapconv/            core (built)
    vmf.lua                 KeyValues parser → MapFile { brushes (MapBrush: id, entity, sides), entities }
    bsp.lua                 Source .bsp v19-21 → the same MapFile: planes per side, role from contents flags,
                            entity per brush from each brush model's BSP tree, map.terrain = displacement count
                            (MapConv.parse(data, name) in convert.lua picks the reader)
    brush.lua               sides → MapGeometry (corners, faces + areas, volume, bounds); MapConv.Vec helpers
    boxfit.lua              geometry → MapBox (center, frame, sides, fitError, "box"|"slab")
    convert.lua             filtering, budget, region, anchor, yaw/scale, env_obj objects, text, report
    merge.lua               Phase 3: merge boxes with the same frame that share a face
    objwriter.lua           Phase 2: brush faces → OBJ (triangles, normals, palette UVs) + palette TGA
    quakemap.lua            Phase 5: Quake/Valve220 .map parser → same MapFile
mge/tools/mapconv.lua       command line front end (built)
mge/mge/ui/map_overlay.lua  in-game front end (built), opened by the Advanced tab's Map row
```

How to run it: `lua5.1 mge/tools/mapconv.lua map.vmf [--scale 0.035] [--budget 200] [--region x1 y1 z1 x2 y2 z2] [--anchor x y z] [--yaw deg] [--no-clips] [--ungrippable]`. `--help` lists every option. Output goes to `mge/mge/assets/obj/<map>.tbm` by default, which is where MGE's Import looks.

## Pipeline

1. **Parse.** VMF stores `world > solid > side { plane "(x y z) (x y z) (x y z)", material }` and the same structure under `entity > solid`. Turn the three points into a plane (Hammer winding gives the outward normal; the sign must be checked against a known box in tests). Keep `dispinfo` presence as a flag. Ignore `.bsp` and tell users to decompile it first with BSPSource.
2. **Filter.**
   - Drop: `TOOLS/TOOLSTRIGGER`, `TOOLSSKYBOX`, `TOOLSHINT`, `TOOLSSKIP`, `TOOLSAREAPORTAL`, `TOOLSOCCLUDER`, and the entities `trigger_*`, `func_buyzone`, `func_bomb_target`, `func_areaportal*`, `func_illusionary`.
   - Collision only, no visuals: `TOOLSNODRAW`, which is solid (visuals skip only those faces), and `TOOLSPLAYERCLIP`/`TOOLSCLIP`. Clips are optional and on by default because they are the map's invisible walls.
   - `prop_static` and other MDL models are not converted. List them in the report.
3. **Geometry.** Intersect every three planes. Keep a point if it lies inside all planes (eps about 0.01 Source units), then deduplicate. For each plane, collect its points and sort them by angle around their centroid to get the face polygon. Skip degenerate brushes (fewer than 4 points) and report them.
4. **Box fit.**
   - *Exact box*: 6 faces in 3 perpendicular, opposite pairs. Read the frame and sides straight from the faces. Most dust2 walls, floors and crates are this case.
   - *Wedge or ramp* (one sloped face): a thin box (default 0.2 tori units) placed under the sloped face. The slope is the surface that matters for walking.
   - *Other convex shapes*: try each face normal plus world Z as frame candidates and keep the smallest-volume OBB. Record `fitError = 1 - hullVolume / boxVolume`.
   - *Displacements* (terrain): use the base brush's box and warn. Phase 5 can fit thin boxes to patches.
5. **Merge.** Repeatedly join two boxes with the same frame (within about 0.5°) whose touching faces match exactly, because their union is a box. Remove boxes that sit fully inside another.
6. **Budget.**
   - `--region minx miny minz maxx maxy maxz` (Source units) crops to one area, such as B site.
   - Rank by largest face area, so floors and walls come first. Then keep the top N, where N is `--budget` (default 200) or MGE's free ids minus a reserve of about 16 in game.
   - The report lists everything dropped.
7. **Transform.**
   - Source and Toribash both use Z-up, right-handed axes, so only scale and translate are needed: `p' = (p - anchor) * scale + MGE.POS_ORIGIN`, with z shifted so the anchor's floor is at z=0.
   - The anchor is chosen with `--anchor x y z`, `--anchor info_player_terrorist` (the first entity of that class), or the region's center.
   - `--yaw` is optional, to turn the map.
8. **Write .tbm** to `mge/assets/obj/<map>.tbm`.
   - Each object: `shape box`, pos, rot (matrix → `SetRotOffset`), sides clamped to at least `MGE.MIN_SIDE`, `flag 8` (or `24` with `--ungrippable`), friction and bounce from the defaults, `visible 0` when a model is exported and `1` otherwise, and a color per material group.
   - The carrier object is written last, as in the Bowling mod. Put it under the anchor floor so nothing touches it.
9. **Write model** to `data/mod_assets/mapconv/<map>.obj` + `.tga`.
   - Faces of visible materials only, triangulated as fans, with per-face normals.
   - *Texture*: one TGA per model means real textures need an atlas built from VTF files. That is out of scope. Instead, write a small **palette TGA** (e.g. 64×64, 8×8 swatches) and point every face's UVs at the swatch for its material group. Groups come from keyword rules (`sand`, `stone`/`brick`, `wood`, `metal`, `plaster`, `tile`, default), and users can override them with a `material → color` file.
   - Users who want full textures can bake an atlas in Blender and replace the OBJ/TGA. Document this route.
   - Split into several models (each with its own carrier) only if Phase 0 shows a face limit.

## MGE changes needed

- ✅ **Import keeping positions.** The converter writes `#mge_keep_position` (`MGE.KEEP_POSITION_TAG`, in `mod_export.lua`) before the first object. `importAssetFromFile` sees it and imports without moving the objects in front of the camera.
- ✅ **Phase 4: Convert Map overlay** ([ui/map_overlay.lua](../mge/ui/map_overlay.lua)), opened by the Advanced tab's "Map" row.
  - The layout follows `settings_overlay.lua`.
  - The Map button opens `FilePicker` (`.vmf`, `mge/mge/assets/maps`) on top of the overlay. Esc closes the picker first.
  - Fields: scale, budget (the hint shows the free ids), min size, yaw, anchor x y z, and both region corners. Terrain and Clips are On/Off toggles (Nogrip was removed 2026-11-13; `--ungrippable` stays on the command line).
  - Typed values and the picked map are kept in `MapConv.overlayState` while the script runs.
  - Convert (or Enter in a field) shows "Converting…". One frame later, a one-shot `draw2d` hook (`mge_mapconv`, removed by the overlay's `killAction` too) reads the file with `Files`, converts it, closes the overlay and calls `Assets.addObjects(objects, false, false)`: one undo step, kept in place. The report goes to chat.
  - The mapconv modules load on the first Convert map click (`MGE.loadMapConv` in `main.lua`), not at startup, so a broken converter prints an error in chat and the rest of MGE still starts. `mapOverlay` is in `main.lua`'s `OVERLAY_KEYS`, which quit, overlay-open and Esc handling all read.
  - The conversion runs in one go. A dust2-sized file paused for about 1.3 s offline. If it feels bad in game, run it in a coroutine across frames.
- ✅ **The flow (2026-11-12):** the overlay holds only settings:
  - Map
  - Scale, Budget, Min size, Terrain tol.
  - Terrain / Clips
  - Cancel | **Place** (Enter in a field does the same)

  Region, anchor and yaw are picked only in the placement view, and its bar reads **Region | Map | Settings | Convert**:
  - **Convert** adds the boxes and closes the view. With an empty region it stays open and says why.
  - **Settings** and **Esc** go back to the overlay.

  Each map's placement (region, anchor, yaw) is kept per map file in `overlayState.placements`, so Place resumes where you left off. The map's scale goes back into the Scale field. With no saved placement, the view starts around the anchor entity (a T spawn) with a 1000×1000-unit region. The command-line tool keeps `--region` / `--anchor` / `--yaw`.
- ✅ **Placement view** ([ui/map_place.lua](../mge/ui/map_place.lua)), opened by the overlay's **Place** button.
  - It draws the map in the world where Convert puts it:
    - orange: what Convert adds
    - red: in the region but over the budget
    - grey: the map around the region, within `contextMargin` (0.5 of its size), `contextLimit` (200) biggest boxes
    - The game drew only part of the first version on dust2 (it had ~3,500 draws a frame). The view now draws at most `MapPlace.maxDraws` (800) shapes a frame, in order: region, kept (fill + outline), over budget (fill), context (fill). The bar says "preview trimmed" when some are left out. Lower `maxDraws` if parts of the preview still go missing.
    - cyan: the region box
  - A bar at the top switches the gizmo between:
    - **Region:** Move, and Scale per axis, in map axes.
    - **Map:** Move = anchor, the z ring = yaw, the white cube = scale. All around the dojo centre.
  - The bar shows live counts (boxes of the budget, how many over).
  - **MGE's window is hidden** while placing and shown again afterwards. The bar replaces it:
    - Row 1: Region | Map, then Move | Rotate | Scale (lit like the toolbar, through `Gizmo.modeListeners`), then Settings | Convert.
    - Row 2: **Floors first** | **Center first**.
    - Row 3: the info line.

    While placing, Shift+Q/W/E still work, other shortcuts and F1 do nothing, and the gizmo, highlight and world-click gates allow the view through.
  - **Budget order** (`MapConv.priority`, also `--no-floors-first` / `--center-first` on the command line):
    - **Floors first** (default on): a box's walkable top (a face within ~45° of up) counts 3× extra, so floors and terrain beat equally big walls.
    - **Center first** (default off): the score is divided by `1 + (d/reach)²`, where `d` is the distance from the region's middle across. That's half at the middle of a side and a third at a corner.
    - The toggles are kept across maps in `overlayState`.
    - The region's height already cuts roofs and ceilings.
  - **Draw order** within `maxDraws` (the user set 500, `contextLimit` 250): region, kept fills, over-budget fills, context, then outlines on the biggest kept boxes with what's left.
  - **On the ground:** the anchor's height is always worked out so the lowest kept box sits at z = `lift`. It's redone after every region or map change. Map Move's up/down changes only the lift (clamped ≥ 0, so nothing ends up under the game's floor), and the live drag preview is clamped the same way. The lift is kept with the placement.
  - **Camera:** with Camera follow on (`Camera.followMoves`, the default), every committed region or map change re-aims the camera at the region, keeping its distance when far enough, the same as moving objects.
  - **Done** writes region, anchor, yaw and scale into the fields. Cancel or Esc keeps the old values.
  - How it hooks in:
    - `Gizmo.targetOverride` gives the gizmo the region or map target.
    - `Highlight.placement` draws through `Highlight.drawBox`.
    - `WorldSelect.clicksOff` stops world clicks selecting; camera drags still work.
  - The converter is split into stages so this stays fast:
    - `MapConv.pieces` is the slow part. It runs once and is cached per map and options in `overlayState.cache`, which keeps only the entities, not the brushes.
    - `MapConv.select` (region, merge, size, budget) reruns after every gizmo release.
    - `MapConv.toWorld` / `toMap` / `objects` handle placement.
  - `convert` = pieces → select → objects. Output is byte-identical to before the split (checked on dust2 B site).
  - Offline smoke test with stubbed UI: TF2 `test2.bsp` and dust2 all pass. Dust2 loads in 1.8 s, and Convert after Place takes 0.1 s. Placed values converted in the window match a direct conversion object for object.
  - **In game: open.** Things to check:
    - the bar draws (it reuses the main window's `globalid`)
    - frame rate with ~1500 grey boxes; lower `contextLimit` if it's slow
    - gizmo size on a big map target
- **Phase 2 adds to the overlay:** a "Model" toggle and the OBJ/TGA writer, using `io.open(path, mode, true)` (root-relative).

## In-game checklist

Everything here passed offline. Only the user can check it in game. Tick each item, or write what went wrong next to it.

- [ ] Advanced → **Convert map** opens the overlay. The converter loads on this first click; a load error shows in chat and MGE keeps working.
- [ ] `mapconv_test.vmf`: Place, then Convert. The boxes sit where the preview showed them, on the ground, and a tori can walk on them.
- [ ] `tf2_test2.bsp`: converts, and the terrain slabs are walkable.
- [ ] One undo (Shift+Z) removes all of a conversion's boxes.
- [ ] A `.tbm` from `tools/mapconv.lua`, imported through Objects → Import, keeps its position (`#mge_keep_position`).
- [ ] Ramps and slabs feel right to walk on. If not, tune `slabThickness`.
- [ ] Placement view: the bar draws, Shift+Q/W/E switch tools, F1 does nothing, and Esc goes back to the overlay.
- [ ] After placement, MGE's window comes back on the right tab, and the gizmo tool is the one from before Place.
- [ ] Frame rate with the grey context boxes. Lower `contextLimit` if it's slow.
- [ ] The gizmo is a usable size on a big map target.
- [ ] dust2: how long Convert pauses (about 1.3 s offline). Move the conversion into a coroutine if the pause is bad.
- [ ] Joints → Link with more than 56 objects (a converted map) shows the pager, and picks on page 2 work.

## Phases

| # | Scope | Done when |
|---|---|---|
| 0 | ✅ Answer the open questions by hand. | Done: see the Phase 0 answers above. |
| 1 | ✅ Command-line tool: VMF parse, filter, geometry, exact box / smallest box / **ramp slab** fitting, region crop, anchor, yaw, scale, budget cut, `.tbm` writer, plus the keep-position import (`MGE.KEEP_POSITION_TAG` in `assets.lua`). | Offline: done. **In game: open**, a real map area has to import with boxes where they should be. |
| 2 | OBJ + palette TGA + carrier object, `maxFacesPerModel` option. | The model lines up with the boxes in game. |
| 3 | Merge, a report file, slab tuning. | A full dust2-sized area fits in the budget and is walkable. |
| 4 | ✅ In-game Convert Map overlay (Advanced tab → Map). | Offline smoke test: done. **In game: open.** |
| 5a | ✅ Source `.bsp` reader (v19-21; L4D2-style lump order detected). It reads only the lumps it uses, through a seekable file. Not supported: GoldSrc (v29/30: no brushes), Source 2 / CS2 (`.vpk`), Momentum (v25), LZMA-compressed lumps. | Offline: done. **In game: open.** |
| 5b | ✅ Terrain (`.bsp` displacements) → slabs (`BoxFit.terrain`: a flat patch becomes one slab, a bumpy patch splits in 4), plus merging (`merge.lua`, the planned Phase 3 merge). | dust2 B site (1000×1000 units) = 187 boxes at terrain tolerance 16. |
| 5 | Quake `.map` (standard + Valve220), model splitting. | GPL Quake/Xonotic maps convert. |

### Props (crates, doors, cars), 2026-11-12

> **Removed 2026-11-13.** In-game testing found the prop boxes not useful. The code is in git history (`de2ce06`); what follows is the record of how it worked.

Most map detail is props, not brushes. dust2 has 3,158 static props: 1,258 solid and 1,900 not, including 156 crates, 319 doors and door frames, and 32 cars. [mapconv/props.lua](../mge/mapconv/props.lua) handles them:

- **Where props come from:**
  - static props from the game lump `sprp`, any record size; version 11+ adds a scale
  - prop entities: `prop_dynamic*`, `prop_physics*`, `prop_door_rotating`, and in a `.vmf` also `prop_static`
- **Model sizes:** read from the `.mdl` header (hull box, else view box). Each model is looked up in:
  1. the map's packed zip (stored entries)
  2. the game archives (`*_dir.vpk` v1/v2, `.mdl` entries only, parts opened on demand)
- **Boxes:** each prop's box is `R = Rz(yaw) Ry(pitch) Rx(roll)`, scaled.
- **Left out:**
  - non-solid props
  - by model path (`Props.SKIP`): foliage, trees, palms, bushes, plants, grass, flowers, vines, wires, cables, antennas, ropes. Their boxes would be blocks of air.
- **Cache:** sizes found go into `<map>.models` next to the map, at 17 digits so the cache gives exactly the same boxes as reading the files.
  - The command-line tool finds archives in Steam's `common` folder next to Toribash, or via `--game-dir`. `--no-props` turns props off.
  - The game opens `../<game>/<archive>` from the Toribash root (`io.open(path, "rb", true)`). **Whether the game allows `../` there is unverified.** If it doesn't, the cache the command-line tool writes covers it. `de_dust2.bsp.models` is already in `assets/maps`.
- **Settings:** a **Props** toggle in the overlay; `DEFAULTS.props = true`.
- **Clips** are now off by default (`--clips` turns them on). *2026-11-13: on by default again, colored like the geometry they cover, after the user's in-game tests; `--no-clips` turns them off.*
- **Checks run:**
  - dust2: 629 models found in 0.25 s.
  - The crate named `37x37x74` comes out 43×78×38 (lying along y, with overhang).
  - B site gets 48 props among its 200 boxes.
  - The archive run, the cache run under 5.1 and the cache run under 5.4 give byte-identical output.
  - The placement smoke test passes with props, both from the cache and from the archives (the game's root-relative path, stubbed).

### Boxes that aren't in the game (the user's in-game test, 2026-11-12)

The preview showed big boxes in the air above B doors. Measured on dust2, they came from three sources:

1. **465 brushes with only `TOOLS/TOOLSNODRAW`**, up to 2336×2624×288: the sealing slab under the map, roof caps, and the backs of terrain walls. They're now dropped as "invisible": every side has an undrawn tool texture, which excludes `TOOLSBLACK` / `TOOLSWHITE`. The `invisible` option (`--invisible`) keeps them.
2. **6 `TOOLS/TOOLSTRIGGER` brushes**, up to 1360×816×272 at height 560: the boxes above B doors. A `.bsp`'s contents flags marked them solid. `brushRole` now applies the trigger, sky, hint and areaportal texture rule to `.bsp` brushes too.
3. **302 CS:GO "autocombine" props**, up to 866×1522: the compiler merges scattered decoration into one model whose box spans a street. `autocombine` was added to `Props.SKIP`.

Result: B site has 178 boxes and nothing is under the ground, since the invisible basement slab had been the "lowest point".

### Simplify: nearly flat slabs join (2026-11-12)

The exact merge only joins boxes aligned to 1 unit. Terrain tiles each tilt and lift a little differently, so a terrain floor stayed a mosaic. `Merge.flat` (in `merge.lua`) runs after the exact merge in `MapConv.select`, on the region only.

- **What joins:** slabs only (thinnest side ≤ 32, the other two at least 2× thicker), with matching role, facing nearly the same way (|n·n| ≥ 0.95).
- **Conditions for a join:**
  - The two touch or overlap in their plane (gap ≤ 16), so pits are never bridged.
  - The joined box is at most `simplifyTolerance` (12) thicker than the thickest part.
  - The parts cover at least `simplifyFill` (85%) of it, so L shapes keep their corners open.
- **How it runs:**
  - Greedy, biggest first.
  - A 256-unit xy grid finds neighbours, which are tried in a fixed order, so 5.1 and 5.4 give identical output.
  - The joined box keeps the first slab's axes.
- **Switches:** the placement bar's **Simplify** toggle (on by default, saved like the order toggles); `--no-simplify`, `--simplify-tolerance`, `--simplify-fill` on the command line.
- **dust2 B site (1000×1000):** 277 → 111 boxes at terrain tolerance 8; 178 → 103 at 16.
- **A 1600×1600 area** now fits in 233. Recounting after a gizmo release takes 0.07–0.26 s.
- The grey context skips Simplify; it would take 2.5 s more over the whole map.

### Openings stay open (the user saw blocked tunnel entrances, 2026-11-12)

Two causes, both measured on dust2:

1. **Frame-like props.** Their box fills the opening they frame:
   - `dust_underpass_frame_03` (223×42×185), the tunnel mouths
   - `dust_door_large_doorframe_01` (159×19×284)
   - `dust_arch_01` (68×359×455)
   - `dust_underpass_gate_columns` (321×33×209)

   `frame`, `arch`, `doorway`, `columns` were added to `Props.SKIP`. Doors themselves are kept.
2. **Simplify could join a lintel with the wall beside it.** The fill share allowed 15% empty, which covered the doorway. In B site, one 648×448 wall covered a 6% hole. `Merge.flat` now joins only edge to edge: along one axis both reach as far as each other (within the gap), or one lies inside the other on both axes. A cross shape doesn't join either.

   Measured with a sampling check: 0 joined boxes cover empty space. Cost: B site goes 111 → 161 boxes.

Tests check a doorway wall (3 parts stay 3), the same wall without an opening (joins into 1), a cross, the skipped models, and that a door is kept.

### Beams and ledge shells (rails that wouldn't join, 2026-11-12)

> **The shell join was removed 2026-11-13** (the overlay's Ledge size field, `simplifyShell`, `--simplify-shell`): in-game testing found it not useful. Beams joining end to end and the slab rules stay. Beams are now at most `maxThickness` (32) thick.

Rails, curbs and ledge strips are **beams**: thin in two directions. As slabs their "normal" was arbitrary, so an 8×16 rail next to a 16×8 one never joined. A measured diagnostic of the unjoined pairs on dust2 showed most were **strips side by side**: a ledge's top, face and lip, the same length and 15–38 apart. They're the shell of one solid ledge, which is what the user saw as "hollow".

`Merge.flat` now classifies each piece as a beam and/or a slab (re-classified after every join) and tries each rule both qualify for:

- **Beam end to end:** within 14°, cross-section growth ≤ tolerance, fill along the length.
- **Beam side by side ("shell"):** the same length (ends within `align`), touching across, joined cross-section ≤ `simplifyShell` (96). Touching is required, so a corridor between two curbs is never filled. Beams can be up to 64 thick.
- **Slab edge alignment** uses `align` = 32: a notch of at most 32 can close, a doorway can't (a lintel differs by far more). `simplifyFill` dropped to 0.75, since alignment already prevents holes.
- **Settings** gained **Simplify tol.** and **Ledge size** (0 turns off the shell join). The command line has `--simplify-shell`.

Results:

| | Box count |
|---|---|
| dust2 B site | 161 → 132 |
| 1600×1600 area | 247, fits |

The only unjoined strip pair left is two big overlapping slanted slabs 7° apart. The hole check flags one 48×368×84 ledge block as half "empty": that's its filled inside, by design.

### Sky clips (the user: clips are useful but bring huge sky boxes, 2026-11-13)

With Clips on, dust2 gave giant see-through lids over the map. Mappers fill the air between the roofs and the sky with big clip brushes, so players can't jump onto the roofs. dust2 has 5 of them, up to 2652×3116 units, all ending at z 820 with the sky starting at 1056. 1,253 clips were measured to find a rule that separates the lids from the useful clips:

- **Touching the sky isn't the test.** Only 7 clips touch a sky brush from below, all thin pillars and walls. The lids stop 76–236 units short of the sky.
- **Sky somewhere above isn't either.** Every outdoor clip has it. A wide, flat stair ramp clip (`958`, 738×562×27) has the sky 232 above it, but only over 1% of its top.

The rule (`SKY_CLIP` and `MapConv.isSkyClip` in `convert.lua`) leaves a clip out when all of these hold:

- it's **wide**: both horizontal sides are at least 256
- it's **flat**: lower than it is wide
- the sky starts at most **256** above its top
- that sky covers at least **half** of its top

On dust2 it drops exactly the 5 lids. The 712×160×500 clip at the lids' edge (`1382`) stays, because it's taller than it is wide. Sky brushes come from `MapBrush.sky`, which the `.bsp` reader sets from the sky surface flags; in a `.vmf` they're found by their `TOOLSSKYBOX` material. The report says how many were left out. `--sky-clips` on the command line (option `skyClips`) keeps them; the overlay always leaves them out. Clips inside dust2's 3D skybox (z ~3570–3790) aren't lids and aren't dropped, and a region around the play area leaves them out anyway. Tests: `sky clips` in `tests/test_mapconv.lua`.

**Floating lids (the user: office and nuke keep big flat sky clips, 2026-11-13).** Office's and nuke's lids are thin 16-unit sheets 250–1150 units under the sky, so the 256 gap missed them (office: 0 left out). Distance to the sky can't separate them from useful clips, but what's under them can. The rule (`dropSkyClips` in `convert.lua`, run once every piece exists, since what's under a clip can be terrain) now also leaves out a wide, flat clip when, on 6×6 points of its footprint:

- **floating**: on at least half, nothing solid (terrain included) from 72 units (a player's height) under it up to its top
- **open**: on at least half, sky directly over it with nothing solid in between

The old "close under the sky" rule stays as the other way in: thick blocks resting on roofs right under the sky (inferno's, overpass's roof caps) don't float.

Measured: office's 8 sheets float on 75–100% and are open on 97–100%. Nuke's sheets at z 208 and −64 float on 94–100%, open 78–100%. Kept: nuke's clips under roofs (open 0%), its clips lying on geometry (floating 3–11%), and dust2's ceiling clip over CT spawn (738×562, open 47%). Also dropped now: the 512×1024 sheets in the 3D skyboxes (dust2, nuke, mirage), mirage's 6144×5504 lid over the whole map, and dust2's 1256×448 clip at (−1596, 1184, 372). None of these is inside the dust2 bombsite regions.

Sky clips left out, whole maps: office 0 → 8, nuke 22, dust2 5 → 11, inferno 15 → 16, mirage 3 → 9, overpass 5 → 9, train 16, cache 13 → 28, ancient 11, vertigo 2. Times unchanged.

### AtmoLayer the excess (2026-11-13)

The overlay's Budget may go above the mod's free object ids, up to the free ids plus the room left for parked objects (`AtmoLayer.maxAtmo`, 512). Convert adds the boxes in the converter's order (most important first): the first ones get the free ids, the rest become parked objects (`utils/atmo_layer.lua`: kept in the mod file as comments, drawn by MGE, exportable as an atmo without collisions). The placement view draws the boxes that will be parked in purple and counts them in the bar. Imports that don't ask for it (`Assets.addObjects`' `atmoExcess`) stay all or nothing.

### Clip colors (the user: clips hold a big share of the core geometry, 2026-11-13)

With Clips on, 74 of the 200 boxes of a dust2 mid area are clips: ramps over stairs, smoothed wall corners, rails. See-through red made a big part of the map look unfinished, so clips are now **always solid, in the color of the map geometry they cover**. A `clipColor` option with a Red mode existed briefly and was removed the same day; the user found no use for red.

- **Borrowed material** (`borrowMaterials` in `convert.lua`): each clip takes the material of the solid piece its bounds overlap most, counting solids within 8 units (a clip along a wall only touches it). Brushes and terrain slabs count; tool-textured solids don't. A clip touching nothing is plain grey. The material is in the object's comment (`clip by <material>`).
- A 512-unit XY grid keeps it fast: dust2's pieces step went from 0.55 s to 0.67 s.
- On that dust2 area every clip found a material.

Tests: `clip colors` in `tests/test_mapconv.lua`.

### Hidden and covered boxes (the user: one bombsite takes the whole budget, 2026-11-13)

Clips are on by default now. Measured on dust2 B site with defaults and no budget:

| Region | Boxes | Terrain slabs | Inside another box |
|---|---|---|---|
| 1000×1000 | 135 | 98 | 23 |
| 1500×1500 | 247 | 175 | 60 |
| 2000×2000 | 321 | 226 | 61 |

Most of the hidden boxes are solids inside clips (stairs under their ramp clip). Terrain tolerance is a weak lever (1500×1500: 247 → 219 at 16, 208 at 24), and a looser tolerance for wall terrain changes nothing: each wall grid is already one slab.

- **`Merge.hidden`** (`merge.lua`), run in `MapConv.select` after merging and before the minimum size and budget. Smallest boxes first, against boxes still kept, so of two identical boxes one stays.
  - **Inside one other box** (`dropHidden`, on, no toggle): all 8 corners inside the other box's own axes, 1 unit to spare. Lossless: on dust2 B site 1500×1500 every removed box is 100% inside kept boxes. 247 → **187**.
  - **Covered by several** (`dropCovered`, off; the placement view's **Covered** toggle, `--drop-covered`): at least `COVERED_SHARE` (95%) of 5×5×5 points inside other kept boxes. 187 → **147**. The least covered removed box is 94% covered (finer 7×7×7 check), so a thin ledge can go: check the preview.
  - A 256-unit XY grid finds neighbours: about 0.1 s per region change. The placement view's grey whole-map context skips it (0.3 s on dust2).
- **Budget** in the overlay now defaults to every free object id (256 in an empty mod) instead of 200. The command line keeps 200, since the asset may go into a mod that already has objects.

Tests: `hidden and covered boxes`, `hidden boxes in a conversion` in `tests/test_mapconv.lua`.

### dust2 (CS:GO Legacy `csgo/maps/de_dust2.bsp`, copied to `mge/mge/assets/maps/`)

- The file is 325 MB, of which 294 MB is the packed-texture lump. 9.1 MB is read.
- 2,471 brushes and 8,324 terrain grids.
- **88% of the floor area and 84% of the wall terrain has no brush behind it**, so terrain is on by default.
- The whole map comes to about 7,500 boxes after merging, so it's always converted by region.
- Bombsites from the `func_bomb_target` models: A x 976..1248, y 2336..2624, z 96..192. B x −1728..−1344, y 2496..2864, z 0..96.
- Spawns (average): T (−756, −791, 145), CT (281, 2269, −109).
- Pre-converted assets in `mge/mge/assets/obj/`:
  - `de_dust2_bsite.tbm`: region −2036 2180 −200 to −1036 3180 600, anchor −1536 2680 0, tolerance 16. 187 boxes.
  - `de_dust2_asite.tbm`: region 612 1980 −200 to 1612 2980 600, anchor 1112 2480 96, tolerance 16. 200 boxes, with 33 small ones cut by the budget.
- Terrain grid ordering was checked: 56% of edge points are shared with neighbouring grids, against 43% for the transposed or reversed orderings.

### More CS:GO Legacy maps (copied to `mge/mge/assets/maps/` on 2026-11-13)

`assets/` is gitignored and not in the release zip, so these are local test maps only. Whole-map runs of the command-line tool with the defaults (budget 200, anchor at the T spawn) all read without errors:

Sky clip counts in this table are from before the floating-lid rule (see Sky clips above for the new ones).

| Map | File | Brushes | Terrain grids → slabs | Boxes left out inside others | Sky clips left out | Time |
|---|---|---|---|---|---|---|
| `cs_office.bsp` | 32 MB | 4,940 | 119 → 1,436 | 366 | 0 | 2.8 s |
| `de_cache.bsp` | 486 MB | 5,560 | 10,852 → 13,444 | 3,197 | 13 | 12.3 s |
| `de_inferno.bsp` | 102 MB | 5,707 | 2,223 → 6,501 | 597 | 15 | 5.2 s |
| `de_mirage.bsp` | 63 MB | 8,189 | 954 → 1,443 | 1,714 | 3 | 4.8 s |

Later the same day, every other defusal and hostage map in CS:GO Legacy was copied too: cs_agency, cs_assault, cs_italy, cs_militia, de_ancient, de_anubis, de_bank, de_boyard, de_canals, de_cbble, de_chalice, de_lake, de_nuke, de_overpass, de_safehouse, de_shortdust, de_shortnuke, de_stmarc, de_sugarcane, de_train, de_tuscan and de_vertigo (2.4 GB). All 22 convert as whole maps without errors, in 0.7–6.7 s each. Brush counts range from 991 (boyard) to 7,847 (train).

- Like dust2, each whole map is far over the budget, so convert by region (Place).
- Newer maps such as cs_agency, de_boyard and de_chalice have few brushes for their size. Much of their geometry is probably models (props), which the converter doesn't read, so expect holes.
- "Boxes under the ground" in these runs only means the T spawn isn't the map's lowest point. A region with its own anchor doesn't have that.
- cache is the heaviest: most of its floors are terrain. Expect its Place view to take noticeably longer to open than dust2's. Not yet tried in game.

## Testing

- **Test suite:** `lua5.1 mge/tests/run.lua mapconv` (and `bsp`). `tests/test_mapconv.lua` builds hand-written VMFs and checks the whole conversion; `tests/test_bsp.lua` reads `tf2_test2.bsp` when it's in `assets/maps`. Add new converter checks there. The 2026-11-12 harness below was a throwaway one, and the suite rebuilds most of it.
  - Hand-written VMFs: one axis-aligned box, a box rotated 30° on Z, a wedge, two boxes that merge, a box with a `TOOLSTRIGGER` face, and a `func_buyzone` entity.
  - Check plane normal signs, the pos/sides/rot values against what the Generate tab would write for the same box, the merge count and the budget cut.
- **CLI under Lua 5.4** too, because community users may have it. The core must not use `unpack`, `loadstring` or `getn` directly.
- **Syntax:** run `luac5.1 -p` on every new file.
- **In game:** import the output into an empty mod and walk on it. Only the user can do this.

What ran for Phase 1 (2026-11-12):

- `luac5.1 -p` passed on all new and changed files.
- A Lua 5.1 harness passed 56/56 checks. It was kept in a temp folder and rebuilds from the list above. It covered:
  - the tokenizer
  - the winding of Hammer's example cube
  - reversed winding
  - exact fits for yawed, tilted and on-its-side boxes
  - rot lines read back through `Transforms.orientationOf`'s formula and giving the same box
  - a wedge becoming a slab on its slope
  - filtering (sky, trigger, buyzone, skip, hidden solids, func_detail)
  - colors, budget, region, anchor, yaw and the under-ground count
  - the output parsed back by `FileHandler.ParseMod` with the tag in its header
- The command-line tool ran on a synthetic 5,000-brush, 5.7 MB VMF in 1.3 s on Lua 5.1 and 0.9 s on Lua 5.4, and the error messages were checked.
- `.bsp` reader, against the handmade TF2 test maps from [bsp_tool](https://github.com/snake-biscuits/bsp_tool) (GPL-3.0, `tests/maps/Team Fortress 2`):
  - The float decoder was checked against known bit patterns.
  - `test2.bsp` matches Valve's `vbspinfo` output: 75 brushes, 451 sides + 3 bevels = 454, and 3 displacements. Every kept brush builds.
  - The world brushes' combined bounds match the world model's bounds exactly on 3 maps, and no plane needed the flip fallback.
  - Triggers are dropped by class, sky shells by surface flag, and clips are kept.
  - The command-line output is byte-identical under Lua 5.1 and 5.4.
  - A v25 map, a junk `.bsp` and a cut-off `.bsp` each give a clear error, and nothing is written.
- An overlay smoke test ran on Lua 5.1 with stubbed UI (TBMenu, Widgets, Rows, Files, hooks) against `map_overlay.lua`. It checked:
  - the field count and the budget hint (free ids)
  - converting with no map picked
  - a non-number, a partial anchor and a budget over the free ids
  - Enter converting only after a frame
  - 40 objects added in place
  - the overlay closing and the hook being removed
  - the report echoed to chat
  - typed values kept for the next opening
  - closing the overlay dropping a pending run

## Risks

- **The object budget.** A whole competitive map won't fit at full detail. Present crop + budget as the normal workflow, not a fallback.
- **The ground at z=0.** If it can't be removed, maps with several levels (dust2's lower tunnels) need the anchor chosen so the play area sits on z=0, and parts below it end up underground.
- **Model scaling and the face limit** are unconfirmed (Phase 0).
- **Wedges and stairs:** a slope box or step boxes change how ramps feel, so tune them in game.
