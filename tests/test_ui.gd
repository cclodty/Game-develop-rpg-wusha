extends SceneTree
## Use real scene buttons/input. Only exam-result presentation uses fixtures;
## the schedule and qualification rules have their own public-API suite.

const MainScene = preload("res://scenes/main.tscn")
const Run = preload("res://scripts/run_state.gd")
var passed = 0
var failed = 0
var app: Control


func _initialize() -> void:
	call_deferred("_run")


func expect(condition: bool, description: String) -> void:
	if condition:
		passed += 1
		print("PASS UI: " + description)
	else:
		failed += 1
		push_error("FAIL UI: " + description)


func press(action: String) -> bool:
	var button = app.action_buttons.get(action)
	if not is_instance_valid(button) or not button.is_visible_in_tree() or button.disabled:
		expect(false, "visible enabled action: " + action)
		return false
	button.pressed.emit()
	return true


func frames(count: int = 2) -> void:
	for _frame in range(count): await process_frame


func fit(view: String) -> void:
	var outside: Array = []
	var viewport = Rect2(Vector2.ZERO, Vector2(1440, 900))
	for key in app.action_buttons:
		var button = app.action_buttons[key]
		if is_instance_valid(button) and button.is_visible_in_tree():
			var ancestor: Node = button.get_parent()
			var clipped_out = false
			while ancestor != app and ancestor != null:
				if ancestor is ScrollContainer and not ancestor.get_global_rect().intersects(button.get_global_rect()): clipped_out = true
				ancestor = ancestor.get_parent()
			if clipped_out: continue
			if not viewport.grow(1).encloses(button.get_global_rect()): outside.append(key)
	expect(outside.is_empty(), view + " buttons fit the design viewport: " + str(outside))


func wait_story() -> bool:
	for _frame in range(160):
		await process_frame
		if app._overlay_kind == "dialogue" and app.story_line != null and not app._story_busy:
			return true
	expect(false, "dialogue reaches an actionable line")
	return false


func finish_story() -> bool:
	for _step in range(130):
		await frames()
		if app._overlay_kind != "dialogue": return true
		if not await wait_story(): return false
		if app.story_line.responses.is_empty():
			if not press("dialogue_next"): return false
		else:
			# Authored question hubs put the return-to-gameplay choice last.
			if not press("dialogue_response_" + str(app.story_line.responses.size() - 1)): return false
	expect(false, "dialogue completes within the finite authored flow")
	return false


func key(code: Key, held: bool = true) -> void:
	var event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = held
	Input.parse_input_event(event)


func new_origin(origin: String) -> bool:
	press("new_game")
	await frames()
	fit("character creation")
	press("origin_" + origin)
	app.name_entry.text = "試玩行者"
	press("create")
	if not await wait_story(): return false
	expect(app.run.data.hero_name == "試玩行者" and app.run.data.origin == origin, origin + ": creation retains name and origin")
	expect(str(app.run.data.dialogue.get("title", "")) == "intro_" + origin, origin + ": authored opening is selected")
	fit("origin dialogue")
	if not await finish_story(): return false
	expect(app._screen == "game" and is_instance_valid(app.world) and app.current_location == "wangxi", origin + ": opening reaches walkable Wangxi town")
	expect(app.run.data.spent == 0 and app.run.remaining() == 21, origin + ": reading the opening costs no calendar slots")
	return true


func _run() -> void:
	if FileAccess.file_exists(Run.SAVE_PATH):
		push_error("UI tests require a fresh XDG_DATA_HOME; refusing to overwrite an existing save.")
		quit(2)
		return
	root.size = Vector2i(1440, 900)
	app = MainScene.instantiate()
	root.add_child(app)
	await frames(3)
	expect(app.action_buttons.has("new_game") and app.action_buttons["continue"].disabled, "fresh title offers creation and disables missing save")
	fit("title")
	await test_animation_preview()
	for origin in ["herbalist", "courier", "performer"]:
		if not await new_origin(origin):
			await _finish()
			return
		press("pause")
		await frames()
		press("save_exit")
		await frames()
		expect(app._screen == "title" and not app.action_buttons["continue"].disabled, origin + ": save and return enables Continue")
	press("continue")
	await frames(5)
	expect(app.run.data.origin == "performer" and is_instance_valid(app.world), "Continue restores the last named origin into town")
	await test_world_and_activities()
	await test_checkpoint_recovery()
	await test_exam_results()
	await _finish()


