extends SceneTree
## Integration checks for creation, permanent learning and transactional card fights.
const Run = preload("res://scripts/run_state.gd")
const Data = preload("res://scripts/game_data.gd")
const Cards = preload("res://scripts/card_catalog.gd")
const Creation = preload("res://scripts/character_creation.gd")
const Battle = preload("res://scripts/card_battle.gd")
const SAVE = "user://test-card-rules-v3.json"
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
	_test_opportunities()
	_test_lab_and_choice_resume()
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
		_check(state.data.learned_cards.size() == 6 and Cards.validate_deck(state.data.deck, state.data.learned_cards, "sword").ok, "five basics fill a valid initial deck for " + origin)
		_check(state.data.inner == "guiyuan" and state.data.learned_inners == ["guiyuan"], "all origins begin with the same accessible inner")
		var chosen: Array = state.data.deck.duplicate()
		chosen[0] = "gather_momentum"
		chosen[1] = "gather_momentum"
		var money: int = state.data.money
		_check(state.set_loadout(chosen, "unarmed", "guiyuan").ok and state.data.money == money and state.data.spent == 0, "atomic loadout can change to a legal unarmed deck for free")
		chosen[0] = "unknown"
		_check(state.data.deck[0] == "gather_momentum", "caller cannot mutate stored deck through input array")
		var before: Dictionary = state.data.duplicate(true)
		for invalid in [[], ["strike"], ["strike", "strike", "strike", "guard", "guard", "breath", "breath", "observe", "observe", "probing_stone"], ["sword_qi", "sword_qi", "guard", "guard", "breath", "breath", "observe", "observe", "probing_stone", "probing_stone"], [null, "strike", "guard", "guard", "breath", "breath", "observe", "observe", "probing_stone", "probing_stone"]]:
			_check(not state.set_deck(invalid).ok and state.data == before, "invalid copies, size, permission or weapon are atomic")
		_check(not state.set_loadout(Cards.starting_deck(), "unarmed", "guiyuan").ok and state.data == before, "sword cards cannot be equipped unarmed")
		_check(not state.set_loadout(state.data.deck, "sword", "shouzhong").ok and state.data == before, "unlearned inner cannot be equipped")
		_check(not state.set_loadout(state.data.deck, "wand", "guiyuan").ok and state.data == before, "unsupported weapon rejected")
		for activity in ["sword_lesson", "practice", "spar", "grove_survey", "ridge_tracks", "hermit_visit"]: _do(state, activity)
		_check(state.data.learned_cards.size() == 12 and state.data.learned_inners.size() == 3, "guaranteed activities teach every prototype card and inner for " + origin)
		var learned_count: int = state.data.learned_cards.size()
		_do(state, "practice")
		_check(state.data.learned_cards.size() == learned_count, "repeat practice never duplicates ownership")
		_check(state.save_game(SAVE).ok, "learned cards and inners follow actual event ledger")
		_clean()

