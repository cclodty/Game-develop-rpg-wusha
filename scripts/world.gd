class_name WeiyuanWorld
extends Node2D
## A small walkable place, independent of the run's calendar and rewards.

signal npc_requested(id: String)
signal hotspot_requested(id: String)
signal exit_requested(destination: String)

const FIELD_SIZE := Vector2(1080, 640)
const WALK_SPEED := 215.0
const FOOT_RADIUS := 14.0
const INTERACTION_RADIUS := 78.0
const GRID_SIZE := 24
const TOWN_NPCS := [
	{"id": "shen", "name": "沈照嶺", "role": "習劍 · 對練", "position": Vector2(240, 230)},
	{"id": "lu", "name": "陸行雲", "role": "身法 · 遠行", "position": Vector2(825, 235)},
	{"id": "tao", "name": "陶半夏", "role": "藥鋪 · 採藥", "position": Vector2(385, 465)},
	{"id": "zhou", "name": "周望山", "role": "驛站 · 委託", "position": Vector2(715, 465)},
	{"id": "xiao", "name": "蕭小滿", "role": "戲班 · 謀生", "position": Vector2(525, 445)},
	{"id": "lin", "name": "林知微", "role": "鎮史 · 舊路", "position": Vector2(535, 210)},
]
const PLACE_NAMES := {"wangxi": "望溪鎮", "grove": "青篁溪谷", "ridge": "望風古道"}

var location: String = "wangxi"
var origin: String = "herbalist"
var player_position := Vector2(540, 550)
var input_enabled: bool = true
var objectives: Array = []
var npc_positions: Dictionary = {}

var _obstacles: Array[Rect2] = []
var _walkable_border: PackedVector2Array = []
var _buildings: Array = []
var _landmarks: Array = []
var _exits: Array = []
var _specks: Array = []
var _particles: Array = []
var _navigation := AStarGrid2D.new()
var _path: PackedVector2Array = []
var _path_cursor: int = 0
var _pending_interaction: Dictionary = {}
var _elapsed: float = 0.0
var _walk_phase: float = 0.0
var _moving: bool = false
var _facing: float = 1.0
var _footstep: float = 0.0
var _nearby: Dictionary = {}
var _click_mark := Vector2(-100, -100)
var _click_age: float = 10.0
var _font: Font
var _serif: Font
var _art: Script
var _portraits: Dictionary = {}
var _backdrop: Texture2D


func _ready() -> void:
	_font = load("res://assets/fonts/JianghuSans.otf") as Font
	_serif = load("res://assets/fonts/JianghuSerif.otf") as Font
	if _font == null:
		_font = ThemeDB.fallback_font
	if _serif == null:
		_serif = _font
	_load_art()
	_build_location()
	queue_redraw()


func configure(place: String, hero_origin: String = "herbalist", initial_position: Vector2 = Vector2(-1, -1)) -> void:
	location = place if PLACE_NAMES.has(place) else "wangxi"
	origin = hero_origin
	var spawn: Vector2 = Vector2(730, 530) if location == "grove" else (Vector2(620, 475) if location == "ridge" else Vector2(540, 550))
	player_position = initial_position if initial_position.x >= 0.0 else spawn
	objectives.clear()
	_pending_interaction.clear()
	_path.clear()
	_particles.clear()
	_nearby.clear()
	_load_art()
	_build_location()
	player_position = _nearest_walkable(player_position)
	queue_redraw()


func set_objectives(items: Array) -> void:
	objectives.clear()
	var fallback_positions: Array[Vector2] = [Vector2(345, 290), Vector2(755, 325), Vector2(550, 135)]
	for index in range(items.size()):
		if not items[index] is Dictionary:
			continue
		var item: Dictionary = items[index].duplicate(true)
		if not item.has("id"):
			continue
		var raw_position: Variant = item.get("position", fallback_positions[index % fallback_positions.size()])
		var point: Vector2 = fallback_positions[index % fallback_positions.size()]
		if raw_position is Vector2:
			point = raw_position
		elif raw_position is Array and raw_position.size() >= 2:
			point = Vector2(float(raw_position[0]), float(raw_position[1]))
		point = _nearest_walkable(point)
		item["position"] = point
		item["label"] = str(item.get("label", "查訪線索"))
		item["kind"] = "hotspot"
		objectives.append(item)
	# A completed marker may be removed while an approach is in progress.
	if not _pending_interaction.is_empty() and _pending_interaction.get("kind", "") == "hotspot":
		var still_present: bool = false
		for item: Dictionary in objectives:
			still_present = still_present or item["id"] == _pending_interaction.get("id", "")
		if not still_present:
			_pending_interaction.clear()
	_nearby = _nearest_interaction()
	queue_redraw()


func set_input_enabled(value: bool) -> void:
	input_enabled = value
	if not value:
		_path.clear()
		_pending_interaction.clear()
		_moving = false
	queue_redraw()


