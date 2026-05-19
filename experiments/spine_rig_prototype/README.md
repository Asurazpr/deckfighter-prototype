# Spine Humanoid Combat Rig

This folder contains a Spine-runtime-ready humanoid character export for combat animation experiments.

## Runtime Files

- `export/humanoid-combat.json` - Spine JSON skeleton export, marked as Spine 4.3.02-compatible JSON.
- `export/humanoid-combat.atlas` - PNG atlas descriptor.
- `export/humanoid-combat.png` - packed atlas page.
- `images/*.png` - individual segmented source body pieces.
- `humanoid-combat.spine-project.json` - reproducible project manifest and notes.

## Rig Notes

- Average adult male proportions, approximately 7.5 heads tall.
- Longer lower body: legs occupy nearly half the body height.
- Neutral relaxed A-pose tuned for a 30-45 degree three-quarter combat stance.
- Side-biased movement and attack tests are provided in `walk_side` and `jab_turn`.
- `walk_side_v3` is a rough pose-driven walk cycle: thighs, shins, feet, arms, pelvis, and chest are keyed to test actual limb motion rather than foot sliding.
- `root_master` is the world/gameplay root at the ground line between the feet.
- `pelvis_root` handles body motion above the gameplay root.
- Spine chain: `pelvis_root -> abdomen -> chest -> neck -> head`, with local bone axes pointing up the torso chain.
- Arm grouping: `chest -> arms -> shoulder -> upper_arm -> forearm -> hand`.
- Leg grouping: `pelvis_root -> legs -> thigh -> shin -> foot`.
- Feet are authored to sit on the y=0 baseline in the setup pose.
- Shoulder and hip cap pieces overlap the limbs and torso to avoid visible gaps during early rotation tests.

## Placeholder Animations

- `idle`
- `idle_3q`
- `walk`
- `walk_side`
- `walk_side_v2`
- `walk_side_v3`
- `jab`
- `jab_turn`
- `hurt`
- `joint_debug`

The animations are intentionally plain. They are there to validate hierarchy, pivots, silhouette, and Spine-to-Godot import.

## Spine Editor Note

Spine's native `.spine` editor file is a proprietary save format. This package provides the portable Spine JSON/atlas/PNG structure that the Spine editor and spine-godot runtime can consume. To create a native `.spine` file, import `export/humanoid-combat.json` into Spine and save it from the editor.
