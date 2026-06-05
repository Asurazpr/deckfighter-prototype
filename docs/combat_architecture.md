# Combat Architecture

`scenes/Arena.tscn` uses `res://scripts/combat/combat_manager.gd` as the active combat manager. The old root-level `scripts/combat_manager.gd` should stay removed so there is only one combat manager script in play.

## CombatManager

`CombatManagerCore` owns high-level match flow, scene references, combat logs, UI-facing debug text, and coordination between systems. It should not become the home for new gameplay rules. When adding combat behavior, prefer placing the rule in the relevant system and keeping the manager as the caller/orchestrator.

Current combat states now route through explicit `CombatStateMachine.transition_to(...)` calls at the major combat phase boundaries. Some legacy booleans still exist as compatibility mirrors while the refactor continues, but new input checks and debug labels should query the state machine API instead of recomputing state from manager flags.

The combat engine should remain input-source agnostic. Cards, direct fighting-game inputs, AI choices, scripted events, and debug tools should all become `ActionRequest` producers. The combat lifecycle should consume action requests rather than treating cards as the primitive action type.

## Shared Core Boundary

`CombatCore` is the new compatibility boundary for shared combat authority. It owns the accepted `ActionRequest` contract, the canonical 30 FPS gameplay-frame constant, and actor-local core flags such as block startup/active state. Tactical and power controls should submit requests through this boundary before legacy manager code performs the current action lifecycle.

This pass intentionally keeps `CombatManagerCore` as the orchestrator while the deeper extraction continues. The next migration target is to move action execution, damage, hit/block/whiff/trade application, and recovery ownership behind `CombatCore.submit_action_request(...)` instead of letting the manager execute those rules directly.

`TacticalModeController` and `PowerFightingModeController` are mode-specific request producers. Tactical mode remains responsible for deck, hand, queue, frame advantage, and route UX. Power mode is responsible for direct-input mapping, future input buffer/cancel checks, and creating `DIRECT_INPUT` requests. Neither controller should apply damage or activate hitboxes.

`CombatAnimationController` is a presentation boundary. It may play or release visuals from observed action/block state, but gameplay timing and block/hit decisions should come from `CombatCore`, `CombatStateMachine`, and `HitboxSystem`.

## Systems

- `CombatCore`: shared combat authority boundary. It accepts `ActionRequest` objects, exposes the 30 FPS gameplay clock, stores core block startup/active flags, and is the intended future owner for move execution, hitbox resolution, damage, block, stance damage, hitstun, and recovery.
- `TacticalModeController`: deckfighter-mode adapter. It converts hand/card choices into `ActionRequest` objects and will own tactical queue/frame-advantage/card UX as those pieces leave the manager.
- `PowerFightingModeController`: fighting-game-mode adapter. It converts direct inputs into `ActionRequest` objects and will own input buffering, directional attacks, and cancel checks.
- `CombatAnimationController`: presentation adapter. It observes actor/action phase data and asks characters to play visuals; it must not advance gameplay state.
- `CombatClock`: single combat-frame advancement entry point. It ticks startup, vulnerability, and stance timers using combat frames.
- `CombatStateMachine`: authoritative combat phase enum, explicit state transitions, last-transition logging, input permission helpers, actor lock queries, current actor/phase helpers, and debug labels. It owns global phase authority; manager booleans are temporary mirrors only.
- `ActorCombatState`: per-fighter state snapshot for player/enemy action id, animation key, phase, facing, lock status, recovery/hitstun/blockstun counters, airborne state, and debug/export serialization.
- `ActionRequest`: input-source-neutral action intent data. Fields include `actor_id`, `action_id`, `source_type` (`card`, `direct_input`, `ai`, `scripted`, `debug`), `input_frame`, `priority`, optional `card_instance_id`, optional `queued_index`, and a payload dictionary. Deckfighter cards should produce these requests; future real-time inputs and AI should produce the same shape.
- `CombatInputRouter`: raw keyboard event routing for tactical queue controls, live reaction inputs, jump evade, pressure movement, and queue execution. Key bindings should eventually become configurable input data.
- `CombatDebugExporter`: JSONL export formatting/writing for metadata, snapshots, structured combat events, and human-readable log lines.
- `CombatTimeline`: lightweight visual/action timeline for startup, active, impact, recovery, movement, hitbox windows, and animation keys. It consumes combat-frame advancement and should never become the authority for gameplay timing, hit success, damage, frame advantage, or recovery completion.
- `QueueResolver`: tactical action queue, frozen card snapshots, queue text, duplicate card instance checks, queue clearing, and trade interruption flags.
- `FrameSystem`: frame advantage math, effective enemy startup, initiative carry-over helpers, and punish-window calculation.
- `StanceSystem`: public stance facade for combat code. It forwards to `enemy.gd` for now, but callers should use this system for stance state, protection, break timers, and stance damage application.
- `RouteSystem`: combo route reset, repeat-move decay, route helpers, and future follow-up/draw rules.
- `MovementSystem`: duel spacing, step/backstep/jump movement, movement frame costs, and card spacing effects.
- `MovementFlowSystem`: slow-neutral live movement, neutral time scale, live A/D repositioning, enemy approach movement, and movement-mode debug state.
- `HitboxDefinition` / `MoveDefinition`: data-shaped combat move definitions. Moves expose startup, active, recovery, hitbox size/offset, attack level, damage, stance damage, knockback, animation key, tags, and future extension points such as armor, invulnerability, projectiles, and grabs.
- `HitboxSystem`: gameplay authority for active hitbox state. It builds move definitions from card/enemy data, owns attack hitbox activation/deactivation, overlap checks, active/recovery debug phase state, and keeps character scripts from directly deciding collision timing or hitbox profiles. Characters may play animations and expose visual state, but they should not own gameplay hitbox timing.
- `TradeSystem`: trade recovery values and post-trade frame advantage calculation.
- `ReactionWindowSystem`: slow-time reaction countdown, impact bar progress, live guard input tracking, guard startup state, and perfect-block timing windows.
- `EnemyAISystem`: enemy decision state, tier/profile config, situation scoring, spacing checks, punish candidate selection, pressure reactions, boss phase hooks, and enemy intent choice.
- `CharacterRig2D` / `CombatAnimationDriver`: placeholder stick-rig visuals and pose mapping for combat phases. These are visual consumers of timeline data only; they do not decide hits, damage, frame advantage, or timing.