func get_player_position() -> Vector2:
	return player_position


func get_npc_position(id: String) -> Vector2:
	return npc_positions.get(id, Vector2(-1, -1))


func navigate_to_npc(id: String) -> void:
	if not input_enabled or location != "wangxi" or not npc_positions.has(id):
		return
	for entry: Dictionary in _all_interactions():
		if entry["kind"] == "npc" and entry["id"] == id:
			_pending_interaction = entry.duplicate()
			if player_position.distance_to(entry["position"]) <= INTERACTION_RADIUS:
				_activate(entry)
			else:
				_walk_to(entry["position"])
			return


func is_walkable(point: Vector2) -> bool:
	if not Rect2(Vector2(FOOT_RADIUS + 10, FOOT_RADIUS + 10), FIELD_SIZE - Vector2.ONE * (FOOT_RADIUS + 10) * 2.0).has_point(point):
		return false
	if not _walkable_border.is_empty():
		for offset: Vector2 in [Vector2.ZERO, Vector2(FOOT_RADIUS, 0), Vector2(-FOOT_RADIUS, 0), Vector2(0, FOOT_RADIUS), Vector2(0, -FOOT_RADIUS)]:
			if not Geometry2D.is_point_in_polygon(point + offset, _walkable_border):
				return false
	for obstacle: Rect2 in _obstacles:
		if obstacle.grow(FOOT_RADIUS).has_point(point):
			return false
	return true


func _load_art() -> void:
	if not ResourceLoader.exists("res://scripts/art.gd"):
		return
	_art = load("res://scripts/art.gd") as Script
	if _art == null:
		return
	if _art.has_method("location"):
		_backdrop = _art.call("location", location) as Texture2D
	if _art.has_method("portrait"):
		for id: String in ["hero", "herbalist", "courier", "performer", "shen", "lu", "tao", "zhou", "xiao", "lin"]:
			_portraits[id] = _art.call("portrait", id)


func _build_location() -> void:
	_obstacles.clear()
	_walkable_border.clear()
	_buildings.clear()
	_landmarks.clear()
	_exits.clear()
	npc_positions.clear()
	_specks.clear()
	match location:
		"wangxi":
			# Footprints follow the finished illustration, including the stage steps.
			_add_building(Rect2(35, 0, 340, 205), "照嶺劍坪", Color("4e6b66"), "school")
			_add_building(Rect2(422, 0, 236, 182), "望溪書亭", Color("6c7865"), "library")
			_add_building(Rect2(700, 0, 350, 215), "行雲茶舍", Color("b27e58"), "tea")
			_add_building(Rect2(30, 330, 325, 275), "半夏藥鋪", Color("6d8267"), "shop")
			_add_building(Rect2(745, 340, 310, 285), "望溪驛", Color("9e6150"), "post")
			_add_building(Rect2(435, 340, 220, 80), "小滿戲臺", Color("9c5b49"), "stage")
			_obstacles.append(Rect2(0, 0, 70, 245))
			_obstacles.append(Rect2(0, 330, 35, 310))
			for npc: Dictionary in TOWN_NPCS:
				npc_positions[npc["id"]] = npc["position"]
			_exits = [
				{"id": "grove", "label": "青篁溪谷", "position": Vector2(58, 292), "kind": "exit"},
				{"id": "ridge", "label": "望風古道", "position": Vector2(1022, 325), "kind": "exit"},
			]
			_landmarks = [
				{"kind": "tree", "position": Vector2(50, 150), "scale": 1.1},
				{"kind": "tree", "position": Vector2(1028, 165), "scale": 1.0},
				{"kind": "tree", "position": Vector2(380, 555), "scale": 0.6},
				{"kind": "tree", "position": Vector2(690, 551), "scale": 0.65},
			]
		"grove":
			_walkable_border = PackedVector2Array([Vector2(670, 0), Vector2(750, 0), Vector2(728, 112), Vector2(840, 166), Vector2(984, 216), Vector2(1055, 305), Vector2(1020, 410), Vector2(935, 470), Vector2(835, 550), Vector2(748, 635), Vector2(684, 583), Vector2(630, 527), Vector2(520, 497), Vector2(425, 457), Vector2(360, 388), Vector2(299, 330), Vector2(318, 253), Vector2(370, 208), Vector2(466, 177), Vector2(545, 130), Vector2(570, 48), Vector2(620, 25)])
			_obstacles = [Rect2(765, 60, 220, 128)]
			_exits = [{"id": "wangxi", "label": "返回望溪鎮", "position": Vector2(725, 562), "kind": "exit"}]
			_landmarks = [
				{"kind": "bamboo", "position": Vector2(330, 165), "scale": 1.3},
				{"kind": "bamboo", "position": Vector2(425, 168), "scale": 1.0},
				{"kind": "rock", "position": Vector2(840, 177), "scale": 1.5},
				{"kind": "tree", "position": Vector2(905, 535), "scale": 1.6},
			]
		"ridge":
			_walkable_border = PackedVector2Array([Vector2(24, 100), Vector2(120, 100), Vector2(200, 155), Vector2(320, 199), Vector2(450, 224), Vector2(570, 188), Vector2(664, 154), Vector2(785, 160), Vector2(880, 210), Vector2(1055, 250), Vector2(1055, 300), Vector2(990, 350), Vector2(900, 399), Vector2(805, 449), Vector2(740, 510), Vector2(705, 545), Vector2(696, 579), Vector2(647, 584), Vector2(610, 530), Vector2(590, 495), Vector2(542, 469), Vector2(430, 429), Vector2(362, 392), Vector2(298, 336), Vector2(245, 290), Vector2(180, 260), Vector2(125, 215), Vector2(70, 200), Vector2(24, 180)])
			_exits = [{"id": "wangxi", "label": "返回望溪鎮", "position": Vector2(650, 550), "kind": "exit"}]
			_landmarks = [
				{"kind": "rock", "position": Vector2(135, 155), "scale": 2.2},
				{"kind": "rock", "position": Vector2(930, 160), "scale": 2.1},
				{"kind": "rock", "position": Vector2(325, 525), "scale": 1.8},
				{"kind": "tree", "position": Vector2(645, 125), "scale": 1.0},
				{"kind": "rock", "position": Vector2(900, 570), "scale": 2.0},
			]
	var random := RandomNumberGenerator.new()
	random.seed = 9741 + location.hash()
	for index in range(115):
		_specks.append({"position": Vector2(random.randf_range(20, 1060), random.randf_range(30, 620)), "radius": random.randf_range(0.8, 2.8), "phase": random.randf_range(0, TAU)})
	_build_navigation()
	player_position = _nearest_walkable(player_position)


