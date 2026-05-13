# deckfighter-prototype

A tactical fighting-game / deckbuilder hybrid prototype built in Godot.

**Core idea:** combine fighting-game frame logic with tactical decision making, spacing, stance pressure, interrupts, trades, combo routing, and readable cinematic combat timing.

> Current status: experimental prototype / vertical slice.

---

## Overview

`deckfighter-prototype` explores a combat system where players think like fighting-game players while interacting through a tactical/action hybrid structure.

The project currently focuses on:

- Frame advantage and disadvantage
- Startup / active / recovery timing
- Tactical queueing
- Spacing and whiff punishment
- Stance damage and stance break states
- Combo follow-up routing
- Enemy AI decision profiles
- Procedural stick-rig combat visualization
- Future bullet-time reaction windows

The long-term direction is:

```text
real-time tactical fighting combat with bullet-time reaction windows
```

rather than strict turn-based combat.

---

## Current Prototype Features

### Combat Systems

- Frame advantage / disadvantage system
- Persistent initiative carryover
- Startup / active / recovery timing
- Effective startup calculation
- Interrupt system
- Trade system
- Spacing and whiff punish logic
- Hit levels:
  - `HIGH`
  - `MID`
  - `LOW`
  - `OVERHEAD`
- Queue-based tactical action system
- Follow-up combo routing
- Repeat move decay
- Punish window logic

### Stance System

- Stance damage
- Stance break states
- Protected recovery after break
- Break stun states
- Recovery timers

### Enemy AI

- Enemy tiers:
  - `NORMAL`
  - `ELITE`
  - `BOSS`
- Punish evaluation
- Spacing-aware decision making
- Pressure / mash / block states
- AI scoring system
- AI debug output

### Animation / Visualization

- Procedural stick-rig placeholder fighters
- Startup / active / recovery visualization
- Hitbox visibility during active frames
- Compact intent markers
- Action phase visualization

### Debug / UI

- Combat log
- Frame/timing debug panels
- Enemy AI debug panels
- Toggleable debug views
- Expanded combat HUD

---

## Combat Direction

The project is moving toward:

- Readable reaction-based combat
- Cinematic slow-motion pressure windows
- Fighting-game style momentum
- Tactical decision making under pressure
- Visual telegraph readability

A key design goal is to avoid exposing raw frame numbers during normal play. Instead, the game should communicate danger and timing through animation, impact bars, telegraphs, hitstop, and visual pressure.

---

## Controls

Current prototype controls may change during development.

### Movement

| Input | Action |
|---|---|
| `A / D` | Move |
| `Space` | Jump |
| `L` | Backstep |

### Defense

| Input | Action |
|---|---|
| `J` | Block |
| `K` | Crouch block |

### Combat

| Input | Action |
|---|---|
| Mouse | Select cards / queue actions |

### Debug

| Input | Action |
|---|---|
| `F1-F4` | Toggle debug panels |

---

## Planned Features

### Combat Expansion

- Bullet-time focus windows
- Real-time slow-motion combat flow
- Better hitstop and impact feedback
- Advanced spacing interactions
- Air combat expansion
- Grapples / throws
- Armor / parry systems
- Counter-hit system
- Guard crush / pressure states

### Animation

- Full animation timeline system
- Bone/socket-driven combat rig
- Root motion support
- Better attack telegraphs
- Procedural animation blending
- Character skin layering

### Enemy Expansion

- Boss phases
- Unique boss mechanics
- Scripted enemy sequences
- Advanced pressure AI
- Archetype-based enemy behavior

### Modding Support

Planned long-term support for:

- Custom characters
- Custom cards
- Custom enemy AI profiles
- Custom movesets
- External combat data
- Animation overrides

### Game Modes

- Training mode
- Replay viewer
- Combat sandbox
- Roguelike progression structure
- Boss encounters
- Challenge fights

### UX / Accessibility

- Better onboarding/tutorial system
- Combat glossary
- Optional frame data display
- Timeline visualization
- Hitbox viewer
- Controller support

---

## Project Structure

```text
scenes/
scripts/
  animation/
  combat/
  enemy/
  ui/
docs/
```

Combat systems are being refactored toward modular architecture for:

- Maintainability
- Extensibility
- Mod support
- Future character expansion

---

## Architecture

See:

```text
docs/combat_architecture.md
```

for the current combat system direction and planned modular structure.

---

## Engine

- Godot 4.x

---

## Development Status

This is a work-in-progress prototype.

Art, polish, progression systems, final balance, onboarding, and final presentation are still placeholder / WIP.

---

## License

TBD