func test_animation_preview() -> void:
	if not press("animation_preview"): return
	await frames(3)
	var preview = app.animation_preview
	expect(is_instance_valid(preview), "title opens the live frame-animation preview")
	if not is_instance_valid(preview): return
	expect(preview.animation_state().frame_count == 12, "preview exposes twelve real frames per clip")
	fit("animation preview")
	press("actor_courier")
	press("clip_walk")
	var before: float = preview.animation_state().elapsed
	await create_timer(0.18).timeout
	expect(preview.animation_state().elapsed > before, "preview playback advances its real animation clock")
	press("preview_pause")
	var frozen: Dictionary = preview.animation_state().duplicate(true)
	await create_timer(0.18).timeout
	expect(preview.animation_state() == frozen, "preview pause holds both phase and frame")
	for index in range(12):
		press("frame_" + str(index))
		expect(preview.animation_state().frame == index and not preview.animation_state().playing, "frame-strip selection shows drawn frame %d of 12 and pauses" % (index + 1))
	press("preview_step")
	expect(preview.animation_state().frame == 0, "stepping past the last pose wraps to frame zero")
	press("preview_previous")
	expect(preview.animation_state().frame == 11, "previous-frame control wraps to the twelfth pose")
	press("preview_flip")
	expect(preview.animation_state().mirrored, "preview can review the mirrored left-facing presentation")
	press("preview_speed")
	expect(preview.animation_state().rate == 0.5, "half-speed playback is available for timing review")
	for actor in ["courier", "herbalist", "performer", "bandit", "lancer", "examiner"]:
		press("actor_" + actor)
		for clip in ["idle", "walk", "attack", "dodge", "hurt", "defeat"]:
			press("clip_" + clip)
			expect(preview.animation_state().actor == actor and preview.animation_state().clip == clip, actor + ": preview selects authored " + clip + " clip")
	for actor in ["shen", "lu", "tao", "zhou", "xiao", "lin"]:
		press("actor_" + actor)
		expect(preview.animation_state().actor == actor and preview.animation_state().clip == "idle" and app.action_buttons["clip_attack"].disabled, actor + ": NPC preview offers its dedicated idle loop")
	press("preview_back")
	await frames(3)
	expect(app.action_buttons.has("new_game") and not FileAccess.file_exists(Run.SAVE_PATH), "returning from animation review leaves the title and player save untouched")