func _add_building(footprint: Rect2, label: String, roof: Color, kind: String) -> void:
	_obstacles.append(footprint)
	_buildings.append({"rect": footprint, "label": label, "roof": roof, "kind": kind})


func _build_navigation() -> void:
	_navigation.region = Rect2i(0, 0, 45, 27)
	_navigation.cell_size = Vector2(GRID_SIZE, GRID_SIZE)
	_navigation.offset = Vector2(GRID_SIZE, GRID_SIZE) * 0.5
	_navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_navigation.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_navigation.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_navigation.update()
	for x in range(45):
		for y in range(27):
			var point := Vector2(x * GRID_SIZE + GRID_SIZE * 0.5, y * GRID_SIZE + GRID_SIZE * 0.5)
			_navigation.set_point_solid(Vector2i(x, y), not is_walkable(point))


func _nearest_walkable(point: Vector2) -> Vector2:
	var clamped := Vector2(clampf(point.x, 28, 1052), clampf(point.y, 28, 612))
	if is_walkable(clamped):
		return clamped
	var best := Vector2(540, 550)
	var distance: float = INF
	for x in range(45):
		for y in range(27):
			var candidate := Vector2(x * GRID_SIZE + GRID_SIZE * 0.5, y * GRID_SIZE + GRID_SIZE * 0.5)
			if is_walkable(candidate) and candidate.distance_squared_to(clamped) < distance:
				best = candidate
				distance = candidate.distance_squared_to(clamped)
	return best


func _grid_point(point: Vector2) -> Vector2i:
	var cell := Vector2i(clampi(floori(point.x / GRID_SIZE), 0, 44), clampi(floori(point.y / GRID_SIZE), 0, 26))
	if not _navigation.is_point_solid(cell):
		return cell
	var best := Vector2i(22, 23)
	var distance: float = INF
	for x in range(45):
		for y in range(27):
			var candidate := Vector2i(x, y)
			if not _navigation.is_point_solid(candidate) and Vector2(candidate).distance_squared_to(Vector2(cell)) < distance:
				best = candidate
				distance = Vector2(candidate).distance_squared_to(Vector2(cell))
	return best


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_F, KEY_ENTER, KEY_KP_ENTER]:
			var target := _nearest_interaction()
			if not target.is_empty():
				_activate(target)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Use the event's coordinates, including this node's canvas transform.
		# This remains correct when the playfield is wrapped in a clipping Control.
		var local_event := make_input_local(event) as InputEventMouseButton
		var point: Vector2 = local_event.position
		if not Rect2(Vector2.ZERO, FIELD_SIZE).has_point(point):
			return
		var target: Dictionary = {}
		var best_distance: float = 58.0
		for entry: Dictionary in _all_interactions():
			var position: Vector2 = entry["position"]
			var hit_point := position - Vector2(0, 32 if entry["kind"] == "npc" else 0)
			var distance := point.distance_to(hit_point)
			if distance < best_distance:
				target = entry
				best_distance = distance
		if not target.is_empty():
			_pending_interaction = target.duplicate()
			if player_position.distance_to(target["position"]) <= INTERACTION_RADIUS:
				_activate(target)
			else:
				_walk_to(target["position"])
		else:
			_pending_interaction.clear()
			_walk_to(point)
		get_viewport().set_input_as_handled()


