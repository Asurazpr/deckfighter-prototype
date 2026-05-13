# Combat Architecture

`scenes/Arena.tscn` uses `res://scripts/combat/combat_manager.gd` as the active combat manager. The old root-level `scripts/combat_manager.gd` should stay removed so there is only one combat manager script in play.

## CombatManager

`CombatManagerCore` owns high-level match flow, input routing, state transitions, combat logs, UI-facing debug text, and coordination between systems. It should not become the home for new gameplay rules. When adding combat behavior, prefer placing the rule in the relevant system and keeping the manager as the caller/orchestrator.

Current combat states are beginning to route through `CombatFlowState` in `CombatManagerCore`, while legacy flags still drive the actual flow. Future explicit state-machine work should preserve the current debug labels and gameplay behavior while making the enum authoritative.

## Systems

- `CombatClock`: single combat-frame advancement entry point. It ticks startup, vulnerability, and stance timers using combat frames.
- `CombatTimeline`: lightweight visual/action timeline for startup, active, impact, recovery, movement, hitbox windows, and animation keys. It consumes combat-frame advancement and should never become the authority for gameplay timing.
- `QueueResolver`: tactical action queue, frozen card snapshots, queue text, duplicate card instance checks, queue clearing, and trade interruption flags.
- `FrameSystem`: frame advantage math, effective enemy startup, initiative carry-over helpers, and punish-window calculation.
- `StanceSystem`: public stance facade for combat code. It forwards to `enemy.gd` for now, but callers should use this system for stance state, protection, break timers, and stance damage application.
- `RouteSystem`: combo route reset, repeat-move decay, route helpers, and future follow-up/draw rules.
- `MovementSystem`: duel spacing, step/backstep/jump movement, movement frame costs, and card spacing effects.
- `HitboxSystem`: hurtbox and attack hitbox construction, hit prediction, debug hitbox lifetimes, and future active collision-window hooks.
- `TradeSystem`: trade recovery values and post-trade frame advantage calculation.
- `EnemyAISystem`: enemy decision state, tier/profile config, situation scoring, spacing checks, punish candidate selection, pressure reactions, boss phase hooks, and enemy intent choice.
- `CharacterRig2D` / `CombatAnimationDriver`: placeholder stick-rig visuals and pose mapping for combat phases. These are visual consumers of timeline data only; they do not decide hits, damage, frame advantage, or timing.

## Data Direction

Future cards, moves, character kits, movement profiles, and rulesets should become data-driven. Avoid hardcoding new move-specific behavior in `CombatManagerCore`; prefer card/move definitions or system-level config that can later be loaded from external data.

Enemy attack definitions now live in `scripts/enemy/enemy_move_data.gd`, and stance defaults live in `scripts/enemy/enemy_stance_config.gd`. `enemy.gd` still owns runtime enemy state for now, but new enemy move/timing config should be added through data-shaped enemy config files instead of inline runtime logic.

Animation and timing should consume combat-frame data from the systems. Animation should not become the authority for combat logic timing. Placeholder combat visuals should read from `CombatTimeline`, while final animation/camera/focus-window work should keep `CombatClock` and combat rules as the source of truth.

## TODO Boundaries

- Continue moving stance rules/config from `enemy.gd` into character kit data.
- Move card definitions, route tables, generated follow-ups, and repeat-decay tuning out of `DeckManager`/`RouteSystem` into data assets.
- Continue moving enemy move definitions and AI scoring weights into ruleset/character kit data.
- Let later skins attach to `CharacterRig2D`, and let moves/character kits override animation keys, sockets, and procedural pose data.
- Keep `NORMAL`, `ELITE`, and `BOSS` intent profiles data-shaped so they can become modded enemy definitions.
- Keep debug UI stable while replacing implicit manager booleans with a clearer explicit state enum.
- Add a real pause/debug inspector, mod/debug console, enemy intent icon display, stance break countdown visual near the enemy, and frame timeline visualization.