func test_world_and_activities() -> void:
	var before: Vector2 = app.world.get_player_position()
	key(KEY_D)
	await create_timer(0.3).timeout
	key(KEY_D, false)
	expect(app.world.get_player_position().distance_to(before) > 20.0 and app.run.data.spent == 0, "keyboard walking moves the character without consuming a slot")
	for menu in ["map", "journal", "planner"]:
		press(menu)
		await frames()
		expect(app._overlay_kind == menu, menu + " opens from town")
		fit(menu)
		press("close")
		await frames()
	# Let the world's ordinary pathfinding reach a real NPC, without teleporting.
	press("guide")
	for _step in range(900):
		if app._overlay_kind == "dialogue": break
		app.world._physics_process(1.0 / 60.0)
	if not await wait_story(): return
	expect(app.run.data.dialogue.title == "npc_shen", "town navigation reaches Shen and triggers his authored dialogue")
	if not await finish_story(): return
	expect(app._overlay_kind == "npc" and app.run.data.spent == 0, "NPC questions return to activities without spending time")
	press("activity_sword_lesson")
	await frames()
	fit("activity cost confirmation")
	expect(app._overlay_kind == "confirm" and app.run.data.spent == 0, "opening an activity shows its cost before charging it")
	press("cancel")
	await frames()
	expect(app.run.data.spent == 0, "cancelling an activity preserves all slots")
	press("activity_sword_lesson")
	press("confirm_activity")
	if not await wait_story(): return
	expect(app.run.data.spent == 2 and not app.run.has_skill("sword_qi"), "lesson charges two slots once and withholds its skill until the scene is complete")
	press("dialogue_next")
	if not await wait_story(): return
	var cursor = app.story_line.id
	press("save_exit")
	await frames()
	press("continue")
	if not await wait_story(): return
	expect(app.story_line.id == cursor and app.run.data.spent == 2, "mid-lesson Continue restores the precise line without charging again")
	if not await finish_story(): return
	expect(app.run.has_skill("sword_qi") and app.run.data.training == 2 and app.run.data.pending.is_empty() and app.run.data.spent == 2, "finishing the lesson grants sword qi and training exactly once")
	press("planner")
	await frames()
	expect(app.action_buttons["activity_sword_lesson"].disabled, "completed one-time lesson cannot be booked again")
	press("activity_practice")
	press("confirm_activity")
	if not await finish_story(): return
	expect(is_instance_valid(app.arena) and app.run.data.pending.stage == "combat" and app.run.data.spent == 3, "practice briefing opens actual real-time combat with one additional slot")
	fit("combat HUD")
	app.arena.set_process(false)
	for _step in range(90): app.arena.step_simulation(1.0 / 60.0)
	key(KEY_SPACE)
	key(KEY_SPACE, false)
	await frames()
	expect(app.arena.snapshot().dodge_timer > 0.0, "Space input reaches the arena dodge through the live scene")
	for _step in range(30): app.arena.step_simulation(1.0 / 60.0)
	key(KEY_Q)
	key(KEY_Q, false)
	await frames()
	expect(app.arena.snapshot().qi_cooldown > 0.0, "Q input casts the skill learned from the lesson")
	press("pause")
	await frames()
	fit("pause")
	var frozen: Dictionary = app.arena.snapshot().duplicate(true)
	for _step in range(120): app.arena.step_simulation(1.0 / 60.0)
	expect(app.arena.snapshot() == frozen, "pause freezes enemies, projectiles, cooldowns and player state")
	press("save_exit")
	await frames()
	press("continue")
	press("pause")
	await frames()
	var restored: Dictionary = app.arena.snapshot()
	expect(restored.position == frozen.position and restored.wave == frozen.wave and restored.hp == frozen.hp and restored.enemies.size() == frozen.enemies.size() and is_equal_approx(restored.qi_cooldown, frozen.qi_cooldown), "Continue reconstructs the saved battlefield, health and skill cooldown")
	expect(app.run.data.spent == 3, "combat Continue does not pay its activity cost again")
	press("resume")
	app.arena.set_process(false)
	# Genuine enemy simulation defeats an idle player; no health/result injection.
	for _step in range(16000):
		if app._overlay_kind == "defeat": break
		app.arena.step_simulation(1.0 / 60.0)
	expect(app._overlay_kind == "defeat", "real enemy attacks reach the defeat/retry presentation")
	if app._overlay_kind != "defeat": return
	fit("defeat")
	press("retry")
	await frames()
	expect(app.run.data.spent == 3 and app.run.data.pending.attempt == 1 and app.arena.status().hp == app.arena.status().max_hp, "Retry rebuilds the encounter at full health without extra time")
	press("retreat")
	await frames()
	press("retreat")
	await frames()
	expect(app.run.data.pending.is_empty() and app.run.data.spent == 3 and app.run.data.training == 2 and is_instance_valid(app.world), "retreat returns to town, retains spent time and withholds practice reward")


func restore_fixture() -> void:
	expect(app.run.save_game().ok, "transitional fixture uses the production save validator")
	app._show_title()
	press("continue")
	await frames(4)