func _test_mastery_and_fortune() -> void:
	var regular: RefCounted = _with_tendency("aptitude", false)
	_do(regular, "sword_lesson")
	_do(regular, "practice")
	_check(not regular.upgrade_status("sword_qi").ok and not regular.upgrade_card("sword_qi").ok and regular.data.mastery == 1, "ordinary aptitude requires two real practice points")
	_do(regular, "practice")
	_check(regular.upgrade_card("sword_qi", "specialist").ok and regular.data.mastery == 0 and not regular.data.aptitude_discount_used, "ordinary practice unlocks specialist for both copies")
	_check(regular.data.refinements.sword_qi == "specialist", "selected refinement stored by card kind")
	var before: Dictionary = regular.data.duplicate(true)
	_check(not regular.upgrade_card("sword_qi").ok and not regular.upgrade_card("cloud_step").ok and not regular.upgrade_card("strike").ok and regular.data == before, "duplicate, unlearned and unsupported refinements spend nothing")
	_check(regular.set_refinement("sword_qi", "stable").ok and regular.data.mastery == 0, "already unlocked alternatives switch freely")
	before = regular.data.duplicate(true)
	_check(not regular.set_refinement("sword_qi", "").ok and not regular.set_refinement("opening_thrust", "stable").ok and regular.data == before, "journey cannot erase chosen refinement or select a locked branch")
	var talented: RefCounted = _with_tendency("aptitude", true)
	_do(talented, "sword_lesson")
	_do(talented, "practice")
	_check(talented.upgrade_status("sword_qi").cost == 1 and talented.upgrade_card("sword_qi").ok and talented.data.aptitude_discount_used, "high aptitude discounts exactly the first upgrade")
	_do(talented, "practice")
	_check(talented.upgrade_status("opening_thrust").cost == 2 and not talented.upgrade_card("opening_thrust").ok, "second upgrade cannot reuse first discount")
	_do(talented, "practice")
	_check(talented.upgrade_card("opening_thrust", "specialist").ok and talented.data.upgraded_cards == ["sword_qi", "opening_thrust"], "later refinement uses regular cost")
	_check(talented.save_game(SAVE).ok, "refinement ownership and first discount save")
	var restored: RefCounted = Run.new()
	_check(restored.load_game(SAVE).ok and restored.data.refinements.opening_thrust == "specialist" and restored.data.aptitude_discount_used, "reload cannot refresh discount or forget chosen branch")
	_clean()
	var lucky: RefCounted = _with_tendency("fortune", true)
	_do(lucky, "courier_work")
	_check(not lucky.data.fortune_hint_used, "town activities do not consume exploration hint")
	_check(lucky.begin_activity("grove_survey").ok and lucky.data.pending.fortune_hint != "" and lucky.data.fortune_hint_used, "first exploration reveals the authored early hint")
	var hint: String = lucky.data.pending.fortune_hint
	_check(lucky.retry_activity().ok and lucky.data.pending.fortune_hint == hint and lucky.data.pending.visited.is_empty(), "retry preserves hint without completing objectives")
	_check(lucky.retreat_activity().ok and lucky.begin_activity("ridge_tracks").ok and lucky.data.pending.fortune_hint == "", "retreat does not refresh once-only convenience")
	var observant: RefCounted = _with_tendency("fortune", false)
	_check(observant.begin_activity("ridge_tracks").ok and observant.data.pending.fortune_hint == "", "low fortune still accesses full core training")
	_check(observant.complete_activity().ok and "cloud_step" in observant.data.learned_cards and "xingyun" in observant.data.learned_inners, "ordinary investigation earns same core card and inner")

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
	# Rules-level route fixtures settle accepted activities; actual combat is checked separately.
	for origin in Data.ORIGINS:
		for social in [false, true]:
			var state: RefCounted = _fresh(origin)
			var route: Array = ["grove_survey", "ridge_tracks", "hermit_visit", "practice"] if social else ["sword_lesson", "practice", "spar", "practice", "missing_letter"]
			for activity in route: _do(state, activity)
			var preset: Dictionary = Cards.PRESETS["xingyun" if social else "shouzhong"]
			_check(state.set_loadout(preset.deck, preset.weapon, preset.inner).ok and state.data.spent == 8, "each origin can learn a complete sample build in eight slots")
			while state.remaining() > 0: _do(state, "rest")
			_check(state.begin_exam().ok and state.battle_stats().deck == preset.deck and state.battle_stats().inner == preset.inner, "exam locks route-specific full loadout")
			_check(state.complete_exam(false).ok, "prepared exam may be conceded")
			var school: String = "duyun" if social else "zhaoling"
			_check(state.data.exam_result.eligible == [school] and state.choose_school(school).ok, "preparation earns the chosen ending even after concession")
			_check(not state.set_deck(Cards.starting_deck()).ok and not state.upgrade_card("sword_qi").ok, "ending prevents workshop mutation")
			_check(state.save_game(SAVE).ok, "complete route saves with earned loadout")
			_clean()
			print("MARTIAL ROUTE VERIFIED: %s -> %s" % [origin, school])

func _test_opportunities() -> void:
	var observed: Dictionary = {}
	for seed in range(1, 25):
		var state: RefCounted = Run.new()
		state.new_run("問路人", "herbalist", seed)
		var same_seed: RefCounted = Run.new()
		same_seed.new_run("另一位", "performer", seed)
		_check(state.data.opportunities == same_seed.data.opportunities and state.data.encounter_variants == same_seed.data.encounter_variants, "seed fixes opportunities and foes independently of origin")
		observed[str(state.data.opportunities)] = true
		for id in ["bridge_repair", "old_ballad"]:
			var before: Dictionary = state.data.duplicate(true)
			var preview: Dictionary = state.activity_preview(id)
			_check(not preview.text.is_empty() and preview.card_id == state.data.opportunities[id] and state.data == before, "optional lesson and reward are disclosed before paying")
		_check(not state.activity_preview("ridge_tracks").encounter_variant.is_empty(), "encounter clue available before expedition cost")
	_check(observed.size() > 1, "fresh journeys actually offer different optional lessons")
	var learner: RefCounted = Run.new()
	learner.new_run("橋邊客", "herbalist", 1)
	var choice: String = learner.data.opportunities.bridge_repair
	_do(learner, "sword_lesson")
	_do(learner, "practice")
	if choice == "yielding_palm": _do(learner, "spar")
	_do(learner, "courier_work")
	var mastery: int = learner.data.mastery
	_check(learner.activity_preview("bridge_repair").already_learned, "known optional technique advertises its alternate practice reward")
	_check(learner.begin_activity("bridge_repair").ok and learner.story_context().activity_variant == choice, "accepted variant reaches Dialogue Manager context")
	_check(learner.save_game(SAVE).ok, "pending optional lesson saves")
	var loaded: RefCounted = Run.new()
	_check(loaded.load_game(SAVE).ok and loaded.data.opportunities == learner.data.opportunities, "loading does not reroll optional reward")
	_check(loaded.complete_activity().ok and loaded.data.mastery == mastery + 1, "known technique grants exactly the promised one practice point")
	var settled: Dictionary = loaded.data.duplicate(true)
	_check(not loaded.complete_activity().ok and loaded.data == settled, "optional alternate reward settles only once")
	_check(loaded.begin_activity("ridge_tracks").ok, "start seeded expedition")
	var locked: Dictionary = loaded.battle_stats()
	_check(loaded.retry_activity().ok and loaded.battle_stats() == locked, "retry cannot reroll encounter pattern or opening seed")
	_clean()