## Data Direction

Future cards, moves, character kits, movement profiles, and rulesets should become data-driven. Avoid hardcoding new move-specific behavior in `CombatManagerCore`; prefer card/move definitions or system-level config that can later be loaded from external data.

Cards are a deckfighter UX/control source, not the combat engine primitive. They should validate and create action requests. A future real-time mode should create equivalent requests from direct inputs while reusing the same startup, active, recovery, hitstun, blockstun, cancel, and lockout lifecycle.

Enemy attack definitions now live in `scripts/enemy/enemy_move_data.gd`, and stance defaults live in `scripts/enemy/enemy_stance_config.gd`. `enemy.gd` still owns runtime enemy state for now, but new enemy move/timing config should be added through data-shaped enemy config files instead of inline runtime logic.

Animation and timing should consume combat-frame data from the systems. Animation should not become the authority for combat logic timing. Placeholder combat visuals should read structured actor/action/phase data from `ActorCombatState` and `CombatTimeline`, while final animation/camera/focus-window work should keep `CombatStateMachine`, `CombatClock`, and combat rules as the source of truth.

Hitbox calibration is currently manual and author-driven. `F6` toggles a temporary calibration overlay that draws rendered sprite alpha bounds, pushboxes, hurtboxes, and HitboxSystem move boxes in startup/active/recovery colors. This is for tuning authored fighting-game boxes against the PNG-rendered characters; it should not become pixel-derived hitbox generation. `enable_hitbox_trace_log` emits compact `MOVE_DEF` and `HITBOX_CHECK` JSON-style combat log lines with the actual gameplay rectangles, source offsets/sizes, facing, scales, defender state, overlap, gaps, and final result.

## Current Dependency Audit

These are the remaining high-risk couplings to remove incrementally:

- Cards: `CombatManagerCore` still calls deck/hand/card methods directly for playability, queue execution, follow-up draw, route validation, and pressure reward flow. `HitboxSystem.begin_player_move(card)` and `MoveDefinition.from_card(card)` still adapt cards directly into move definitions.
- Animation: `CombatManagerCore`, `ReactionWindowSystem`, and `MovementFlowSystem` still call character visual methods such as `show_timeline_phase(...)` and `release_block_action(...)`. Renka still has action/visual lock fields that must remain presentation-only over time.
- UI: `UIManager` still calls manager card helpers directly, and the manager still formats large debug/HUD/export strings. Future UI should observe `CombatCore`, active mode controller, and snapshots instead of owning playability logic.
- Tactical turn logic: `QueueResolver`, `RouteSystem`, frame-advantage spending, magnetic follow-up draw, and enemy intent preview are still coordinated inside `CombatManagerCore`. These are tactical-mode systems and should move behind `TacticalModeController`.
- Enemy intent preview: reaction prompts and intent text are still produced from manager/enemy tactical state. Power mode should not depend on that preview path; it should consume enemy action lifecycle state instead.

## TODO Boundaries

- Move action lifecycle execution from `CombatManagerCore` into `CombatCore`, with manager acting as scene adapter only.
- Replace direct card-to-move calls with move/action definitions produced before submission to `CombatCore`.
- Move tactical queue/frame-advantage/follow-up/intent-preview ownership into `TacticalModeController`.
- Move power-mode input buffering, cancel checks, and directional variants into `PowerFightingModeController`.
- Make `UIManager` read snapshots from core/mode controllers instead of asking manager whether individual cards are playable.
- Continue moving stance rules/config from `enemy.gd` into character kit data.
- Move card definitions, route tables, generated follow-ups, and repeat-decay tuning out of `DeckManager`/`RouteSystem` into data assets.
- Continue extracting combat result application into a focused resolution system once card/route/stance/frame interactions have more test coverage.
- Continue moving enemy move definitions and AI scoring weights into ruleset/character kit data.
- Let later skins attach to `CharacterRig2D`, and let moves/character kits override animation keys, sockets, and procedural pose data.
- Keep `NORMAL`, `ELITE`, and `BOSS` intent profiles data-shaped so they can become modded enemy definitions.
- Continue replacing implicit manager boolean decision-making with `CombatStateMachine.can_accept_*`, `is_actor_locked`, `current_actor`, and `current_phase_name`.
- Add a real pause/debug inspector, mod/debug console, enemy intent icon display, stance break countdown visual near the enemy, and frame timeline visualization.
