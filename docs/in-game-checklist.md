# In-game checklist

The offline checks (`lua5.1 tests/run.lua`, `lua5.1 tools/mapconv_baseline.lua check`) cover the pure logic.
Anything that draws, reloads the mod, or depends on how the game reads a file only shows in game. Go
through this before `tools/package.ps1`. Tick what you checked and move items you fixed to **Done**.

## Before every release

- [ ] `/ls mge/mge.lua` starts without errors in chat. Running it again shows the window, not a second one.
- [ ] Load a mod, move / rotate / scale an object with the gizmo, then Shift + Z and Shift + Y.
- [ ] Save, reload the saved mod with `/lm`, and check the change is still there.
- [ ] Settings opens and closes, and the values are kept after a restart.

## Not yet checked in game

### Players
- [ ] Rotating a player in a mod without a `version` line (aikido.tbm, fat.tbm) applies the turn and adds `version 15`.
- [ ] Rot field: the wheel steps by the rotate step (Shift: 1 degree) and also works after a gizmo turn.
- [ ] Scale field: the placeholder updates after a scroll or a gizmo scale.
- [ ] The shorter help texts fit.

### Snapping (Settings)
- [ ] One Snapping section: Step, Shift step and Rotate step.
- [ ] The gizmo snaps with Ctrl to Step (Ctrl + Shift: Shift step) and its rings to Rotate step (Ctrl + Shift: 1 degree).
- [ ] The wheel over Rot fields (objects, players, Generate's Angle) steps by Rotate step.
- [ ] An old `config.cfg` with `snapStep` loads, and the line is dropped on the next save.

### Wheel from exact values
- [ ] The wheel over Pos / Rot / Scale, a joint's Axis and Range, and player Density steps from the real
      value, not the 2-decimal placeholder: an axis of `0.6084998164` steps to `1.1085`, not `1.11`.

### Hover popups under their buttons
- [ ] The list's icon buttons (New, Duplicate, Delete, Import...), the Link tab's buttons, the map placement
      toggles, the trash icons (Model, Shader) and the list cells show their popup under the button, left
      edges lined up. Near the right edge it moves left, at the bottom of the screen it opens above.
- [ ] The top bar's popups still open under and to the left, and the "?" icons still open to the right.

### Misc: Reset all
- [ ] Reset all with unsaved changes asks first, Cancel keeps everything. Continue loads the classic mod.
- [ ] Without unsaved changes it loads classic right away. MGE then shows the classic mod (2 players, no
      objects, no atmo) and editing and saving it works like any other mod.

### Applying a field by clicking another one
- [ ] Type a joint's Range (or any field that reloads the mod: Axis, an object's Mass), then click another
      field: the value applies without rows of other tabs flashing in the panel, and the clicked field
      keeps focus. The same in Settings and on the Players panel.

### Gizmo steadiness
- [ ] Orbit and zoom with the gizmo off-center (an object not in the middle of the screen): the gizmo no
      longer shakes while the camera moves. Clicking handles still hits them.
- [ ] After a change (the reload), the gizmo doesn't shake while the camera settles. If it still does,
      the camera position and the drawn frame disagree for a moment, a second cause to probe.

### Spawning at the look-at point
- [ ] Opening and closing the Generate tab repeatedly leaves the preview and the camera where they are,
      also for a bend or a ramp (where the pieces' average isn't the shape's middle).
- [ ] On Generate, clicking an object or atmo object (in the world or the list) or box selecting switches to
      Core, and the gizmo moves to the selection. Clicking an atmo object from the Objects list opens the
      Atmo list on Core.
- [ ] With MGE's camera in control, Import and adding a player put the new thing where the camera looks,
      with its bottom on the floor or above it.

### Joints
- [ ] Link tab: with Pick from world off, clicking an object in the world selects it on the Objects
      list (out of the Joints list). With it on, the clicked object is picked for the joint and the object
      under the cursor is lit. It turns off after Create / Update, Reset and leaving the list.
- [ ] Link tab layout: Pick from world on its own row above Reset · Create/Update, with no status line or
      "?" under them. Hovering Create/Update says what it would do ("Joint 3: joins objects 4 and 7").
- [ ] Properties tab: clicking an object selects it on the Objects list. It no longer starts a new joint.
- [ ] Clicking a joint's anchor still selects that joint, and box-selecting joints works on the Link tab.
- [ ] Pos on a joint without a `pos` line (katana.tbm) shows "none". Typing a value puts the anchor at the
      objects' midpoint with that axis, and the objects then hinge there.
- [ ] Recenter on such a joint does the same, and the wheel steps from the midpoint.
- [ ] With camera follow on, changing a joint's Pos (typed, wheel, Move gizmo, Recenter) looks at the
      moved anchor and keeps the camera distance. An Axis or Range change doesn't move the camera.

### Map converter
- [ ] The sky clip rules are back to before the cobble/cache attempt: dust2 keeps its walls.
- [ ] Placement view: Rotate in Region mode switches to Map, and the preview shows the whole Budget + Atmo.
- [ ] Converting still works after `mapconv/skyclips.lua` was split out (it loads with the converter).

## Reference mods

- `data/mod/mge_tests/joint_nopos.tbm`: joints without `pos`. The game locks the objects together.
- `data/mod/mge_tests/joint_axis.tbm`: the axis is in world space, and a length like `0 0 90` is unstable.

## Done
