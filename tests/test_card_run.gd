extends SceneTree
## Integration checks for creation, permanent learning and transactional card fights.
const Run = preload("res://scripts/run_state.gd")
const Data = preload("res://scripts/game_data.gd")
const Cards = preload("res://scripts/card_catalog.gd")
const Creation = preload("res://scripts/character_creation.gd")
const Battle = preload("res://scripts/card_battle.gd")
const SAVE = "user://test-card-rules-v2.json"
var passed: int = 0
var failed: int = 0
var _answer_sets: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_clean()
	_test_creation_and_draft_save()
	_test_decks_and_unlocks()
	_test_mastery_and_fortune()
	_test_locked_battle_and_resume()
	_test_both_routes()
	_test_corrupt_card_saves()
	_clean()
	print("TESTS COMPLETE: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check(ok: bool, message: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL: " + message)

func _fresh(origin: String = "herbalist") -> RefCounted:
	var state: RefCounted = Run.new()
	state.new_run("望溪客", origin)
	return state

func _do(state: RefCounted, id: String) -> void:
	var result: Dictionary = state.begin_activity(id)
	_check(bool(result.ok), "can schedule " + id)
	if result.ok: _check(state.complete_activity().ok, "can settle " + id)

func _sum(attributes: Dictionary) -> int:
	var total: int = 0
	for value in attributes.values(): total += int(value)
	return total

func _answers_for(key: String, high: bool) -> Array:
	var cache_key: String = key + str(high)
	if _answer_sets.has(cache_key): return _answer_sets[cache_key].duplicate()
	for encoded in range(729):
		var rest: int = encoded
		var draft: Dictionary = Creation.draft()
		var answers: Array = []
		for index in range(6):
			var choice: int = rest % 3
			rest /= 3
			answers.append(choice)
			var result: Dictionary = Creation.with_answer(draft, index, choice)
			if not bool(result.ok): break
			draft = result.creation
		if answers.size() != 6 or not Creation.validate(draft, true).ok: continue
		var attributes: Dictionary = Creation.final_attributes(draft)
		if (int(attributes[key]) >= 6) == high:
			_answer_sets[cache_key] = answers
			return answers
	_check(false, "questionnaire permits requested ability tendency: " + cache_key)
	return [0, 0, 0, 0, 0, 0]

func _with_tendency(key: String, high: bool, origin: String = "herbalist") -> RefCounted:
	var state: RefCounted = Run.new()
	state.start_creation("問路人", origin)
	var answers: Array = _answers_for(key, high)
	for index in range(6): _check(state.set_creation_answer(index, answers[index]).ok, "answer scenario " + str(index))
	_check(state.confirm_creation().ok, "confirm complete creation")
	return state

