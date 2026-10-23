# Integration contract — 江湖未遠

Independent project: Godot 4.6.3 standard. Existing game and its save directory remain separate.
Logical viewport 1440×900. Both world and arena are Node2D, logical playfield **1080×640**, positioned by the main UI at (28, 136). They do not create Camera2D or full-screen HUD. Parent owns menus/dialogues/save flow. Main clips the playfield in a Control and keeps scene input separate from modal controls.

## Shared identifiers

- Origins: `herbalist` 藥鋪學徒, `courier` 驛站跑腿, `performer` 戲班子弟.
- NPCs: `shen` 沈照嶺 (照嶺門師傅), `lu` 陸行雲 (渡雲社引路人), `tao` 陶半夏 (藥鋪), `zhou` 周望山 (驛站), `xiao` 蕭小滿 (戲班), `lin` 林知微 (鎮史與舊路).
- Locations: `wangxi` 望溪鎮, `grove` 青篁溪谷, `ridge` 望風古道.
- Skills: `sword_qi` 破雲劍氣, `cloud_step` 掠影突進. Schools: `zhaoling`, `duyun`, ending `stay`.
- Parent handles keys/menu focus. World/arena must honor `set_input_enabled(false)` including held mouse buttons.

## Rules (`scripts/game_data.gd`, `scripts/run_state.gd`)

`WeiyuanData` provides constants `ORIGINS` (dictionary keyed by origin; name/description/perk), `NPCS` (name/role/description), `ACTIVITIES` (dictionary keyed by activity id). Activities have `name`, `npc`, `cost` (slots), `kind` (story/battle/explore/task/rest), `description`, `reward_text`, `repeatable`, optional `location` and `battle`.

`WeiyuanRun extends RefCounted`: public `data:Dictionary`, `new_run(hero_name, origin)`, `day()->int`, `period()->String`, `remaining()->int`, `ready_for_exam()->bool`, `has_skill(id)->bool`, `activity_status(id)->Dictionary {ok,message}`, `begin_activity(id)->Dictionary {ok,message}`, `complete_activity(outcome="success",detail={})->Dictionary {ok,message}`, `retreat_activity(detail={})->Dictionary`, `retry_activity()->Dictionary`, `begin_exam()->Dictionary`, `complete_exam(won:bool,detail={})->Dictionary`, `choose_school(id)->Dictionary`, `save_game(path=SAVE_PATH)->Dictionary`, `load_game(path=SAVE_PATH)->Dictionary`, `story_context()->Dictionary`.

Data includes `hero_name`, `origin`, `spent` (0–21), `money`, `medicine`, `training`, `insight`, `favor` (NPC→int), `skills` (Array[String]), `completed` (Array[String]), `journal` (Array[Dictionary] with text), `pending` (Dictionary), `phase`, `exam_result` (Dictionary with eligible Array and won bool), `school`. Origin is independent of eligibility. Pending is created and time charged exactly once before the activity; saved before gameplay. Parent may add JSON-safe `stage`, `visited`, `combat`, `world_position`, `report`, `battle_won` fields to pending to resume; loading should retain and validate these. Combat `detail.medicine_used` commits at settlement; retry restores the original encounter and never charges again. Completion/retreat clears pending, repeat callbacks rejected. Bind `pending_token` when starting a callback, and pass it with result reports. The main scene reconciles activity transitions when loading completed objectives or a pending encounter.

## Walking world

`scripts/world.gd` Node2D: `configure(location:String, origin:String="herbalist", initial_position:Vector2=Vector2(-1,-1))`, `set_objectives(objectives:Array)` where entries have id/label/position (Vector2 or [x,y]), `set_input_enabled(bool)`, `get_player_position()->Vector2`.
Signals `npc_requested(id:String)`, `hotspot_requested(id:String)`, `exit_requested(destination:String)`.
Town has six reachable NPCs and map exits; F/Enter or click approach+interact. Walk WASD/arrows, click ground to move. Clear blocked boundaries, unobstructed paths; no clock mutation. Objectives for tasks/exploration supplied by parent. Main owns activity completion and encounters.

## Arena

`scripts/arena.gd` Node2D: `configure(mode:String, stats:Dictionary, restore:Dictionary={})`, `set_input_enabled(bool)`, `snapshot()->Dictionary`, `status()->Dictionary`, `use_medicine()`.
Modes `practice`, `spar`, `grove`, `ridge`, `exam`. Stats keys `training`, `insight`, `skills`, `medicine`, `origin`, `exam_aid`.
Signals `finished(won:bool,report:Dictionary)`, `status_changed(status:Dictionary)`.
Report includes `medicine_used`, hits/dodges optional. Status includes hp/max_hp/stamina/max_stamina, medicine left, wave, enemies count, skill cooldowns optional. Snapshot contains position/HP/enemy state/cooldowns/used medicine and must restore safely; retry uses fresh configure, not snapshot. Root saves snapshot periodically and before pause.
Movement WASD/arrows, left mouse/J attack, Space dodge, Q and E skill slots, R heal. Telegraphs and hit pause/feedback, one sword weapon, two enemy types and exam boss. No paid/API dependencies. Parent owns win/lose/retry/retreat UI and all run rewards.

## Story

`story/first_week.dialogue` Dialogue Manager v3.10.4. Required titles `intro_herbalist`, `intro_courier`, `intro_performer`, `npc_shen`, `npc_lu`, `npc_tao`, `npc_zhou`, `npc_xiao`, `npc_lin`, `exam_intro`, `ending_zhaoling`, `ending_duyun`, `ending_stay`. All 16 activities have `activity_<id>` titles. Battle/task/exploration activities also have `complete_<id>` success scenes. Context keys `hero_name`, `origin`, `day`, `remaining`, `training`, `insight`; NPC dialogue can branch on these. All lines/choices have stable unique [ID:...] keys. `[ #portrait=...]` without the space is supported; actual syntax `[#portrait=shen]`. No direct mutations/rewards in dialogue. For story/rest activities, END settles the activity. For battle/task/exploration, END of the briefing launches gameplay; END of the success scene settles it. Questions can return to menu. Provide story bible + full new design documentation.

## Art

`scripts/art.gd` class `WeiyuanArt` static `portrait(id:String)->Texture2D`, `location(id:String)->Texture2D`, `title_background()->Texture2D`, optional `icon(id)`. Portrait ids hero (may aliases origins), six NPC ids, bandit, lancer, examiner. New consistent generated chibi art; raw originals under assets/generated; atlas regions may be sampled at runtime without editing source image pixels. Text is drawn by Godot, not inside illustrations. Document provenance. World and arena use `WeiyuanAnimation` for the separately drawn motion frames; `WeiyuanArt` remains the dialogue portrait/background adapter. The main scene draws text and UI separately. See `ANIMATION_CONTRACT.md` for atlas layout, fixed ground anchors, clip timings, pause/save rules and the frame preview scene.