func test_checkpoint_recovery() -> void:
	# Emulate a process stopping after writing the last objective but before the
	# scene transition. Fixtures are persisted through the production save layer.
	app.run.new_run("斷點行者", "courier")
	app.run.data.phase = "town"
	app.run.begin_activity("courier_work")
	app.run.data.pending.stage = "task"
	app.run.data.pending.visited = ["first", "second"]
	await restore_fixture()
	if not await finish_story(): return
	expect(app.run.data.pending.is_empty() and "courier_work" in app.run.data.completed and app.run.data.spent == 1 and app.run.data.money == 66, "Continue settles the last town objective once after an interrupted transition")
	app.run.new_run("斷點行者", "herbalist")
	app.run.data.phase = "town"
	app.run.begin_activity("herb_errand")
	app.run.data.pending.stage = "explore"
	app.run.data.pending.visited = ["first", "second", "danger"]
	await restore_fixture()
	expect(is_instance_valid(app.arena) and app.run.data.pending.stage == "combat" and app.run.data.spent == 2, "a saved danger marker resumes its required battle without recharging time")
	press("retreat")
	press("retreat")
	await frames()
	app.run.new_run("斷點行者", "herbalist")
	app.run.data.phase = "town"
	app.run.begin_activity("herb_errand")
	app.run.data.pending.stage = "explore"
	app.run.data.pending.visited = ["first", "second", "danger"]
	app.run.data.pending.battle_won = true
	app.run.data.pending.report = {"medicine_used": 1}
	await restore_fixture()
	if not await finish_story(): return
	expect(app.run.data.pending.is_empty() and "herb_errand" in app.run.data.completed and app.run.data.spent == 2 and app.run.data.medicine == 7, "completed exploration resumes debrief and settles its medicine/reward once")
	app.run.save_game()
	app.run.save_game()
	DirAccess.remove_absolute(Run.SAVE_PATH)
	app._show_title()
	expect(not app.action_buttons["continue"].disabled, "title offers Continue when only a validated backup save survives")
	press("continue")
	await frames(4)
	expect(app.run.data.spent == 2 and app.run.data.medicine == 7 and is_instance_valid(app.world), "backup-only Continue recovers the already-settled exploration")


func test_exam_results() -> void:
	# Purpose-built presentation fixtures let every origin see every ending;
	# test_run_state.gd separately proves both preparations are achievable in 21 slots.
	for origin in ["herbalist", "courier", "performer"]:
		for school in ["zhaoling", "duyun", "stay"]:
			app.run.new_run("結局行者", origin)
			app.run.data.phase = "town"
			app.run.data.spent = 21
			app.run.data.training = 6
			app.run.data.insight = 6
			app.run.data.favor.shen = 2
			app.run.data.favor.lu = 2
			app.run.data.completed = ["missing_letter", "ridge_tracks", "herb_errand"]
			app._recover_screen()
			press("exam")
			await frames()
			fit("exam confirmation")
			press("exam_confirm")
			if not await finish_story(): return
			expect(is_instance_valid(app.arena) and app.arena.mode == "exam", origin + ": eighth-day exam intro opens the examiner encounter")
			press("retreat")
			press("retreat")
			await frames()
			expect(app._overlay_kind == "results" and not app.run.data.exam_result.won and app.run.data.exam_result.eligible.size() == 2, origin + ": concession still evaluates both earned invitations")
			fit("school results")
			press("school_" + school)
			if not await finish_story(): return
			expect(app.run.data.school == school and app.run.data.phase == "ending" and app.action_buttons.has("new_game"), origin + " reaches authored " + school + " ending and replay option")
			fit("ending")
	app.run.new_run("留鎮行者", "herbalist")
	app.run.data.phase = "town"
	app._recover_screen()
	press("planner")
	press("exam")
	expect(app.run.data.spent == 0, "early exam confirmation does not silently discard remaining preparation")
	press("exam_confirm")
	if not await finish_story(): return
	press("retreat")
	press("retreat")
	await frames()
	expect(app.run.data.spent == 21 and app.action_buttons["school_zhaoling"].disabled and app.action_buttons["school_duyun"].disabled and not app.action_buttons["school_stay"].disabled, "unprepared concession keeps the stay ending available and explains unavailable invitations")
	press("school_stay")
	if not await finish_story(): return
	expect(app.run.data.school == "stay", "a losing/unprepared player can finish the chapter without forced retries")


func _finish() -> void:
	if is_instance_valid(app):
		app.queue_free()
		await process_frame
		# AudioServer releases stopped playback on its own mixing cycle.
		# Let that cycle finish before an immediate headless-process shutdown.
		await create_timer(0.2).timeout
	print("TESTS COMPLETE: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