func _walk_to(point: Vector2) -> void:
	var destination := _nearest_walkable(point)
	var from_cell := _grid_point(player_position)
	var to_cell := _grid_point(destination)
	_path = _navigation.get_point_path(from_cell, to_cell)
	_path_cursor = 0
	# The first grid center can lie behind the character, so start ahead when safe.
	if _path.size() > 1 and player_position.distance_to(_path[0]) < GRID_SIZE:
		_path_cursor = 1
	if not _path.is_empty():
		_path.append(destination)
	_click_mark = destination
	_click_age = 0.0


func _physics_process(delta: float) -> void:
	_elapsed += delta
	_click_age += delta
	_moving = false
	if input_enabled and visible:
		var direction := Vector2(
			float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
			float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
		if not direction.is_zero_approx():
			_path.clear()
			_pending_interaction.clear()
			direction = direction.normalized()
		elif _path_cursor < _path.size():
			var offset := _path[_path_cursor] - player_position
			if offset.length() < maxf(5.0, WALK_SPEED * delta):
				_path_cursor += 1
				if _path_cursor < _path.size():
					offset = _path[_path_cursor] - player_position
				else:
					offset = Vector2.ZERO
			direction = offset.normalized()
		if not direction.is_zero_approx():
			var before := player_position
			_move_with_collision(direction * WALK_SPEED * delta)
			_moving = player_position.distance_squared_to(before) > 0.05
			if absf(direction.x) > 0.1:
				_facing = signf(direction.x)
			if _moving:
				_walk_phase += delta * 12.0
				_footstep += delta
				if _footstep > 0.15:
					_footstep = 0.0
					_particles.append({"position": player_position + Vector2(0, 4), "age": 0.0})
		if not _pending_interaction.is_empty() and player_position.distance_to(_pending_interaction["position"]) < INTERACTION_RADIUS - 5.0:
			var selected := _pending_interaction.duplicate()
			_activate(selected)
	_nearby = _nearest_interaction()
	for index in range(_particles.size() - 1, -1, -1):
		_particles[index]["age"] += delta
		if _particles[index]["age"] > 0.5:
			_particles.remove_at(index)
	queue_redraw()


func _move_with_collision(offset: Vector2) -> void:
	# Substeps prevent tunnelling through narrow walls at low frame rates.
	var steps := maxi(1, ceili(offset.length() / 8.0))
	var step := offset / float(steps)
	for _index in range(steps):
		var horizontal := player_position + Vector2(step.x, 0)
		if is_walkable(horizontal):
			player_position = horizontal
		var vertical := player_position + Vector2(0, step.y)
		if is_walkable(vertical):
			player_position = vertical


func _all_interactions() -> Array:
	var all: Array = objectives.duplicate()
	if location == "wangxi":
		for npc: Dictionary in TOWN_NPCS:
			all.append({"id": npc["id"], "label": npc["name"], "position": npc["position"], "kind": "npc"})
	all.append_array(_exits)
	return all


func _nearest_interaction() -> Dictionary:
	var result: Dictionary = {}
	var nearest: float = INTERACTION_RADIUS
	for entry: Dictionary in _all_interactions():
		var distance := player_position.distance_to(entry["position"])
		if distance < nearest:
			result = entry
			nearest = distance
	return result


func _activate(target: Dictionary) -> void:
	if not input_enabled:
		return
	_pending_interaction.clear()
	_path.clear()
	_moving = false
	match str(target.get("kind", "")):
		"npc": npc_requested.emit(str(target["id"]))
		"hotspot": hotspot_requested.emit(str(target["id"]))
		"exit": exit_requested.emit(str(target["id"]))


func _draw() -> void:
	_draw_ground()
	if _backdrop == null:
		for building: Dictionary in _buildings:
			_draw_building(building)
		for landmark: Dictionary in _landmarks:
			_draw_landmark(landmark)
	for exit_point: Dictionary in _exits:
		_draw_exit(exit_point)
	for objective: Dictionary in objectives:
		_draw_objective(objective)
	for puff: Dictionary in _particles:
		var age: float = puff["age"]
		draw_circle(puff["position"] + Vector2(sin(age * 7.0) * 4, -age * 8), 3 + age * 5, Color(0.94, 0.87, 0.66, (0.5 - age) * 0.5))
	if _click_age < 0.8 and _pending_interaction.is_empty():
		draw_arc(_click_mark, 9 + _click_age * 8, 0, TAU, 24, Color(0.17, 0.45, 0.39, 1.0 - _click_age / 0.8), 2, true)
	var actors: Array = []
	if location == "wangxi":
		for npc: Dictionary in TOWN_NPCS:
			actors.append({"id": npc["id"], "position": npc["position"], "name": npc["name"], "role": npc["role"], "hero": false})
	actors.append({"id": origin, "position": player_position, "name": "", "hero": true})
	actors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["position"].y < b["position"].y)
	for actor: Dictionary in actors:
		_draw_actor(actor)
	_draw_ambient()
	_draw_wayfinding()


