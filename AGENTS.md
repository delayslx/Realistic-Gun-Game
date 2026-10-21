# AGENTS.md - RealisticGunGame

Godot 4.7 (Forward Plus + Jolt) FPS prototype. There is no CI, test framework, or build step; validation is done by running the game/probes and reading logs.

## Running and validation

```bash
godot --path .                                  # main.tscn
godot --path . res://dev_test/rig_probe.tscn    # output: user://probe_out.txt
godot --headless --path . --script res://dev_test/measure_fingertips.gd
```

- Godot 4.7 is required; the binary is not in the repo (depending on your installation the command may be `godot4`). Opening the project with an older Godot can corrupt `uid://` / `unique_id` data.
- `dev_test/rig_probe` and `measure_fingertips` are the current tools. `verify_bodycam.gd`, `verify_recoil_eject.gd`, and the root-level `rigshot.gd` were written against the old API (`Player/CameraPivot/Weapon`, the removed `weapon_aim_offset` / `weapon_aim_raw`); they FAIL with the current code, so do not treat them as regression references.
- The screenshot directory in `verify_*.gd` is hardcoded for Windows (`C:/Users/tunac/...`); ignore the images on Linux.
- When debugging, check the script errors in the `godot --path .` output first; `push_warning` messages can be silently missed.

## Godot AI MCP

- `addons/godot_ai` (v4.3) is vendored and enabled in `project.godot`. The `_mcp_game_helper` autoload is required for runtime `game_manage` commands; do not delete it.
- If MCP is connected, MCP is the single source of truth for editor state: use `session_manage` / `editor_state` first, `scene_get_hierarchy` for the scene, and `script_manage` / `node_get_properties` before editing. Save with `scene_save`, run with `project_run`, read logs with `logs_read(source="editor")`, stop with `project_manage(op="stop")`.
- The `scene_list`, `node_list`, `script_read`, `script_write`, `play_start`, and `console_get` names in older documentation do not exist in this version; do not use them.
- If MCP is not connected, edit the files directly and validate with the Godot CLI; do not assume scene state as if it were connected.

## Ask questions

Before writing code, use `question`: when the target scene/node/script is unclear, when there is more than one valid approach (GDScript vs scene setting), for a delete/overwrite, a `project.godot` or input map change, or if a large refactor is needed. Do not ask for single-file fixes with a clear scope.

## Architecture (easily broken)

- `main.tscn` is the playable arena: `Player` + `IK_character` + targets + `UI`. `ik_character.tscn` is the rig itself.
- Weapons are mounted through the `WeaponManager` autoload: `weapons/<id>/<id>.tscn`, with `metadata/weapon_id` on the root. The current mount point is **`IK_character/WeaponMount`** (player_controller drives it every frame); if it is missing, fall back to `RightHandAttach`, then `CameraPivot`. The header of `weapon_manager.gd` and part of `weapons/README.md` still describe the old "RightHandAttach hand socket" model; the code is current.
- Update order carries weight: `weapon_controller` (-10) -> `player_controller` (0) -> `hand_rig` (10). `fingers_ik` must remain the **last** link in the skeleton modifier chain; if the order changes, fingers are solved with a one-frame lag/old pose.
- `hand_rig.gd` is a `@tool` script and also drives the editor preview. During finger calibration, while `grip_wrap=false` the `*_target` markers under `RightHandAttach` / `LeftHandAttach` are authoritative; `grip_wrap=true` overrides them with a procedural grip. Details: `weapons/README.md`.
- When adding a new weapon, copy `g18.tscn`. `weapon_controller.gd` expects the G18-specific `GunVisual/G18_rig/Skeleton3D` and the `G18_slide` / `G18_mag_2` / `G18_trigger` bone names; a different rig will silently not work and requires code changes.
- Aiming is only entered with RMB (`look_hold`); LMB (`fire`) never enables ADS. The bullet travels from the muzzle (`muzzle`), not the camera; the aim offset is intentional.
- The character has only a single static clip; walking/idle bob and animation transitions are disabled for this reason. Do not enable them without adding a clip.

## Input and UI

- The old `rack_slide=G`, `clear_jam=C`, `insert_mag=T` entries remain in `project.godot`; `player_controller._ensure_key_bindings()` deletes them at runtime and binds R (magazine) / F (slide + jam). If a key changes, both `project.godot` and this function must be updated.
- The control panel at the bottom left is rewritten from the InputMap by `scripts/controls_ui.gd`; editing the Label text in `main.tscn` has no lasting effect. For a new action, update `build_text()` and `DESCRIPTIONS`; the `ORDER` constant is currently unused.

## Scenes and UID

- `.tscn` / `.tres` files contain `uid://` and `unique_id=` references. Manual bulk editing breaks references; use MCP/editor or re-save with Godot, then open the project and verify there are no missing resource errors.
- `_t*.tscn`, `_mcp_probe_scene.tscn`, `hello.tscn`, `temp_ik_check.tscn`, `inspect.tscn`, and `rigshot.gd` are old/scratch files left in place on purpose. `inspect.tscn`'s reference to `inspect_bones.gd` is a known gap; do not delete or "fix" it unless asked.
- The large binary assets in the root (`gun.glb` ~94 MB, normal map ~75 MB) and `.import` files are tracked; do not re-import/export and commit them unless asked.