func _test_creation_and_draft_save() -> void:
	var state: RefCounted = Run.new()
	state.start_creation("小溪", "courier")
	_check(state.data.phase == "prologue" and _sum(state.data.attributes) == 24 and state.remaining() == 21, "unanswered prologue is a draft before the week starts")
	_check(not state.confirm_creation().ok and not state.begin_activity("rest").ok and not state.prepare_exam_now().ok, "unfinished draft cannot skip into calendar or exam")
	_check(not state.set_deck(Cards.starting_deck()).ok and not state.upgrade_card("strike").ok, "draft cannot use town workshop")
	var before: Dictionary = state.data.duplicate(true)
	_check(not state.set_creation_answer(-1, 0).ok and not state.set_creation_answer(6, 0).ok and not state.set_creation_answer(0, 3).ok and state.data == before, "invalid question edits are atomic")
	_check(state.set_creation_answer(0, 1).ok and _sum(state.data.attributes) == 25, "each scenario awards exactly one point")
	_check(state.save_game(SAVE).ok, "partial answered prologue can be saved")
	var loaded: RefCounted = Run.new()
	_check(loaded.load_game(SAVE).ok and _same(loaded.data.creation, state.data.creation) and loaded.data.phase == "prologue", "draft page and hidden answer choices survive reload")
	for index in range(1, 6): _check(loaded.set_creation_answer(index, index % 3).ok, "finish loaded scenario " + str(index))
	_check(_sum(loaded.data.attributes) == 30, "six answers preserve fixed total thirty")
	_check(loaded.move_creation_point("constitution", "strength").ok and loaded.move_creation_point("strength", "constitution").ok, "two one-point transfers are permitted")
	before = loaded.data.duplicate(true)
	_check(not loaded.move_creation_point("constitution", "strength").ok and loaded.data == before, "a reversed transfer still consumes its adjustment allowance")
	_check(loaded.reset_creation_adjustments().ok and Creation.summary(loaded.data.creation).moves_used == 0, "reset returns to answer-derived abilities")
	_check(loaded.move_creation_point("constitution", "strength").ok and loaded.set_creation_answer(5, 1).ok and Creation.summary(loaded.data.creation).moves_used == 0, "editing an answer clears old adjustments")
	_check(loaded.confirm_creation().ok and loaded.data.phase == "intro" and _sum(loaded.data.attributes) == 30, "confirmation starts the story without creating extra points")
	before = loaded.data.duplicate(true)
	_check(not loaded.confirm_creation().ok and not loaded.set_creation_answer(0, 0).ok and not loaded.reset_creation_adjustments().ok and loaded.data == before, "confirmed creation cannot replay rewards or rewrite abilities")
	_check(loaded.story_context().creation_motivation != "" and loaded.story_context().creation_approach != "", "motivation and road choices reach later dialogue")
	_check(loaded.save_game(SAVE).ok, "confirmed creation validates for persistence")
	for origin in Data.ORIGINS:
		var compatible: RefCounted = _fresh(origin)
		_check(compatible.data.phase == "intro" and _sum(compatible.data.attributes) == 30 and Creation.validate(compatible.data.creation, true).ok, "programmatic new_run remains valid for " + origin)
	_clean()

func _test_decks_and_unlocks() -> void:
	for origin in Data.ORIGINS:
		var state: RefCounted = _fresh(origin)
		_check(state.data.learned_cards.size() == 6 and Cards.validate_deck(state.data.deck, state.data.learned_cards).ok, "five basics fill the first deck for " + origin)
		var chosen: Array = state.data.deck.duplicate()
		chosen[0] = Cards.ORIGIN_CARDS[origin]
		chosen[1] = Cards.ORIGIN_CARDS[origin]
		var money: int = state.data.money
		_check(state.set_deck(chosen).ok and state.data.money == money and state.data.spent == 0, "learned origin card supplies two free copies")
		chosen[0] = "unknown"
		_check(state.data.deck[0] == Cards.ORIGIN_CARDS[origin], "caller cannot mutate stored deck through its input array")
		var before: Dictionary = state.data.duplicate(true)
		for invalid in [[], ["strike"], ["strike", "strike", "strike", "guard", "guard", "breath", "breath", "observe", "observe", "feint"], ["sword_qi", "sword_qi", "guard", "guard", "breath", "breath", "observe", "observe", "feint", "feint"], [null, "strike", "guard", "guard", "breath", "breath", "observe", "observe", "feint", "feint"]]:
			_check(not state.set_deck(invalid).ok and state.data == before, "invalid size, copies or unlearned card cannot replace deck")
		for activity in ["medicine_lesson", "courier_work", "stage_work"]: _do(state, activity)
		for card_id in Cards.ORIGIN_CARDS.values(): _check(card_id in state.data.learned_cards, "all origins can learn every trade: " + card_id)
		var learned_count: int = state.data.learned_cards.size()
		_do(state, "courier_work")
		_check(state.data.learned_cards.size() == learned_count, "repeat work never grants duplicate card ownership")
	var apprentice: RefCounted = _fresh()
	_do(apprentice, "sword_lesson")
	_check("sword_qi" in apprentice.data.learned_cards and "steady_guard" in apprentice.data.learned_cards and "opening_thrust" not in apprentice.data.learned_cards, "first lesson gives two starter school cards")
	_do(apprentice, "practice")
	_do(apprentice, "spar")
	_check("opening_thrust" in apprentice.data.learned_cards and apprentice.data.mastery == 3, "sparring unlocks advanced card and actual practice progress")
	var traveler: RefCounted = _fresh()
	_do(traveler, "ridge_tracks")
	_check("cloud_step" in traveler.data.learned_cards and "flowing_cut" not in traveler.data.learned_cards, "ridge teaches the first Duyun card")
	_do(traveler, "grove_survey")
	_do(traveler, "hermit_visit")
	for id in ["flowing_cut", "returning_swallow", "mountain_echo"]: _check(id in traveler.data.learned_cards, "travel route learns " + id)
	for activity in ["bridge_repair", "missing_letter", "old_ballad"]:
		var event: RefCounted = _fresh()
		_do(event, activity)
		for id in Cards.cards_for_activity(activity): _check(id in event.data.learned_cards, "completed event unlocks its authored card: " + activity)