func _draw_ground() -> void:
	var base := Color("d7dfba") if location != "ridge" else Color("d7d6bc")
	draw_rect(Rect2(Vector2.ZERO, FIELD_SIZE), base)
	if _backdrop != null:
		draw_texture_rect(_backdrop, Rect2(Vector2.ZERO, FIELD_SIZE), false)
		draw_rect(Rect2(Vector2.ZERO, FIELD_SIZE), Color("8d9b79"), false, 2)
		return
	for point: Dictionary in _specks:
		var position: Vector2 = point["position"]
		draw_circle(position, point["radius"], Color(0.36, 0.48, 0.28, 0.13))
	if location == "wangxi":
		_path_stroke(PackedVector2Array([Vector2(20, 326), Vector2(1040, 326)]), 90)
		_path_stroke(PackedVector2Array([Vector2(540, 205), Vector2(540, 332), Vector2(685, 350), Vector2(698, 556), Vector2(540, 570)]), 65)
		_path_stroke(PackedVector2Array([Vector2(540, 570), Vector2(360, 550), Vector2(370, 335), Vector2(240, 240)]), 62)
		_path_stroke(PackedVector2Array([Vector2(370, 425), Vector2(240, 442)]), 62)
		_path_stroke(PackedVector2Array([Vector2(690, 425), Vector2(820, 442)]), 62)
		_path_stroke(PackedVector2Array([Vector2(825, 235), Vector2(780, 325)]), 68)
		_path_stroke(PackedVector2Array([Vector2(525, 450), Vector2(540, 570)]), 70)
		draw_circle(Vector2(535, 325), 97, Color("e7ddbc"))
		draw_arc(Vector2(535, 325), 72, 0, TAU, 64, Color(0.47, 0.5, 0.37, 0.2), 3, true)
		for i in range(18):
			var angle := float(i) / 18.0 * TAU
			draw_line(Vector2(535, 325) + Vector2.from_angle(angle) * 75, Vector2(535, 325) + Vector2.from_angle(angle) * 86, Color(0.54, 0.53, 0.4, 0.2), 2, true)
	elif location == "grove":
		draw_rect(Rect2(0, 0, 195, 640), Color("94bcb6"))
		for x in range(8):
			for y in range(11):
				var wave := Vector2(x * 28 + sin(_elapsed * 0.7 + y) * 8, y * 60 + 10)
				draw_line(wave, wave + Vector2(12, -3), Color(0.9, 0.99, 0.91, 0.3), 2, true)
		_path_stroke(PackedVector2Array([Vector2(540, 610), Vector2(595, 450), Vector2(565, 305), Vector2(675, 195), Vector2(665, 45)]), 95)
		_path_stroke(PackedVector2Array([Vector2(560, 305), Vector2(240, 325), Vector2(25, 325)]), 66)
		_path_stroke(PackedVector2Array([Vector2(590, 450), Vector2(360, 455)]), 58)
		draw_rect(Rect2(0, 282, 236, 78), Color("9a7854"))
		for plank in range(16):
			draw_line(Vector2(plank * 16, 286), Vector2(plank * 16, 357), Color("c5a77b"), 2)
		draw_line(Vector2(0, 281), Vector2(237, 281), Color("765b42"), 6)
		draw_line(Vector2(0, 361), Vector2(237, 361), Color("765b42"), 6)
	else:
		_path_stroke(PackedVector2Array([Vector2(535, 610), Vector2(580, 465), Vector2(480, 330), Vector2(695, 260), Vector2(775, 145), Vector2(775, 30)]), 120)
		_path_stroke(PackedVector2Array([Vector2(480, 330), Vector2(285, 275), Vector2(130, 290)]), 70)
		for stone in range(11):
			var point := Vector2(500 + sin(stone * 0.8) * 70, 585 - stone * 31)
			draw_rect(Rect2(point, Vector2(36, 11)), Color(0.58, 0.57, 0.47, 0.23))
	# The frame doubles as the world boundary; actors never move behind the HUD.
	draw_rect(Rect2(Vector2.ZERO, FIELD_SIZE), Color("aeb798"), false, 3)


func _path_stroke(points: PackedVector2Array, width: float) -> void:
	draw_polyline(points, Color(0.54, 0.52, 0.38, 0.2), width + 7, true)
	draw_polyline(points, Color(0.91, 0.86, 0.69, 0.92), width, true)
	for point: Vector2 in points:
		draw_circle(point, width * 0.5, Color(0.91, 0.86, 0.69, 0.92))


