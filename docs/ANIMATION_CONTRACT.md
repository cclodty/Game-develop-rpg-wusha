# Twelve-frame animation integration contract

Every logical clip now contains 12 separately drawn poses. Preserve the original 252 key poses and add 252 genuinely new in-between drawings; do not count duplicated frames, crossfades, recoloring or affine transforms as extra animation. Godot 4.6.3, existing save directory, action durations and combat rules remain unchanged.

## Source sheets and temporal order

Original sheets remain byte-identical under `assets/generated/animation/`: `courier`, `herbalist`, `performer`, `bandit`, `lancer`, `examiner`, `npcs`. Each physical sheet has six columns and six rows. Six combat actors have idle, walk, attack, dodge, hurt and defeat rows. The NPC sheet has rows for shen, lu, tao, zhou, xiao and lin.

New sheets under `assets/generated/animation/inbetweens/` have the same filenames and physical ordering. Each new cell i is a drawn midpoint between original cell i and its successor. Idle/walk and all NPC loops bridge original5 back to original0 in their final new cell. Nonlooping clips use a distinct settled continuation after original5; defeat remains down. Runtime order is original0, midpoint0, original1, midpoint1, ..., original5, midpoint5. There are 42 logical clips and 504 unique pose cells across 14 PNGs.

Keep the established Q-style, face, outfit, weapons and right/front three-quarter viewpoint. All figures and weapons must be physically separated by transparent gutters. Generated spacing may be uneven, so measured regions replace assumed equal-grid slicing. Original PNG pixels are not rewritten.

## Calibration and runtime API

`WeiyuanAnimation` retains `frame`, `loop_frame`, `draw_rect`, `frame_index`, `clip_duration`, `metadata` and `has_actor`. `FRAME_COUNT` is 12; the physical source grid remains 6×6. Metadata exposes every runtime frame's source path, region and padding so QA can verify interleaving and source isolation.

Use one fixed body scale and ground anchor per actor. If the new sheet's nominal standing size differs, calibrate one uniform scale for the entire actor bank (or NPC row), with proportional virtual-canvas/pivot dimensions. Never resize each pose using its own alpha bounds. The target world rectangle remains fixed for all 12 frames. Cache AtlasTexture objects, preserve transparency and clipped linear filtering, and leave dialogue portraits in `art.gd` unchanged.

## Timing, pauses and saves

Idle: 12 frames in 1.0 second (12 fps). Walk: 12 in 0.6 seconds (20 fps). Attack: 0.32s. Dodge: 0.25s. Hurt: 0.24s. Defeat: 0.65s. Loops wrap; action endpoints clamp to frame11.

Combat simulations own damage. The original attack contact pose is now zero-based frame4, at the existing 0.11s hit time. Player anticipation samples frames0–3; the remaining poses follow contact without adding damage callbacks. Enemy windup, strike and recovery retain their gameplay durations while exposing the new intermediate poses. Qi and cloud step retain their existing release/impact rules. Old normalized clocks naturally select the new sequence; do not migrate or reset player progress.

World and arena pause gates freeze animation phases. The settled fight's existing 0.65s noninteractive defeat presentation remains frozen when paused, resumes from saves, and emits its result once. Both previous save generations must retain their compatible defaults.

## Preview and delivery

The title's animation viewer exposes 12 chronological thumbnails in two rows of six, actor/clip selection, pause, backward/forward step, mirroring and half speed. Frame11 advances to0; backward from0 selects11. The viewer never creates or modifies a player save.

Mandatory QA checks all 504 visible/distinct original and new cells, their source attribution, transparent boundaries, fixed scale/pivot, preservation of original PNG hashes, loop duration, contact timing, pause/resume and save compatibility. Inspect old/new transitions in rendered gameplay for body-size jumps and unrelated poses. Browser recording is real gameplay; format conversion does not synthesize frames. Publish the existing source/download branches after verification and keep the earlier prototype branch intact.