func _test_mastery_and_fortune() -> void:
	var regular: RefCounted = _with_tendency("aptitude", false)
	_do(regular, "practice")
	_check(not regular.upgrade_status("strike").ok and not regular.upgrade_card("strike").ok and regular.data.mastery == 1, "low aptitude can progress but needs ordinary two practice points")
	_do(regular, "practice")
	_check(regular.upgrade_card("strike").ok and regular.data.mastery == 0 and not regular.data.aptitude_discount_used, "ordinary practice unlocks exactly the same upgrade")
	var before: Dictionary = regular.data.duplicate(true)
	_check(not regular.upgrade_card("strike").ok and not regular.upgrade_card("sword_qi").ok and regular.data == before, "duplicate or unlearned upgrades consume nothing")
	var talented: RefCounted = _with_tendency("aptitude", true)
	_do(talented, "practice")
	_check(talented.upgrade_status("strike").cost == 1 and talented.upgrade_card("strike").ok and talented.data.aptitude_discount_used, "high aptitude discounts the first upgrade once")
	_do(talented, "practice")
	_check(talented.upgrade_status("guard").cost == 2 and not talented.upgrade_card("guard").ok, "second upgrade never reuses aptitude discount")
	_do(talented, "practice")
	_check(talented.upgrade_card("guard").ok and talented.data.upgraded_cards == ["strike", "guard"], "later upgrades use ordinary progress")
	_check(talented.save_game(SAVE).ok, "upgrade and one-time discount persist")
	var restored: RefCounted = Run.new()
	_check(restored.load_game(SAVE).ok and restored.upgrade_status("feint").cost == 2 and restored.data.aptitude_discount_used, "load cannot refresh upgrade shortcut")
	_clean()
	var lucky: RefCounted = _with_tendency("fortune", true)
	_do(lucky, "courier_work")
	_check(not lucky.data.fortune_hint_used, "town activities never consume the exploration hint")
	_check(lucky.begin_activity("grove_survey").ok and lucky.data.pending.fortune_hint != "" and lucky.data.fortune_hint_used, "first exploration reveals a fixed authored clue")
	var hint: String = lucky.data.pending.fortune_hint
	_check(lucky.retry_activity().ok and lucky.data.pending.fortune_hint == hint and lucky.data.pending.visited.is_empty(), "hint survives retry but does not auto-complete investigation")
	_check(lucky.retreat_activity().ok and lucky.begin_activity("ridge_tracks").ok and lucky.data.pending.fortune_hint == "", "retreat does not replenish the once-only clue")
	var observant: RefCounted = _with_tendency("fortune", false)
	_check(observant.begin_activity("grove_survey").ok and observant.data.pending.fortune_hint == "", "low fortune still has full exploration access")
	_check(observant.complete_activity().ok and "mountain_echo" in observant.data.learned_cards, "ordinary investigation earns the same core card")

