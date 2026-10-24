extends SceneTree
## Rule and persistence regression tests. No main scene, UI or combat timing required.

const Run = preload("res://scripts/run_state.gd")
const Data = preload("res://scripts/game_data.gd")
const Battle = preload("res://scripts/card_battle.gd")
const SAVE = "user://test-rules-v3.json"
var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_clean_save()
	_test_catalog_and_origins()
	_test_calendar_and_payment()
	_test_rewards_and_dependencies()
	_test_complete_routes()
	_test_pending_and_retry()
	_test_persistence()
	_test_invalid_saves()
	_clean_save()
	print("TESTS COMPLETE: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		printerr("FAIL: " + message)

func _fresh(origin: String = "herbalist") -> RefCounted:
	var state: RefCounted = Run.new()
	state.new_run("小行", origin)
	return state

func _do(state: RefCounted, id: String) -> void:
	var start: Dictionary = state.begin_activity(id)
	_check(bool(start.ok), "can begin " + id)
	if bool(start.ok):
		_check(bool(state.complete_activity().ok), "can complete " + id)

func _fill_week(state: RefCounted) -> void:
	while state.remaining() > 0:
		_do(state, "rest")

func _training_route(origin: String) -> RefCounted:
	var state: RefCounted = _fresh(origin)
	_do(state, "sword_lesson")
	for index in range(4):
		_do(state, "practice")
	_do(state, "missing_letter")
	return state

func _social_route(origin: String) -> RefCounted:
	var state: RefCounted = _fresh(origin)
	for id in ["grove_survey", "ridge_tracks", "hermit_visit"]:
		_do(state, id)
	return state

func _test_catalog_and_origins() -> void:
	_check(Data.ORIGINS.size() == 3, "three origins")
	_check(Data.NPCS.size() == 6, "six major NPCs")
	_check(Data.ACTIVITIES.size() == 16, "bounded meaningful activity catalog")
	var one_time_cost: int = 0
	for id in Data.ACTIVITIES:
		var activity: Dictionary = Data.ACTIVITIES[id]
		_check(activity.cost >= 1 and activity.cost <= 3, "visible bounded cost: " + id)
		_check(not activity.description.is_empty() and not activity.reward_text.is_empty(), "activity explains choice: " + id)
		_check(activity.npc in Data.NPCS and id in Data.activities_for(activity.npc), "activity belongs to a real NPC: " + id)
		if not activity.repeatable:
			one_time_cost += int(activity.cost)
	_check(one_time_cost > 21, "one run cannot collect every one-time outcome")
	var herbalist: RefCounted = _fresh("herbalist")
	var courier: RefCounted = _fresh("courier")
	var performer: RefCounted = _fresh("performer")
	_check(herbalist.data.medicine == 4 and courier.data.medicine == 2, "herbalist brings extra medicine")
	_check(courier.data.money == 40 and herbalist.data.money == 24, "courier brings extra money")
	_check(performer.data.insight == 1 and herbalist.data.insight == 0, "performer brings observation experience")
	_do(herbalist, "herb_errand")
	_do(courier, "herb_errand")
	_check(herbalist.data.medicine == 8 and courier.data.medicine == 5, "origin changes herb reward")
	_do(herbalist, "medicine_lesson")
	_check(herbalist.data.medicine == 12, "herbalist gets bonus recipe supplies")
	_do(courier, "courier_work")
	_do(performer, "stage_work")
	_check(courier.data.money == 74, "courier work grants 26 coins after herb reward")
	_check(performer.data.money == 48, "performer work grants 24 coins")
	for origin in Data.ORIGINS:
		var state: RefCounted = _fresh(origin)
		_check(state.story_context().origin == origin, "origin available to distinct story responses")
		_check(state.day() == 1 and state.period() == "早" and state.remaining() == 21, "origin starts on morning one")
	var unnamed: RefCounted = Run.new()
	unnamed.new_run(" \n\t", "invalid")
	_check(unnamed.data.hero_name == "行路人" and unnamed.data.origin == "herbalist", "safe empty-name and invalid-origin fallback")

func _test_calendar_and_payment() -> void:
	var state: RefCounted = _fresh()
	_check(not state.begin_exam().ok, "exam unavailable before day eight")
	_check(not state.activity_status("unknown").ok, "unknown activity rejected")
	_do(state, "rest")
	_check(state.day() == 1 and state.period() == "午", "one slot advances to afternoon")
	_do(state, "ridge_tracks")
	_check(state.day() == 2 and state.period() == "午" and state.remaining() == 17, "three-slot expedition can cross day boundary")
	var before_money: int = state.data.money
	_check(state.begin_activity("sword_lesson").ok, "paid activity can start")
	_check(state.data.money == before_money - 12 and state.data.spent == 6, "fee and time charged on begin")
	_check(not state.begin_activity("rest").ok and not state.buy_medicine().ok, "pending activity excludes overlapping schedule and shopping")
	_check(state.retry_activity().ok and state.data.money == before_money - 12 and state.data.spent == 6, "retry cannot charge fee or time twice")
	_check(state.retreat_activity().ok, "can retreat from paid lesson")
	_check(state.data.money == before_money - 12 and state.data.spent == 6 and not state.has_skill("sword_qi"), "retreat keeps spent resources and awards nothing")
	_check(state.begin_activity("sword_lesson").ok, "abandoned one-time event can be rescheduled")
	_check(state.complete_activity().ok and state.data.money == 0, "rescheduled event is a new paid commitment")
	_check(not state.activity_status("bridge_repair").ok, "insufficient funds reject fee-bearing activity")
	_check(not state.buy_medicine().ok, "insufficient funds reject medicine")
	_do(state, "courier_work")
	var before_slots: int = state.data.spent
	var before_medicine: int = state.data.medicine
	_check(state.buy_medicine().ok and state.data.money == 6, "earned money buys medicine")
	_check(state.data.spent == before_slots and state.data.medicine == before_medicine + 1, "shopping consumes money but no time")
	while state.remaining() > 1:
		_do(state, "rest")
	_check(not state.begin_activity("old_ballad").ok and state.remaining() == 1, "insufficient remaining slots rejected without mutation")
	_do(state, "rest")
	_check(state.day() == 8 and state.period() == "選拔日" and state.ready_for_exam(), "21 slots enter day eight")
	_check(not state.begin_activity("rest").ok, "day eight blocks further preparation")
	var shortcut: RefCounted = _fresh()
	var skipped: Dictionary = shortcut.prepare_exam_now()
	_check(skipped.ok and skipped.forfeited_slots == 21 and shortcut.ready_for_exam(), "explicitly waiting forfeits remaining time")

func _test_rewards_and_dependencies() -> void:
	var state: RefCounted = _fresh()
	_check(not state.begin_activity("spar").ok, "spar requires actual training")
	_check(not state.begin_activity("hermit_visit").ok, "hermit requires actual insight")
	_check(not state.begin_activity("escort_promise").ok, "escort requires a completed courier job")
	_do(state, "sword_lesson")
	_check(state.has_skill("sword_qi") and state.data.favor.shen == 2, "lesson teaches sword skill and establishes relationship")
	var before: Dictionary = state.data.duplicate(true)
	_check(not state.complete_activity().ok and state.data == before, "duplicate completion cannot issue a second reward")
	_check(not state.begin_activity("sword_lesson").ok and state.data == before, "one-time activity cannot be repeated")
	_do(state, "practice")
	_do(state, "spar")
	_check(state.data.training == 5 and state.data.favor.shen == 3, "training unlocks useful sparring rewards")
	_do(state, "courier_work")
	_do(state, "escort_promise")
	_check(state.has_kept_promise() and state.exploration_count() == 1, "escort records promise and distinct exploration")
	_do(state, "missing_letter")
	_check(state.data.favor.zhou == 5, "special promises can lift favor above job cap")
	_do(state, "courier_work")
	_check(state.data.favor.zhou == 5, "repeating capped job must not reduce existing favor")
	var scholar: RefCounted = _fresh()
	for index in range(6):
		_do(scholar, "meditate")
	_check(scholar.data.insight == 6 and not scholar.activity_status("meditate").ok, "repeatable study stops at its disclosed insight cap")
	var jobs: RefCounted = _fresh()
	for index in range(4):
		_do(jobs, "stage_work")
	_check(jobs.data.favor.xiao == 3 and jobs.data.money == 88, "repeat jobs keep wages but cap shallow acquaintance")

func _test_complete_routes() -> void:
	for origin in Data.ORIGINS:
		var training: RefCounted = _training_route(origin)
		_check(training.data.spent == 8 and training.data.training == 6, "training route fits eight slots: " + origin)
		_check(training.has_skill("sword_qi") and not training.has_skill("cloud_step"), "training route has distinct martial style: " + origin)
		_fill_week(training)
		_check(training.begin_exam().ok, "training route reaches exam: " + origin)
		_check(training.complete_exam(false).ok, "surrender still resolves prepared route: " + origin)
		_check(training.data.exam_result.eligible == ["zhaoling"], "kept promise earns Zhaoling despite surrender: " + origin)
		_check(not training.choose_school("duyun").ok, "unearned school cannot be selected: " + origin)
		_check(training.choose_school("zhaoling").ok and training.data.phase == "ending", "training route ending: " + origin)
		_check(not training.choose_school("stay").ok and not training.complete_exam(true).ok, "ending cannot be overwritten or exam rewarded twice: " + origin)
		var social: RefCounted = _social_route(origin)
		_check(social.data.spent == 7 and social.data.insight >= 6, "social route fits seven slots: " + origin)
		_check(social.has_skill("cloud_step") and not social.has_skill("sword_qi"), "social route has distinct martial style: " + origin)
		_fill_week(social)
		_check(social.begin_exam().ok and social.complete_exam(false).ok, "social route can concede exam: " + origin)
		_check(social.data.exam_result.eligible == ["duyun"], "experience and relationship earn Duyun: " + origin)
		_check(social.choose_school("duyun").ok, "social route ending: " + origin)
		print("ROUTE VERIFIED: %s; training 8/21 slots -> zhaoling; social 7/21 slots -> duyun" % origin)
	var mixed: RefCounted = _fresh()
	for id in ["sword_lesson", "practice", "practice", "practice", "missing_letter", "grove_survey", "ridge_tracks", "hermit_visit"]:
		_do(mixed, id)
	_check(mixed.data.spent == 14 and mixed.data.training == 6 and mixed.data.insight == 7, "mixed route is a deliberate 14-slot investment")
	_check(mixed.prepare_exam_now().ok and mixed.begin_exam().ok and mixed.complete_exam(false).ok, "mixed route resolves without forced victory")
	_check(mixed.data.exam_result.eligible == ["zhaoling", "duyun"], "both invitations remain player choice")
	_check(mixed.choose_school("stay").ok, "player may decline both offers")
	var failure: RefCounted = _fresh()
	_check(failure.prepare_exam_now().ok and failure.begin_exam().ok and failure.retreat_activity().ok, "unprepared player can surrender immediately")
	_check(failure.data.exam_result.eligible.is_empty() and failure.choose_school("stay").ok, "unprepared failure has complete stay ending")
	var merit: RefCounted = _fresh()
	_do(merit, "sword_lesson")
	for index in range(4):
		_do(merit, "practice")
	_check(merit.eligible_schools(false).is_empty() and merit.eligible_schools(true) == ["zhaoling"], "exam victory can replace kept promise")
	var observation: RefCounted = _fresh()
	_do(observation, "ridge_tracks")
	for index in range(4):
		_do(observation, "meditate")
	_check(observation.eligible_schools(false).is_empty() and observation.eligible_schools(true) == ["duyun"], "exam victory can supplement one exploration")

func _test_pending_and_retry() -> void:
	var state: RefCounted = _fresh()
	_check(state.begin_activity("herb_errand").ok, "begin encounter")
	var token: int = state.data.pending.token
	state.data.pending.stage = "combat"
	state.data.pending.visited = ["bamboo_mark", "basket"]
	state.data.pending.world_position = [240.0, 320.0]
	state.data.pending.combat = {"player": {"hp": 20, "position": [400, 300]}, "medicine_used": 2, "enemies": [{"hp": 10, "kind": "bandit"}]}
	_check(not state.complete_activity("success", {"medicine_used": 5}).ok, "invalid medicine use does not settle")
	_check(not state.complete_activity("success", {"medicine_used": -1}).ok, "negative medicine cannot manufacture inventory")
	_check(not state.complete_activity("success", {"medicine_used": 0.5}).ok, "fractional medicine rejected")
	_check(state.data.medicine == 4 and state.data.spent == 2, "failed or pending combat hasn't consumed run resources")
	_check(state.retry_activity().ok and state.data.pending.attempt == 1, "can retry an encounter")
	_check(state.data.pending.combat.is_empty() and state.data.pending.visited.size() == 2 and state.data.pending.stage == "combat", "retry resets combat but preserves completed exploration")
	_check(state.data.spent == 2 and state.data.medicine == 4, "retry restores initial inventory without charging time")
	_check(state.complete_activity("success", {"medicine_used": 1, "pending_token": token}).ok, "winning attempt settles its own medicine usage")
	_check(state.data.medicine == 7 and state.data.insight == 1, "consumption then origin-adjusted reward applied exactly once")
	_check(not state.complete_activity("success", {"medicine_used": 1, "pending_token": token}).ok and state.data.medicine == 7, "duplicate settlement consumes neither medicine nor rewards")
	_check(state.begin_activity("practice").ok, "start next transaction")
	_check(not state.complete_activity("success", {"pending_token": token}).ok and state.data.training == 0, "stale callback cannot complete a different activity")
	_check(not state.retreat_activity({"medicine_used": 2}).ok, "one battle cannot consume a second dose")
	_check(state.retreat_activity({"medicine_used": 1}).ok and state.data.medicine == 6, "retreat commits used medicine but no completion rewards")
	_check(state.data.spent == 3 and state.data.training == 0 and "practice" not in state.data.completed, "abandoned fight retains only committed time")
	_check(state.prepare_exam_now().ok and state.begin_exam().ok, "begin exam for resource retry")
	_check(state.retry_activity().ok and state.data.spent == 21, "exam retry costs no further time")
	_check(state.complete_exam(false, {"medicine_used": 1}).ok and state.data.medicine == 5, "exam surrender settles medicine once")
	_check(not state.complete_exam(false, {"medicine_used": 1}).ok and state.data.medicine == 5, "exam cannot consume a second dose")

func _test_persistence() -> void:
	_clean_save()
	var state: RefCounted = _fresh("courier")
	_do(state, "courier_work")
	_do(state, "sword_lesson")
	_check(state.begin_activity("escort_promise").ok, "begin expedition before save")
	state.data.world_position = [601.5, 431.25]
	state.data.pending.stage = "combat"
	state.data.pending.visited = ["old_sign", "medicine_cart"]
	state.data.pending.world_position = [399, 287]
	var battle: RefCounted = Battle.new()
	_check(battle.configure("ridge", state.battle_stats()).ok, "real card encounter fixture initializes")
	state.data.pending.combat = battle.snapshot()
	state.data.dialogue = {"title": "activity_escort_promise", "cursor": "21", "revision": "revision-v1", "after": "activity_briefed", "return_npc": "zhou"}
	var saved: Dictionary = state.save_game(SAVE)
	_check(saved.ok, "atomic pending save succeeds: " + str(saved.message))
	if not saved.ok:
		return
	_check(FileAccess.file_exists(SAVE) and not FileAccess.file_exists(SAVE + ".tmp"), "completed atomic save has no temporary file")
	var restored: RefCounted = Run.new()
	var loaded: Dictionary = restored.load_game(SAVE)
	_check(loaded.ok, "pending save loads: " + str(loaded.message))
	if not loaded.ok:
		_clean_save()
		return
	_check(restored.data.origin == "courier" and restored.data.spent == 6 and restored.data.money == 54, "identity, original costs, fee and income survive")
	_check(restored.data.favor.zhou == 1 and restored.has_skill("sword_qi") and restored.data.completed.has("courier_work"), "relationships, skills, reward ledger survive")
	_check(restored.data.world_position == state.data.world_position and restored.data.dialogue == state.data.dialogue, "walking and dialogue cursor survive")
	_check(restored.data.pending.stage == "combat" and restored.data.pending.visited == state.data.pending.visited and _same_json(restored.data.pending.combat, state.data.pending.combat), "exploration and mid-combat checkpoint survive")
	_check(restored.data.pending.token == state.data.pending.token and _same_json(restored.data.pending.world_position, state.data.pending.world_position), "transaction and exploration position survive")
	_check(restored.retry_activity().ok and restored.data.medicine == 2 and restored.data.spent == 6, "loaded retry restores medicine and preserves paid time")
	_check(restored.complete_activity("success", {"medicine_used": 1}).ok, "loaded pending activity completes")
	_check(restored.data.money == 86 and restored.data.medicine == 1 and restored.data.training == 3, "loaded outcome issues exactly the outstanding reward")
	_check(restored.save_game(SAVE).ok and FileAccess.file_exists(SAVE + ".bak"), "replacement retains prior valid checkpoint")
	var settled: RefCounted = Run.new()
	_check(settled.load_game(SAVE).ok and settled.data.pending.is_empty(), "settled save does not replay encounter")
	_check(not settled.complete_activity().ok and settled.data.money == 86, "loading settled save cannot reissue reward")
	_write_raw(SAVE, "{invalid")
	var recovered: RefCounted = Run.new()
	var result: Dictionary = recovered.load_game(SAVE)
	_check(result.ok and result.recovered and recovered.data.pending.id == "escort_promise", "corrupt primary recovers previous complete checkpoint")
	_check(recovered.data.money == 54 and recovered.data.spent == 6, "backup recovery is coherent rather than mixing rewards and pending state")
	_clean_save()
	var ending: RefCounted = _social_route("performer")
	ending.prepare_exam_now()
	ending.begin_exam()
	ending.data.pending.stage = "combat"
	_check(ending.save_game(SAVE).ok, "exam pending save validates")
	var exam_restored: RefCounted = Run.new()
	_check(exam_restored.load_game(SAVE).ok and exam_restored.data.phase == "exam", "exam save returns to exam")
	_check(exam_restored.complete_exam(false).ok and exam_restored.choose_school("duyun").ok, "loaded exam resolves to selected ending")
	_check(exam_restored.save_game(SAVE).ok, "ending save validates")
	var last: RefCounted = Run.new()
	_check(last.load_game(SAVE).ok and last.data.school == "duyun" and last.data.phase == "ending", "ending and invitations survive reload")

func _test_invalid_saves() -> void:
	_clean_save()
	var state: RefCounted = _fresh()
	var original: Dictionary = state.data.duplicate(true)
	_check(not state.load_game(SAVE).ok and state.data == original, "missing save doesn't replace active run")
	for raw in ["null", "[]", "{", "{\"version\":2,\"data\":{}}", "{\"version\":1,\"data\":{}}"]:
		_write_raw(SAVE, raw)
		_check(not state.load_game(SAVE).ok and state.data == original, "malformed or unsupported envelope leaves active run intact")
	var corruptions: Array = [
		{"spent": -1}, {"spent": 22}, {"spent": 0.5}, {"money": -5}, {"medicine": "4"},
		{"origin": "mage"}, {"phase": "unknown"}, {"hero_name": ""}, {"skills": ["flight"]},
		{"skills": ["sword_qi", "sword_qi"]}, {"completed": ["unknown"]}, {"favor": {}},
		{"pending": []}, {"phase": "activity"}, {"exam_result": {"won": true}},
		{"school": "duyun"}, {"world_position": [2]}, {"world_position": [0, 20000]},
		{"dialogue": {"cursor": 12}}, {"dialogue": {"unknown": "value"}},
		{"journal": [{"day": 99, "text": "bad"}]},
	]
	for corruption in corruptions:
		var invalid: Dictionary = original.duplicate(true)
		for key in corruption:
			invalid[key] = corruption[key]
		_write_raw(SAVE, JSON.stringify({"version": Run.SAVE_VERSION, "data": invalid}))
		_check(not state.load_game(SAVE).ok and state.data == original, "invalid field rejected without mutation: " + str(corruption))
	var pending: RefCounted = _fresh()
	pending.begin_activity("grove_survey")
	for corruption in [{"cost": 1}, {"start_spent": 3}, {"token": 0}, {"id": "unknown"}, {"stage": "invented"}, {"combat": []}, {"visited": [3]}, {"world_position": "oops"}]:
		var invalid: Dictionary = pending.data.duplicate(true)
		for key in corruption:
			invalid.pending[key] = corruption[key]
		_write_raw(SAVE, JSON.stringify({"version": Run.SAVE_VERSION, "data": invalid}))
		_check(not state.load_game(SAVE).ok and state.data == original, "invalid transaction rejected: " + str(corruption))
	_clean_save()
	_check(state.save_game(SAVE).ok, "valid save before refusing invalid in-memory data")
	state.data.spent = 25
	_check(not state.save_game(SAVE).ok, "invalid in-memory save rejected")
	var intact: RefCounted = Run.new()
	_check(intact.load_game(SAVE).ok and intact.data.spent == 0, "invalid save attempt preserves last valid file")
	_clean_save()
	_write_raw(SAVE, "x".repeat(Run.MAX_SAVE_BYTES + 1))
	_check(not intact.load_game(SAVE).ok and intact.data.spent == 0, "oversized save rejected without replacing state")

func _write_raw(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check(false, "test could write temporary fixture")
		return
	file.store_string(text)
	file.close()

func _same_json(left: Variant, right: Variant) -> bool:
	# JSON represents every number as float; compare after that intentional conversion.
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))

func _clean_save() -> void:
	for path in [SAVE, SAVE + ".tmp", SAVE + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