func _test_lab_and_choice_resume() -> void:
	for id in Cards.PRESETS:
		var lab: RefCounted = Run.new()
		lab.new_lab(id)
		_check(lab.data.mode == "lab" and lab.data.inner == id and lab.data.deck == Cards.PRESETS[id].deck, "lab loads exact preset " + id)
		_check(lab.data.attributes.values() == [5, 5, 5, 5, 5, 5] and lab.data.refinements.is_empty(), "trial begins with equal abilities and unrefined baseline")
		_check(lab.current_save_path() == Run.LAB_SAVE_PATH and not lab.save_game(Run.SAVE_PATH).ok, "lab cannot overwrite canonical journey save")
		_check(not lab.begin_activity("practice").ok and not lab.buy_medicine().ok and not lab.prepare_exam_now().ok and not lab.begin_exam().ok, "lab cannot farm story calendar, resources or endings")
		_check(lab.set_refinement("sword_qi", "specialist").ok and lab.set_refinement("sword_qi", "").ok, "lab can compare already unlocked refinement with baseline")
		_check(lab.begin_trial("armored", 91).ok, "trial starts against chosen pattern")
		var token: int = lab.data.pending.token
		var locked: Dictionary = lab.battle_stats()
		var before: Dictionary = lab.data.duplicate(true)
		_check(not lab.apply_lab_preset("guiyuan").ok and not lab.set_refinement("sword_qi", "stable").ok and lab.data == before, "active trial locks full build and refinement")
		_check(lab.retry_activity().ok and lab.battle_stats() == locked and lab.data.spent == 0, "trial retry keeps seed/loadout and never spends a day")
		_check(lab.retreat_activity({"medicine_used": 1, "pending_token": token}).ok and lab.data.medicine == 1 and lab.data.completed.is_empty() and lab.data.mastery == 0 and lab.data.money == 0, "trial retreat resets allowance without producing story rewards")
		before = lab.data.duplicate(true)
		_check(not lab.complete_activity("success", {"pending_token": token}).ok and lab.data == before, "trial settlement cannot replay")
		_check(lab.begin_trial("counter", 92).ok, "another trial receives its own transaction")
		before = lab.data.duplicate(true)
		_check(not lab.complete_activity("success", {"pending_token": token}).ok and lab.data == before, "a prior trial callback cannot settle the next trial")
		var victory: Dictionary = lab.complete_activity("success", {"pending_token": int(lab.data.pending.token), "medicine_used": 1})
		_check(victory.ok and victory.rewards.is_empty() and lab.data.trial_history.size() == 2 and lab.data.trial_history[1].won and lab.data.spent == 0 and lab.data.money == 0 and lab.data.mastery == 0 and lab.data.medicine == 1, "trial success records outcome without awarding journey resources or charging medicine twice")
		_check(lab.apply_lab_preset("xingyun").ok and lab.save_game(SAVE).ok, "free preset change and independent trial save validate")
		_check(not lab._read_save(SAVE, "journey").ok, "a lab payload is rejected by journey-mode reader")
		var restored: RefCounted = Run.new()
		_check(restored.load_game(SAVE).ok and restored.data.mode == "lab" and restored.data.trial_history.size() == 2, "trial history and mode restore")
		_clean()
	var lab: RefCounted = Run.new()
	lab.new_lab("xingyun")
	_check(lab.set_refinement("cloud_step", "specialist").ok, "prepare two-card cycle refinement")
	var battle: RefCounted = Battle.new()
	var found: bool = false
	for seed in range(1, 31):
		_check(lab.begin_trial("flurry", seed).ok, "find a reproducible legal cycle hand")
		var started: Dictionary = battle.configure("flurry", lab.battle_stats())
		_check(started.ok, "lab stats configure real model")
		if not started.ok: break
		battle.skip_mulligan()
		var index: int = battle.data.hand.find("cloud_step")
		if index >= 0:
			_check(battle.play_card(index, 0, false).ok and battle.data.phase == "choice", "a real cycle card enters pending-choice phase")
			found = true
			break
		lab.retreat_activity()
	_check(found, "deterministic search found an actual cycle opening")
	if not found: return
	lab.data.pending.combat = battle.snapshot()
	_check(lab.save_game(SAVE).ok, "in-play card and pending cycle selection save in outer run")
	var loaded: RefCounted = Run.new()
	var load_result: Dictionary = loaded.load_game(SAVE)
	_check(load_result.ok, "pending cycle restores with locked lab build: " + str(load_result.message))
	if not load_result.ok:
		_clean()
		return
	var resumed: RefCounted = Battle.new()
	_check(resumed.configure("flurry", loaded.battle_stats(), loaded.data.pending.combat).ok, "restored pending choice configures without restarting")
	var spent_qi: int = int(battle.data.qi)
	_check(battle.resolve_choice([0, 1]).ok and resumed.resolve_choice([0, 1]).ok and _same(battle.snapshot(), resumed.snapshot()), "resolving saved selection consumes no second fee and draws identical cards")
	_check(resumed.data.qi == spent_qi and resumed.data.phase == "player", "cycle continuation keeps paid qi and returns to player")
	loaded.data.pending.combat = resumed.snapshot()
	_check(loaded.save_game(SAVE).ok, "post-choice state also saves")
	_clean()

