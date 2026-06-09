# Changelog

Major project milestones live here so the README can stay focused on setup, controls, and current project direction.

## 2026-06-05 — Control Mode Validation Merge

- Validated the shared combat core path for two control modes:
  - `TIME_TACTICAL`: card, queue, frame-advantage, and reaction-window play.
  - `POWER_ACTION`: direct fighting-game inputs routed through the same combat rules.
- Formalized `ActionRequest` as the common action primitive for cards, direct input, AI, scripted actions, and debug actions.
- Added or strengthened shared combat architecture pieces:
  - `CombatCore`
  - `ActorCombatState`
  - `CombatStateMachine`
  - `MoveDefinition`
  - `HitboxDefinition`
- Decomposed major chunks of `CombatManager` into focused controllers/systems:
  - `TacticalModeController`
  - `PowerFightingModeController`
  - `EnemyLifecycleController`
  - `PlayerActionLifecycleController`
  - `CombatTraceLogger`
  - `CombatDebugExporter`
- Cleaned up tactical queue ownership so queue orchestration, queue API helpers, display text, and snapshot helpers live closer to tactical systems.
- Preserved shared hitbox, damage, block, whiff, trade, stance, and frame-timing logic across both modes.
- Smoke-tested both `TIME_TACTICAL` and `POWER_ACTION` flows during the validation pass.

Remaining technical debt:

- Extract tactical reward, pressure, follow-up, and trade reward flow out of `CombatManager`.
- Separate enemy reaction and intent resolution from manager-owned tactical flow.
- Move remaining `POWER_ACTION` enemy startup, active, and hitbox resolution ownership into a focused runtime controller.
- Extract combat result reporting and consequence formatting from manager code.
- Begin the roguelike/run/room foundation after the combat authority boundaries settle.

## 2026-06 — Animation / Character Pipeline

Placeholder for the Renka/Kai PNG sequence pipeline, sprite animation integration, and future character animation milestones.

## 2026-05 — UI / Camera / Debug Improvements

Placeholder for the UI readability pass, fighting-game camera work, combat log export, hitbox visualization, and debug overlay milestones.

## 2026-05 — Combat Prototype Foundation

Placeholder for the original deckfighter combat loop, tactical queue, frame advantage, enemy intent, stance break, reaction windows, and prototype combat systems.