func _draw_building(building: Dictionary) -> void:
	var rect: Rect2 = building["rect"]
	var roof: Color = building["roof"]
	var stage: bool = building["kind"] == "stage"
	draw_rect(Rect2(rect.position + Vector2(8, 10), rect.size + Vector2(0, 6)), Color(0.22, 0.25, 0.18, 0.19))
	if stage:
		draw_rect(rect, Color("a47c51"))
		for i in range(11):
			draw_line(rect.position + Vector2(i * rect.size.x / 10, 1), rect.position + Vector2(i * rect.size.x / 10, rect.size.y - 2), Color("c0a277"), 2)
		draw_line(rect.position + Vector2(0, 8), rect.end - Vector2(0, rect.size.y - 8), roof, 9)
		_draw_banner(rect.get_center() + Vector2(0, 0), building["label"], 17)
		return
	var wall := Rect2(rect.position + Vector2(12, 12), rect.size - Vector2(24, 6))
	draw_rect(wall, Color("f2e6c5"))
	draw_rect(wall, Color("786a4c"), false, 2)
	for i in range(3):
		var window := Rect2(wall.position + Vector2(28 + i * (wall.size.x - 50) / 3, wall.size.y - 37), Vector2(22, 27))
		draw_rect(window, Color("8c7960"))
		draw_line(window.get_center() - Vector2(0, 13), window.get_center() + Vector2(0, 13), Color("d4be8e"), 2)
		draw_line(window.get_center() - Vector2(10, 0), window.get_center() + Vector2(10, 0), Color("d4be8e"), 2)
	var roof_points := PackedVector2Array([
		rect.position + Vector2(-10, 20), rect.position + Vector2(30, -19),
		rect.position + Vector2(rect.size.x - 30, -19), rect.position + Vector2(rect.size.x + 10, 20),
		rect.position + Vector2(rect.size.x - 3, 51), rect.position + Vector2(3, 51)])
	draw_colored_polygon(roof_points, roof)
	draw_polyline(PackedVector2Array([roof_points[0], roof_points[1], roof_points[2], roof_points[3]]), roof.lightened(0.23), 4, true)
	draw_line(rect.position + Vector2(-4, 48), rect.position + Vector2(rect.size.x + 4, 48), roof.darkened(0.3), 6, true)
	for i in range(9):
		var roof_x := rect.position.x + 10 + i * (rect.size.x - 20) / 8
		draw_line(Vector2(roof_x, rect.position.y + 16), Vector2(roof_x, rect.position.y + 44), roof.lightened(0.12), 2, true)
	_draw_banner(Vector2(rect.get_center().x, rect.position.y + 67), building["label"], 18)
	for x: float in [rect.position.x + 15, rect.end.x - 15]:
		draw_line(Vector2(x, rect.position.y + 53), Vector2(x, rect.position.y + 65), Color("6e6347"), 2)
		draw_circle(Vector2(x, rect.position.y + 74), 7, Color("b96349"))
		draw_line(Vector2(x, rect.position.y + 81), Vector2(x, rect.position.y + 87), Color("cda96d"), 2)