func _test_locked_battle_and_resume() -> void:
	var state: RefCounted = _fresh()
	_check(state.begin_activity("herb_errand").ok, "start saved encounter")
	var stats: Dictionary = state.battle_stats()
	var seed: int = state.data.pending.seed
	var fixed_deck: Array = state.data.pending.deck.duplicate()
	stats.deck.clear()
	stats.attributes.constitution = 99
	_check(state.data.pending.deck == fixed_deck and state.data.pending.attributes.constitution != 99, "battle_stats returns defensive copies of locked inputs")
	_check(not state.set_deck(Cards.starting_deck()).ok and not state.upgrade_card("strike").ok, "active encounter forbids changing the prepared build")
	var battle: RefCounted = Battle.new()
	_check(battle.configure("grove", state.battle_stats()).ok, "card battle accepts the locked run stats")
	var initial: Dictionary = battle.snapshot()
	_check(battle.mulligan([0]).ok, "make a real opening choice")
	_check(battle.end_turn().ok, "resolve a real enemy turn")
	if battle.data.hp == battle.data.max_hp: battle.end_turn()
	_check(battle.use_medicine().ok, "pending snapshot can contain committed-in-battle medicine")
	state.data.pending.stage = "combat"
	state.data.pending.visited = ["first", "second"]
	state.data.pending.combat = battle.snapshot()
	var carried: int = state.data.medicine
	_check(state.save_game(SAVE).ok and state.data.medicine == carried, "mid-battle save does not settle medicine early")
	var loaded: RefCounted = Run.new()
	var load_result: Dictionary = loaded.load_game(SAVE)
	_check(load_result.ok and _same(loaded.data.get("pending", {}).get("combat", {}), state.data.pending.combat), "JSON restores hand, piles, RNG and actual enemy state: " + str(load_result.message))
	if not bool(load_result.ok):
		_clean()
		return
	var resumed: RefCounted = Battle.new()
	_check(resumed.configure("grove", loaded.battle_stats(), loaded.data.pending.combat).ok, "saved run reopens the exact battle")
	_check(_same(resumed.snapshot(), battle.snapshot()), "resume changes neither phase nor random order")
	loaded.data.pending.report = {"medicine_used": 1, "pending_token": loaded.data.pending.token}
	loaded.data.pending.battle_won = false
	loaded.data.pending.stage = "defeat"
	_check(loaded.retry_activity().ok and loaded.data.pending.seed == seed and loaded.data.pending.deck == fixed_deck, "retry preserves seed and frozen deck")
	_check(loaded.data.pending.combat.is_empty() and not loaded.data.pending.has("report") and loaded.data.pending.stage == "combat", "retry removes prior settlement and defeat checkpoint")
	var replay: RefCounted = Battle.new()
	_check(replay.configure("grove", loaded.battle_stats()).ok and _same(replay.snapshot(), initial), "same attempt rebuilds the same opening, not a free reroll")
	var token: int = loaded.data.pending.token
	_check(loaded.complete_activity("success", {"medicine_used": 1, "pending_token": token}).ok and loaded.data.medicine == carried - 1 + 4, "only settled attempt consumes medicine and grants origin reward")
	var settled: Dictionary = loaded.data.duplicate(true)
	_check(not loaded.complete_activity("success", {"medicine_used": 1, "pending_token": token}).ok and loaded.data == settled, "duplicate callback cannot consume medicine or grant cards twice")
	_clean()

