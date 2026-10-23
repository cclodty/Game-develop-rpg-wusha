# Frame animation integration contract

This update replaces runtime pose tilting/bobbing with separately drawn sprite frames, preserving original portraits for dialogue. Godot 4.6.3, same save directory and game rules.

## Generated sheets

All source sheets use a transparent **6 columns × 6 rows** grid. The six-by-six arrangement describes pose order; generated row/column spacing can vary. Measured source regions in `SOURCE_LAYOUTS` retain every authored opaque pixel and exclude neighboring poses. `AtlasTexture.margin` places each region on one fixed virtual canvas per actor, with a shared standing scale and ground pivot. Never assume equal grid boundaries for an uncalibrated sheet, resize individual silhouettes, or rewrite source PNG pixels. Facing is right/front three-quarter, same character proportions/outfit as `assets/generated/characters.png`. Six distinct sequential poses per row; no painted motion blur, shadows, text, grid lines, or particles. No automatic recoloring or synthetic frame warps. Original PNGs remain unchanged; sampling/alignment is runtime metadata.

Actor sheets under `assets/generated/animation/<actor>.png`: `courier`, `herbalist`, `performer`, `bandit`, `lancer`, `examiner`.
Rows: 0 `idle`, 1 `walk`, 2 `attack`, 3 `dodge`, 4 `hurt`, 5 `defeat`. Idle/walk loop; action clips clamp at end. All poses should keep consistent centered feet and head size with enough horizontal weapon margin. Idle/walk hold/sheath role weapon; attacks use sword for all heroes, saber/spear/sword for the three foes.

`npcs.png`: 6 columns × 6 rows; each row is a six-frame idle/occupational gesture loop for `shen`, `lu`, `tao`, `zhou`, `xiao`, `lin`, in that order. No combat frames required for static NPCs.

## Runtime API — scripts/animation_bank.gd

`class_name WeiyuanAnimation extends RefCounted` static functions:
- `has_actor(actor:String)->bool`
- `frame(actor:String, clip:String, normalized_progress:float)->Texture2D`: clamp 0..1; 1 selects last frame. Unknown clip falls back to idle; actor aliases hero→courier.
- `loop_frame(actor:String,clip:String,elapsed:float)->Texture2D`: idle6fps, walk10fps defaults; positive modulo.
- `draw_rect(actor:String, height:float)->Rect2`: fixed scale and ground anchor across all frames; no independent resize to each frame's visible bounds. Adjust actor metadata after inspecting artwork.
- `frame_index(clip:String,normalized_progress:float)->int` and `clip_duration(clip:String)->float` for timing/tests.
- `metadata(actor:String)->Dictionary` exposes path/grid/frame count/anchor for QA.

AtlasTexture objects cached, imports use transparent linear filtering and no mip bleed. Do not overwrite `art.gd` dialogue portraits.

## World

World player draws idle/walk frames using origin id; NPCs draw actor-specific idle frames. Advance animation time only with enabled gameplay input; pause/menu freezes visual phase. Walking uses true alternating foot poses, remove old per-frame body tilt/squash/bounce when atlas available. Persist only relevant phase if needed; walking animations may resume idle after loading town (position authoritative).

## Arena

Animation is driven by existing gameplay simulation clocks, not AnimationPlayer callbacks that duplicate damage. Attack frame2 aligns existing hit at0.11s in0.32s action; skill/dodge/hurt use corresponding clip. Enemy windup maps to first2 attackframes, strike/contact toframe2, recovery tolast3frames. Preserve current timings, telegraphs, attack/hit rules. Player/foe display direction uses horizontal flip. Add explicit animation state/timers to JSON snapshot only if necessary, with backward-compatible defaults. Pausing freezes all clip clocks. A short (~0.65s) noninteractive defeat presentation may precede result UI. Combat is already settled; only presentation advances. Persist its phase for new snapshots, handle old resolved snapshots compatibly, freeze during pause, and never duplicate rewards or emit finished twice.

Visual helpers/state exposed for tests, e.g. `player_animation()->{clip,progress,frame}` and `enemy_animation(enemy)->dict`. No change to public encounter API.

## Delivery

Document actual frame counts, directions and any remaining limitations honestly. Provide a Godot preview scene with clip/actor controls and pause/step to review individual frames. Test real atlas regions, distinct frames, pause/resume, hit-frame alignment, legacy save defaults, and actual browser playback. Publish updated existing source/download branches only after validation; keep old game branch untouched.
