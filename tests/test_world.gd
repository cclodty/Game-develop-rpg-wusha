extends SceneTree
## Spatial and interaction regressions; run headless with --script tests/test_world.gd.

const World = preload("res://scripts/world.gd")
var failed: int = 0
var checks: int = 0
var interactions: Array[String] = []
var world: Node2D


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error(description)


func _simulate(seconds: float) -> void:
	for _step in range(int(seconds * 60.0)):
		world._physics_process(1.0 / 60.0)


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _click(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	world._unhandled_input(event)


func _animation_regressions() -> void:
	for hero_origin: String in ["herbalist", "courier", "performer"]:
		world.set_input_enabled(true)
		world.configure("wangxi", hero_origin)
		var first: Dictionary = world.player_animation()
		_check(first.actor == hero_origin and first.clip == "idle", "World selects the chosen origin's idle animation: " + hero_origin)
		_simulate(0.23)
		_check(world.player_animation().frame != first.frame, "Idle advances through separate frames: " + hero_origin)
		_key(KEY_D, true)
		_simulate(0.23)
		_key(KEY_D, false)
		var walking: Dictionary = world.player_animation()
		_check(walking.clip == "walk" and walking.frame > 0, "Real movement selects and advances walk poses: " + hero_origin)
		var npc_poses: Dictionary = {}
		for npc: String in ["shen", "lu", "tao", "zhou", "xiao", "lin"]:
			npc_poses[npc] = world.npc_animation(npc)
		var ground: Vector2 = world.get_player_position()
		world.set_input_enabled(false)
		_simulate(2.13)
		var paused: Dictionary = world.player_animation()
		_check(paused.clip == walking.clip and paused.frame == walking.frame and paused.elapsed == walking.elapsed, "Opening a menu freezes the exact hero pose: " + hero_origin)
		var npcs_frozen: bool = true
		for npc: String in npc_poses:
			var pose: Dictionary = world.npc_animation(npc)
			npcs_frozen = npcs_frozen and pose.frame == npc_poses[npc].frame and pose.elapsed == npc_poses[npc].elapsed
		_check(npcs_frozen, "All six occupational gesture loops freeze during a menu: " + hero_origin)
		world.set_input_enabled(true)
		_simulate(0.23)
		_check(world.player_animation().clip == "idle" and world.get_player_position() == ground, "Resuming a cancelled journey returns to idle without sliding: " + hero_origin)
		_check(world.npc_animation("shen").elapsed > npc_poses.shen.elapsed, "NPC gesture timing resumes after the menu: " + hero_origin)
		if FileAccess.file_exists("res://assets/generated/animation/" + hero_origin + ".png"):
			_check(world.player_animation().animated, "Present origin sheet is used instead of a portrait: " + hero_origin)
	if FileAccess.file_exists("res://assets/generated/animation/npcs.png"):
		for npc: String in ["shen", "lu", "tao", "zhou", "xiao", "lin"]:
			_check(world.npc_animation(npc).animated, "Town NPC uses its generated gesture frames: " + npc)
	# Hiding the world without an input event must also freeze its visual clocks.
	var before_hide: Dictionary = world.player_animation()
	world.hide()
	_simulate(0.4)
	_check(world.player_animation().elapsed == before_hide.elapsed, "Hidden world cannot advance actor clocks")
	world.show()


func _run() -> void:
	world = World.new()
	root.add_child(world)
	world.set_physics_process(false)
	world.npc_requested.connect(func(id: String): interactions.append(id))
	world.hotspot_requested.connect(func(id: String): interactions.append(id))
	world.exit_requested.connect(func(id: String): interactions.append(id))
	# Inputs use the same offset as the main game's playfield.
	world.position = Vector2(28, 136)
	world.configure("wangxi")
	_key(KEY_D, true)
	_simulate(0.4)
	_key(KEY_D, false)
	_check(world.get_player_position().x > 620.0, "Physical WASD input moves the character")
	world.set_input_enabled(false)
	var disabled_position: Vector2 = world.get_player_position()
	_key(KEY_W, true)
	_simulate(0.4)
	_key(KEY_W, false)
	_click(Vector2(268, 334))
	_check(world.get_player_position() == disabled_position and interactions.is_empty(), "Disabled input blocks held keys and clicks")
	world.set_input_enabled(true)
	world.configure("wangxi")
	_click(Vector2(1160, 350))
	_simulate(2.0)
	_check(world.get_player_position() == Vector2(540, 550), "Clicking UI outside the playfield cannot move the character")
	_click(Vector2(268, 334)) # Shen's illustrated body, including the parent offset.
	_simulate(10.0)
	_check(interactions == ["shen"], "Clicking an NPC body walks to it and interacts")
	interactions.clear()
	for code: Key in [KEY_F, KEY_ENTER]:
		_key(code, true)
		_key(code, false)
	_check(interactions == ["shen", "shen"], "F and Enter interact with the nearby NPC")
	for id: String in ["shen", "lu", "tao", "zhou", "xiao", "lin"]:
		world.configure("wangxi", "herbalist")
		interactions.clear()
		_check(world.is_walkable(world.get_npc_position(id)), "NPC stands in a walkable position: " + id)
		world.navigate_to_npc(id)
		_simulate(10.0)
		_check(interactions == [id], "Auto-approach reaches and interacts exactly once: " + id)
		_check(world.is_walkable(world.get_player_position()), "Auto-approach preserves collision: " + id)
	# Walking paths traverse the complete town; walls do not swallow waypoints.
	for target: Vector2 in [Vector2(58, 292), Vector2(1022, 325), Vector2(390, 245), Vector2(680, 250)]:
		world.configure("wangxi")
		world._walk_to(target)
		_simulate(12.0)
		_check(world.get_player_position().distance_to(target) < 8.0, "Ground click reaches town target " + str(target))
	# Pausing cancels a journey and cannot deliver a delayed NPC interaction.
	world.configure("wangxi")
	interactions.clear()
	world.navigate_to_npc("shen")
	_simulate(0.4)
	world.set_input_enabled(false)
	var paused_position: Vector2 = world.get_player_position()
	_simulate(8.0)
	_check(world.get_player_position() == paused_position and interactions.is_empty(), "Modal pause prevents movement and interaction")
	world.set_input_enabled(true)
	_simulate(8.0)
	_check(world.get_player_position() == paused_position and interactions.is_empty(), "Closing modal does not resume a cancelled click")
	# Movement cannot tunnel through walls even if one input step is unusually large.
	world.configure("wangxi", "herbalist", Vector2(240, 240))
	world._move_with_collision(Vector2(0, -800))
	_check(world.get_player_position().y >= 198.0, "Large movement step stops at building wall")
	world.configure("wangxi", "herbalist", Vector2(500, 300))
	world._move_with_collision(Vector2(3000, 0))
	_check(world.get_player_position().x <= 1056.0, "Movement stops at playfield boundary")
	for place: String in ["grove", "ridge"]:
		world.configure(place)
		_check(world.is_walkable(world.get_player_position()), "Exploration spawn is walkable: " + place)
		var blocked_terrain: Vector2 = Vector2(150, 310) if place == "grove" else Vector2(210, 500)
		_check(not world.is_walkable(blocked_terrain), "Illustrated river or cliff blocks movement: " + place)
		var points: Array = [Vector2(340, 310), Vector2(710, 225), Vector2(655, 480)] if place == "grove" else [Vector2(350, 280), Vector2(770, 225), Vector2(540, 440)]
		world.set_objectives([
			{"id": "first", "label": "第一處線索", "position": [points[0].x, points[0].y]},
			{"id": "second", "label": "第二處線索", "position": points[1]},
			{"id": "third", "label": "第三處線索", "position": [points[2].x, points[2].y]},
		])
		for index in range(world.objectives.size()):
			var marker: Dictionary = world.objectives[index]
			var target: Vector2 = marker["position"]
			_check(target == points[index], "Published objective coordinates need no collision correction: " + place + "/" + str(index))
			world._walk_to(target)
			_simulate(12.0)
			_check(world.get_player_position().distance_to(target) < 8.0, "Exploration route reaches " + place + "/" + str(marker["id"]))
		var exit_point: Vector2 = Vector2(725, 562) if place == "grove" else Vector2(650, 550)
		world._walk_to(exit_point)
		_simulate(12.0)
		_check(world.get_player_position().distance_to(exit_point) < 8.0, "Exploration can return to exit: " + place)
	_animation_regressions()
	world.queue_free()
	print("TESTS COMPLETE: %s passed, %s failed" % [checks - failed, failed])
	quit(1 if failed else 0)
