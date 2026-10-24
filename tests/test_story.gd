extends SceneTree
## Compile the actual script, then walk every response with Dialogue Manager.

const STORY_PATH = "res://story/first_week.dialogue"
const Data = preload("res://scripts/game_data.gd")
const Run = preload("res://scripts/run_state.gd")
var passed = 0
var failed = 0
var resource: DialogueResource
var manager: Node


func _initialize() -> void:
	call_deferred("_run")


func expect(condition: bool, description: String) -> void:
	if condition:
		passed += 1
		print("PASS STORY: " + description)
	else:
		failed += 1
		push_error("FAIL STORY: " + description)


func _run() -> void:
	var text = FileAccess.get_file_as_string(STORY_PATH)
	var compiled = DMCompiler.compile_string(text, STORY_PATH)
	expect(compiled.errors.is_empty(), "first chapter compiles: " + str(compiled.errors))
	if not compiled.errors.is_empty():
		_finish()
		return
	resource = load(STORY_PATH) as DialogueResource
	expect(resource != null, "Godot imports the authored DialogueResource")
	if resource == null:
		_finish()
		return
	manager = Engine.get_singleton("DialogueManager")
	var required: Array[String] = ["intro_herbalist", "intro_courier", "intro_performer", "arrival_morning", "exam_intro", "ending_zhaoling", "ending_duyun", "ending_stay"]
	for id in Data.NPCS:
		required.append("npc_" + id)
	for id in Data.ACTIVITIES:
		required.append("activity_" + id)
	var missing: Array = []
	for title in required:
		if not resource.titles.has(title): missing.append(title)
	expect(missing.is_empty(), "all origins, six NPCs, activities, exam and endings exist: " + str(missing))
	var mutations: Array = []
	for id in compiled.lines:
		if compiled.lines[id].get("type", "") == DMConstants.TYPE_MUTATION:
			mutations.append(id)
	expect(mutations.is_empty(), "dialogue cannot award resources or advance the schedule")
	var id_pattern = RegEx.new()
	id_pattern.compile("\\[ID:([^\\]]+)\\]")
	var fixed_ids: Dictionary = {}
	var duplicates: Array = []
	for match_result in id_pattern.search_all(text):
		var id = match_result.get_string(1)
		if fixed_ids.has(id): duplicates.append(id)
		fixed_ids[id] = true
	expect(fixed_ids.size() >= 200 and duplicates.is_empty(), "authored lines have unique stable translation IDs")
	expect(not text.contains("掠影突進") and not text.contains("虛招減弱") and not text.contains("可同時照應面前多名對手"), "martial dialogue no longer teaches superseded v2 card effects")
	expect(text.contains("歸元功") and text.contains("守中訣") and text.contains("行雲訣") and text.contains("伏針") and text.contains("每場只能一次"), "the authored story introduces current inners, delayed technique and medicine limit")
	for origin in ["herbalist", "courier", "performer"]:
		for phase in [{"day": 1, "training": 0, "insight": 0}, {"day": 4, "training": 6, "insight": 6}, {"day": 7, "training": 6, "insight": 6}]:
			for answer in range(3):
				await _walk_graph(_context(origin, phase, answer))
	var first_lines: Dictionary = {}
	var morning_origins: Dictionary = {}
	for origin in ["herbalist", "courier", "performer"]:
		var context = _context(origin, {"day": 1, "training": 0, "insight": 0}, 0)
		var line: DialogueLine = await manager.get_next_dialogue_line(resource, "intro_" + origin, [context])
		if line != null: first_lines[line.text] = true
		morning_origins[await _linear_text("arrival_morning", context)] = true
	expect(first_lines.size() == 3, "legacy origin introductions retain their three recognizably different scenes")
	expect(morning_origins.size() == 3, "new next-morning introduction preserves each origin's familiar person")
	for npc in Data.NPCS:
		var remembered: Dictionary = {}
		for answer in range(3):
			var context = _context("herbalist", {"day": 1, "training": 0, "insight": 0}, answer)
			remembered[await _linear_text("npc_" + npc, context)] = true
		expect(remembered.size() == 3, "NPC " + npc + " audibly remembers all three motivation or road-choice branches")
	# These contexts exercise authored branches, not activity rewards or RNG.
	for variant in ["pushing_palm", "yielding_palm", "cloud_step", "hidden_needle"]:
		var context = _context("herbalist", {"day": 4, "training": 6, "insight": 6}, 0)
		context["activity_variant"] = variant
		await _walk_graph(context)
		var title = "complete_bridge_repair" if variant in ["pushing_palm", "yielding_palm"] else "activity_old_ballad"
		var expected: String = {"pushing_palm": "掌根", "yielding_palm": "卸力掌", "cloud_step": "掠影步", "hidden_needle": "伏針"}[variant]
		expect((await _linear_text(title, context)).contains(expected), "optional lesson " + variant + " has its own readable response")

	_finish()


func _context(origin: String, phase: Dictionary, answer: int) -> Dictionary:
	var state: RefCounted = Run.new()
	state.start_creation("試讀行者", origin)
	for index in range(6): state.set_creation_answer(index, answer)
	state.confirm_creation()
	state.data.spent = (int(phase.day) - 1) * 3
	state.data.training = phase.training
	state.data.insight = phase.insight
	return state.story_context()


func _linear_text(title: String, context: Dictionary) -> String:
	var result = ""
	var key = title
	for index in range(80):
		var line: DialogueLine = await manager.get_next_dialogue_line(resource, key, [context])
		if line == null: break
		result += line.text + "\n"
		if not line.responses.is_empty(): break
		key = line.next_id
	return result


func _walk_graph(context: Dictionary) -> void:
	var queue: Array = []
	for title in resource.titles:
		queue.append({"from": "", "key": title})
	var edges: Dictionary = {}
	var terminals: Dictionary = {}
	var visits = 0
	var empty_lines: Array = []
	while not queue.is_empty() and visits < 4000:
		visits += 1
		var entry: Dictionary = queue.pop_front()
		var line: DialogueLine = await manager.get_next_dialogue_line(resource, str(entry.key), [context])
		if line == null:
			if not str(entry.from).is_empty(): terminals[entry.from] = true
			continue
		if not str(entry.from).is_empty(): edges[entry.from].append(line.id)
		if edges.has(line.id): continue
		edges[line.id] = []
		if line.text.strip_edges().is_empty() and line.responses.is_empty(): empty_lines.append(line.id)
		if line.responses.is_empty():
			queue.append({"from": line.id, "key": line.next_id})
		else:
			for response: DialogueResponse in line.responses:
				if response.is_allowed: queue.append({"from": line.id, "key": response.next_id})
	var can_finish = terminals.duplicate()
	var changed = true
	while changed:
		changed = false
		for id in edges:
			if can_finish.has(id): continue
			for destination in edges[id]:
				if can_finish.has(destination):
					can_finish[id] = true
					changed = true
					break
	var name = "%s day %d / %s" % [context.origin, context.day, context.creation_motivation]
	expect(queue.is_empty() and empty_lines.is_empty(), name + ": every title and allowed response resolves to valid readable dialogue")
	expect(not edges.is_empty() and can_finish.size() == edges.size(), name + ": every inquiry loop has an exit back to gameplay")


func _finish() -> void:
	if resource:
		for value in resource.lines.values():
			if value is Dictionary: value.erase("resource")
	resource = null
	print("TESTS COMPLETE: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