func _test_both_routes() -> void:
	for origin in Data.ORIGINS:
		for social in [false, true]:
			var state: RefCounted = _fresh(origin)
			var route: Array = ["grove_survey", "ridge_tracks", "hermit_visit"] if social else ["sword_lesson", "practice", "spar", "practice", "missing_letter"]
			for activity in route: _do(state, activity)
			var new_cards: Array = ["cloud_step", "flowing_cut", "returning_swallow"] if social else ["sword_qi", "steady_guard", "opening_thrust"]
			for card_id in new_cards: _check(card_id in state.data.learned_cards, "route learns complete school set for " + origin)
			var deck: Array = ["strike", "strike", "guard", "guard", new_cards[0], new_cards[0], new_cards[1], new_cards[1], new_cards[2], new_cards[2]]
			_check(state.set_deck(deck).ok and state.data.spent == (7 if social else 8), "route fits original time budget with a legal distinctive deck")
			while state.remaining() > 0: _do(state, "rest")
			_check(state.begin_exam().ok and state.battle_stats().deck == deck, "exam locks route-specific deck")
			_check(state.complete_exam(false).ok, "card exam can still be conceded")
			var school: String = "duyun" if social else "zhaoling"
			_check(state.data.exam_result.eligible == [school] and state.choose_school(school).ok, "preparation earns expected ending even after concession")
			_check(not state.set_deck(Cards.starting_deck()).ok and not state.upgrade_card("strike").ok, "completed story cannot mutate its build")
			_check(state.save_game(SAVE).ok, "complete route ending saves")
			_clean()
			print("CARD ROUTE VERIFIED: %s -> %s" % [origin, school])

func _test_corrupt_card_saves() -> void:
	var state: RefCounted = _fresh()
	var valid: Dictionary = state.data.duplicate(true)
	var corruptions: Array = [
		{"attributes": {}}, {"attributes": {"constitution": 99}}, {"creation": {}},
		{"mastery": -1}, {"mastery": 1.5}, {"aptitude_discount_used": "true"}, {"fortune_hint_used": 1},
		{"learned_cards": ["strike"]}, {"upgraded_cards": ["sword_qi"]}, {"deck": Cards.starting_deck() + ["strike"]},
	]
	for fields in corruptions:
		var invalid: Dictionary = valid.duplicate(true)
		for key in fields: invalid[key] = fields[key]
		_reject_save(state, invalid, "malformed card/creation field: " + str(fields))
	var altered: Dictionary = valid.duplicate(true)
	altered.attributes.constitution = int(altered.attributes.constitution) + 1
	_reject_save(state, altered, "ability cannot drift from saved answers")
	_check(state.begin_activity("practice").ok, "create pending corruption fixtures")
	var battle: RefCounted = Battle.new()
	battle.configure("practice", state.battle_stats())
	state.data.pending.combat = battle.snapshot()
	state.data.pending.stage = "combat"
	for fields in [{"seed": -1}, {"seed": 1.5}, {"seed": 2147483648}, {"deck": []}, {"attributes": {}}, {"upgraded_cards": ["strike"]}, {"medicine_at_start": 99}, {"fortune_hint": "forged"}, {"combat": {"version": 1}}]:
		var invalid: Dictionary = state.data.duplicate(true)
		for key in fields: invalid.pending[key] = fields[key]
		_reject_save(state, invalid, "malformed locked encounter: " + str(fields))
	var bad_piles: Dictionary = state.data.duplicate(true)
	bad_piles.pending.combat.hand.append("strike")
	_reject_save(state, bad_piles, "snapshot cannot manufacture an extra card")
	_write(JSON.stringify({"version": 1, "data": state.data}))
	var before: Dictionary = state.data.duplicate(true)
	_check(not state.load_game(SAVE).ok and state.data == before, "v1 action-game envelope is not imported into card run")
	_check(Run.SAVE_PATH == "user://run-cards-v2.json" and Run.SAVE_VERSION == 2, "card save namespace remains isolated from existing prototype")
	_clean()

func _reject_save(state: RefCounted, invalid: Dictionary, message: String) -> void:
	_clean()
	_write(JSON.stringify({"version": Run.SAVE_VERSION, "data": invalid}))
	var before: Dictionary = state.data.duplicate(true)
	_check(not state.load_game(SAVE).ok and state.data == before, message)

func _write(text: String) -> void:
	var file: FileAccess = FileAccess.open(SAVE, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _same(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))

func _clean() -> void:
	for path in [SAVE, SAVE + ".tmp", SAVE + ".bak"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
