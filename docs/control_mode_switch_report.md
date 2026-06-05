# Control Mode Switch Report

## Summary

This pass adds a first validation layer for running two player input modes through the same combat core:

- `TIME_TACTICAL`: existing card / queue / frame-advantage mode.
- `POWER_ACTION`: direct attack inputs mapped to temporary Renka move data.

The implementation is intentionally small. Direct inputs create `ActionRequest` objects with `source_type = DIRECT_INPUT`, then reuse cloned Renka card definitions as temporary move data so the existing player action lifecycle, `MoveDefinition.from_card(...)`, and `HitboxSystem` remain authoritative.

## Files Touched

- `scripts/combat/action_request.gd`
- `scripts/combat/combat_input_router.gd`
- `scripts/combat/combat_manager.gd`
- `scripts/ui_manager.gd`
- `docs/control_mode_switch_report.md`

## What Changed

- Added `ActionRequest.from_direct_input(...)`.
- Added `CombatManagerCore.ControlMode` with `TIME_TACTICAL` and `POWER_ACTION`.
- Added runtime control mode toggle through:
  - `F9`
  - a pre-fight `Mode: ...` button above `Start Fight`
- Added `request_direct_action(input_name, move_id)`.
- Added direct input mapping in `POWER_ACTION` only:
  - `J` -> `light_punch`
  - `K` -> `light_kick`
  - `U` -> `heavy_punch`
  - `I` -> `heavy_kick`
- POWER_ACTION card buttons are not playable and do not mutate hand/deck state.
- Direct attacks use cloned Renka card definitions as temporary move data.
- Direct attacks enter the existing player action lifecycle and hitbox path.
- Direct action requests are recorded as `source_type = direct_input` in actor/debug/export data.

## Shared Core Path

Current POWER_ACTION path:

```text
keyboard input
-> CombatInputRouter
-> CombatManager.request_direct_action(...)
-> ActionRequest.from_direct_input(...)
-> CombatStateMachine.can_accept_action_request(...)
-> cloned Renka card definition
-> _resolve_player_card(...)
-> _start_player_card_action(...)
-> CombatTimeline / MoveDefinition.from_card(...)
-> HitboxSystem.activate_player_card(...)
-> existing damage / stance / frame logic
```

This validates that direct input can feed the current shared combat lifecycle without a second combat system.

## Validation Commands

Passed:

```powershell
& 'C:\Users\jason\OneDrive\Desktop\Godot_v4.6.2-stable_win64.exe' --headless --path . --scene res://scenes/Arena.tscn --quit-after 3
git diff --check
```

## Manual Test Notes

Interactive POWER_ACTION input was not manually tested in a visible Godot window during this pass. Expected manual validation:

1. Launch Arena.
2. Press the pre-fight `Mode` button until it shows `POWER_ACTION`, or press `F9`.
3. Press `Start Fight`.
4. Press `J`, `K`, `U`, `I`.
5. Confirm Renka performs light punch, light kick, heavy punch, and heavy kick through normal startup / active / recovery.
6. Confirm card buttons are disabled/ignored and deck hand does not mutate in POWER_ACTION.
7. Toggle back to `TIME_TACTICAL` before fight start and confirm existing card queue behavior.

## Passed

- Arena scene loads headless.
- GDScript parses after the adapter patch.
- Tactical mode remains the default.
- The direct-input adapter does not remove or replace tactical card/queue paths.
- POWER_ACTION does not call direct damage or bypass `HitboxSystem`.

## Not Fully Validated Yet

- Visible/manual POWER_ACTION attack playback.
- POWER_ACTION reaction-window challenge timing in live play.
- Whether direct-input follow-up/reward windows should stay fully free-form or later use explicit cancel metadata.

## Follow-Up Bugfix Notes

- POWER_ACTION now forces `Engine.time_scale = 1.0` and does not start tactical reaction countdown windows.
- POWER_ACTION enemy startup advances through a small real-time intent ticker instead of waiting for tactical frame-costed inputs.
- Direct-input challenge no longer uses the tactical close-startup trade shortcut. Direct hits during enemy startup resolve as normal hits/interrupts unless a future same-active-window clash path explicitly proves both hitboxes are active and overlapping.
- Movement/slow-neutral visuals now respect an active player action visual lock, preventing locomotion idle cleanup from cutting direct-input whiff/recovery animations short.
- POWER_ACTION enemy impact no longer uses the TIME_TACTICAL `reaction_no_defense_hit` resolver path; it records `power_action_enemy_hit`.
- POWER_ACTION enemy recovery is frame-owned and must tick to `ACTION_DONE` before Kai can request another attack.
- Added structured lifecycle events: `ACTION_STARTUP_BEGIN`, `ACTION_ACTIVE_BEGIN`, `ACTION_HIT`, `ACTION_WHIFF`, `ACTION_RECOVERY_BEGIN`, `ACTION_DONE`, `INTERRUPT`, and `REJECTED_ACTION`.

## Recommendations

- Promote temporary Renka card definitions into neutral `MoveDefinition` / character-kit data next.
- Add a test harness that can instantiate Arena, set control mode, call `request_direct_action(...)`, and assert that a `DIRECT_INPUT` action reaches `HitboxSystem`.
- Move input bindings into configurable data before supporting alternate characters or real-time versus deckfighter presets.
- Keep `CombatStateMachine` input-source agnostic: cards, direct input, AI, scripted actions, and debug actions should all become `ActionRequest`s.