func _draw_banner(center: Vector2, text: String, font_size: int) -> void:
	if _font == null:
		return
	var size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var rectangle := Rect2(center - Vector2(size.x * 0.5 + 9, 16), Vector2(size.x + 18, 26))
	_round_panel(rectangle, Color("66573f"), 4)
	draw_string(_font, center + Vector2(-size.x * 0.5, 3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("fff0c8"))


func _draw_landmark(item: Dictionary) -> void:
	var position: Vector2 = item["position"]
	var scale_value: float = item["scale"]
	draw_set_transform(position, 0, Vector2.ONE * scale_value)
	match item["kind"]:
		"tree":
			draw_set_transform(position, 0, Vector2(scale_value, scale_value * 0.4))
			draw_circle(Vector2(4, 0), 43, Color(0.23, 0.34, 0.22, 0.2))
			draw_set_transform(position, 0, Vector2.ONE * scale_value)
			draw_line(Vector2.ZERO, Vector2(0, -68), Color("776749"), 11, true)
			draw_line(Vector2(0, -40), Vector2(28, -76), Color("776749"), 5, true)
			draw_circle(Vector2(-24, -67), 35, Color("7f9d73"))
			draw_circle(Vector2(22, -76), 35, Color("6f956f"))
			draw_circle(Vector2(-1, -93), 34, Color("9bb783"))
			draw_circle(Vector2(-15, -102), 18, Color(0.77, 0.83, 0.56, 0.3))
		"bamboo":
			for i in range(5):
				var stalk_x := float(i * 15 - 30)
				var height := 75 + sin(float(i)) * 20
				draw_line(Vector2(stalk_x, 0), Vector2(stalk_x + 8, -height), Color("648965"), 5, true)
				for joint in range(4):
					var point := Vector2(stalk_x + joint * 1.5, -joint * 20)
					draw_line(point - Vector2(3, 0), point + Vector2(5, 0), Color("bad09a"), 2)
					if joint > 0:
						draw_line(point, point + Vector2(22 if joint % 2 == 0 else -22, -14), Color("648965"), 4, true)
		"rock":
			var polygon := PackedVector2Array([Vector2(-42, 0), Vector2(-51, -22), Vector2(-28, -56), Vector2(13, -67), Vector2(40, -39), Vector2(47, -8), Vector2(19, 9)])
			draw_colored_polygon(polygon, Color("9c9e8e"))
			draw_colored_polygon(PackedVector2Array([polygon[1], polygon[2], polygon[3], Vector2(1, -24)]), Color("bbbca3"))
			draw_line(Vector2(1, -24), Vector2(19, 9), Color("838a7b"), 3, true)
	draw_set_transform(Vector2.ZERO)


func _draw_actor(actor: Dictionary) -> void:
	var position: Vector2 = actor["position"]
	var hero: bool = actor["hero"]
	var id: String = actor["id"]
	var texture: Texture2D = _portraits.get(id) as Texture2D
	if hero and texture == null:
		texture = _portraits.get("hero") as Texture2D
	var pulse: float = sin(_elapsed * 2.0 + position.x * 0.02)
	draw_set_transform(position, 0, Vector2(1, 0.32))
	draw_circle(Vector2(0, 1), 23 if hero else 22, Color(0.17, 0.28, 0.2, 0.22))
	draw_set_transform(Vector2.ZERO)
	if hero:
		draw_arc(position + Vector2(0, 3), 25, 0, TAU, 32, Color(0.87, 0.71, 0.37, 0.85), 2, true)
	var bounce: float = absf(sin(_walk_phase)) * 4 if hero and _moving else pulse * 0.7
	var tilt: float = sin(_walk_phase) * 0.045 if hero and _moving else 0.0
	var height: float = 85.0 if hero else 81.0
	var facing: float = _facing if hero else 1.0
	draw_set_transform(position - Vector2(0, bounce), tilt, Vector2(facing, 1))
	if texture != null:
		var size := texture.get_size()
		var width: float = height * size.x / maxf(size.y, 1.0)
		draw_texture_rect(texture, Rect2(-width * 0.5, -height, width, height), false)
	else:
		_draw_fallback_character(hero, id)
	draw_set_transform(Vector2.ZERO)
	if not hero and _font != null:
		var active: bool = _nearby.get("id", "") == id
		var name: String = actor["name"]
		var name_size := _font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 17)
		_round_panel(Rect2(position + Vector2(-name_size.x * 0.5 - 8, 8), Vector2(name_size.x + 16, 25)), Color(0.98, 0.96, 0.85, 0.94), 6)
		draw_string(_font, position + Vector2(-name_size.x * 0.5, 27), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("354c42"))
		if active:
			var role: String = actor["role"]
			var role_size := _font.get_string_size(role, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
			draw_string(_font, position + Vector2(-role_size.x * 0.5, 46), role, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("455b4b"))
			draw_circle(position - Vector2(0, 99), 10 + pulse * 0.8, Color("fff0bd"))
			draw_string(_font, position - Vector2(4.5, 94), "F", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("4b6756"))


func _draw_fallback_character(hero: bool, id: String) -> void:
	var coat := Color("437a69") if hero else Color("687a77")
	var colors := {"shen": Color("566a76"), "lu": Color("779c87"), "tao": Color("b29a67"), "zhou": Color("ad765a"), "xiao": Color("aa716c"), "lin": Color("728a9d")}
	coat = colors.get(id, coat)
	draw_line(Vector2(-7, -8), Vector2(-9, 0), Color("4e5345"), 8, true)
	draw_line(Vector2(8, -8), Vector2(10, 0), Color("4e5345"), 8, true)
	draw_colored_polygon(PackedVector2Array([Vector2(-15, -40), Vector2(14, -40), Vector2(20, -9), Vector2(-19, -9)]), coat)
	draw_line(Vector2(-11, -35), Vector2(-21, -17), coat, 10, true)
	draw_line(Vector2(12, -35), Vector2(20, -20), coat, 10, true)
	draw_circle(Vector2(0, -57), 23, Color("4f4c40"))
	draw_circle(Vector2(0, -53), 19, Color("f5d6ac"))
	draw_arc(Vector2(0, -59), 20, PI, TAU, 16, Color("4f4c40"), 11, true)
	draw_circle(Vector2(-6, -53), 2.1, Color("36443c"))
	draw_circle(Vector2(7, -53), 2.1, Color("36443c"))
	draw_line(Vector2(-12, -23), Vector2(13, -23), Color("d9c69a"), 4, true)
	if hero:
		draw_line(Vector2(17, -32), Vector2(27, -60), Color("d3ddd0"), 4, true)
		draw_line(Vector2(15, -30), Vector2(24, -26), Color("8d7552"), 4, true)


func _draw_objective(objective: Dictionary) -> void:
	var point: Vector2 = objective["position"]
	var pulse := 0.5 + 0.5 * sin(_elapsed * 3.0)
	draw_circle(point, 23 + pulse * 3, Color(0.92, 0.71, 0.31, 0.12))
	draw_arc(point, 19, 0, TAU, 32, Color(0.8, 0.55, 0.22, 0.8), 2, true)
	var diamond := PackedVector2Array([point + Vector2(0, -32), point + Vector2(8, -21), point + Vector2(0, -10), point + Vector2(-8, -21)])
	draw_colored_polygon(diamond, Color("d3a348"))
	if _font != null:
		var label: String = objective["label"]
		var size := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		var width := minf(size.x + 18, 230)
		_round_panel(Rect2(point + Vector2(-width * 0.5, 25), Vector2(width, 26)), Color(1, 0.96, 0.79, 0.97), 7)
		draw_string(_font, point + Vector2(-minf(size.x, 212) * 0.5, 44), label, HORIZONTAL_ALIGNMENT_LEFT, 212, 16, Color("73572b"))


func _draw_exit(entry: Dictionary) -> void:
	var point: Vector2 = entry["position"]
	var direction := Vector2.LEFT if point.x < 100 else Vector2.RIGHT
	if point.y >= 540:
		direction = Vector2.DOWN
	draw_circle(point, 25, Color(0.99, 0.96, 0.82, 0.85))
	draw_arc(point, 25, 0, TAU, 32, Color("849979"), 2, true)
	var across := direction.orthogonal()
	draw_line(point - direction * 11, point + direction * 11, Color("536e59"), 3, true)
	draw_polyline(PackedVector2Array([point + direction * 3 + across * 7, point + direction * 11, point + direction * 3 - across * 7]), Color("536e59"), 3, true)
	if _font != null and player_position.distance_to(point) > 90.0:
		var label: String = entry["label"]
		var size := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		var x := clampf(point.x - size.x * 0.5, 6, FIELD_SIZE.x - size.x - 6)
		var y: float = point.y - 35 if point.y > 540 else point.y + 45
		_round_panel(Rect2(x - 5, y - 17, size.x + 10, 23), Color(0.98, 0.96, 0.85, 0.96), 5)
		draw_string(_font, Vector2(x, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("3f634e"))


func _draw_ambient() -> void:
	for i in range(9):
		var x := fposmod(float(i * 137) + _elapsed * (7.0 + i % 3), 1120.0) - 20.0
		var y := fposmod(float(i * 93) + sin(_elapsed * 0.4 + i) * 18, 600.0) + 20.0
		draw_line(Vector2(x, y), Vector2(x + 5, y - 2), Color(0.98, 0.94, 0.66, 0.55), 3, true)
	if location == "ridge":
		for i in range(3):
			var point := Vector2(280 + i * 220, 72 + sin(_elapsed * 0.3 + i) * 12)
			draw_arc(point, 13, 3.5, 5.8, 12, Color(0.36, 0.41, 0.36, 0.42), 2, true)
			draw_arc(point + Vector2(24, 0), 13, 3.6, 5.9, 12, Color(0.36, 0.41, 0.36, 0.42), 2, true)


func _draw_wayfinding() -> void:
	if _font == null:
		return
	var title: String = PLACE_NAMES.get(location, "望溪鎮")
	_round_panel(Rect2(14, 14, 172, 37), Color(0.98, 0.97, 0.88, 0.95), 9)
	draw_string(_serif, Vector2(28, 40), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color("355e4f"))
	if not input_enabled:
		return
	if not _nearby.is_empty():
		var verb: String = "交談" if _nearby["kind"] == "npc" else ("查看路線" if _nearby["kind"] == "exit" else "查看")
		var text := "F  " + verb + " · " + str(_nearby["label"])
		var size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
		var panel := Rect2(Vector2(540 - size.x * 0.5 - 17, 599), Vector2(size.x + 34, 32))
		_round_panel(panel, Color(0.16, 0.31, 0.25, 0.93), 9)
		draw_string(_font, Vector2(540 - size.x * 0.5, 622), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("fff1ce"))


func _round_panel(rect: Rect2, color: Color, radius: float) -> void:
	var actual := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	draw_rect(Rect2(rect.position + Vector2(actual, 0), rect.size - Vector2(actual * 2, 0)), color)
	draw_rect(Rect2(rect.position + Vector2(0, actual), rect.size - Vector2(0, actual * 2)), color)
	for point: Vector2 in [rect.position + Vector2(actual, actual), rect.position + Vector2(rect.size.x - actual, actual), rect.position + Vector2(actual, rect.size.y - actual), rect.end - Vector2.ONE * actual]:
		draw_circle(point, actual, color)
