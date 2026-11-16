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

### Joints
- [ ] Pos on a joint without a `pos` line (katana.tbm) shows "none". Typing a value puts the anchor at the
      objects' midpoint with that axis, and the objects then hinge there.
- [ ] Recenter on such a joint does the same, and the wheel steps from the midpoint.

### Map converter
- [ ] The sky clip rules are back to before the cobble/cache attempt: dust2 keeps its walls.
- [ ] Placement view: Rotate in Region mode switches to Map, and the preview shows the whole Budget + Atmo.
- [ ] Converting still works after `mapconv/skyclips.lua` was split out (it loads with the converter).

## Reference mods

- `data/mod/mge_tests/joint_nopos.tbm`: joints without `pos`. The game locks the objects together.
- `data/mod/mge_tests/joint_axis.tbm`: the axis is in world space, and a length like `0 0 90` is unstable.

## Done