func _test_corrupt_card_saves() -> void:
	var state: RefCounted = _fresh()
	var valid: Dictionary = state.data.duplicate(true)
	var corruptions: Array = [
		{"attributes": {}}, {"attributes": {"constitution": 99}}, {"creation": {}},
		{"mastery": -1}, {"mastery": 1.5}, {"aptitude_discount_used": "true"}, {"fortune_hint_used": 1},
		{"learned_cards": ["strike"]}, {"upgraded_cards": ["sword_qi"]}, {"deck": Cards.starting_deck() + ["strike"]},
		{"weapon": "wand"}, {"inner": "shouzhong"}, {"refinements": {"strike": "stable"}}, {"refinements": []},
		{"learned_inners": ["guiyuan", "xingyun"]}, {"mode": "lab"}, {"journey_seed": 0}, {"opportunities": {}}, {"encounter_variants": {}},
		{"trial_history": [{"mode": "flurry", "won": true, "seed": 1, "inner": "guiyuan", "weapon": "sword"}]},
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
	for fields in [{"seed": -1}, {"seed": 1.5}, {"seed": 2147483648}, {"deck": []}, {"attributes": {}}, {"upgraded_cards": ["strike"]}, {"weapon": "unarmed"}, {"inner": "xingyun"}, {"refinements": {"sword_qi": "stable"}}, {"encounter_variant": "counter"}, {"medicine_at_start": 99}, {"fortune_hint": "forged"}, {"combat": {"version": 1}}]:
		var invalid: Dictionary = state.data.duplicate(true)
		for key in fields: invalid.pending[key] = fields[key]
		_reject_save(state, invalid, "malformed locked encounter: " + str(fields))
	var bad_piles: Dictionary = state.data.duplicate(true)
	bad_piles.pending.combat.hand.append("strike")
	_reject_save(state, bad_piles, "snapshot cannot manufacture an extra card")
	_write(JSON.stringify({"version": 1, "data": state.data}))
	var before: Dictionary = state.data.duplicate(true)
	_check(not state.load_game(SAVE).ok and state.data == before, "v1 action-game envelope is not imported into card run")
	_check(Run.SAVE_PATH == "user://run-martial-v3.json" and Run.SAVE_VERSION == 3, "card save namespace remains isolated from existing prototype")
	_check(not state.save_game("user://run-cards-v2.json").ok and not state.save_game("user://run-v1.json").ok, "v3 cannot overwrite canonical previous versions even when explicitly passed")
	var lab: RefCounted = Run.new()
	lab.new_lab()
	for fields in [{"medicine": 2}, {"training": 1}, {"spent": 1}, {"learned_cards": Cards.starting_learned("herbalist")}, {"lab_preset": "missing"}]:
		var invalid: Dictionary = lab.data.duplicate(true)
		for key in fields: invalid[key] = fields[key]
		_reject_save(lab, invalid, "lab baseline/permission cannot be forged: " + str(fields))
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
