extends SceneTree
## Exhaustive point-budget and authored-branch checks; persistence/UI integration lives in card_run/card_ui.
const Creation = preload("res://scripts/character_creation.gd")
var passed = 0
var failed = 0

func _initialize() -> void:
	call_deferred("_run")

func expect(ok: bool, message: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		push_error("FAIL CREATION: " + message)

func _sum(values: Dictionary) -> int:
	var total = 0
	for value in values.values(): total += int(value)
	return total

func _complete(answers: Array) -> Dictionary:
	var state = Creation.draft()
	for index in range(6):
		var result = Creation.with_answer(state, index, int(answers[index]))
		if not result.ok:
			expect(false, "valid ordered answer cannot fail")
			return {}
		state = result.creation
	return state

func _run() -> void:
	_test_all_routes()
	_test_adjustments()
	_test_rejections_and_persistence()
	_test_story_and_disclosure()
	print("TESTS COMPLETE: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_all_routes() -> void:
	var appearances: Dictionary = {}
	for key in Creation.ATTRIBUTE_KEYS: appearances[key] = 0
	for question in Creation.QUESTIONS:
		var seen: Dictionary = {}
		expect(question.choices.size() == 3, "every scene has three understandable alternatives")
		for choice in question.choices:
			seen[choice.attribute] = true
			appearances[choice.attribute] += 1
		expect(seen.size() == 3, "a scene offers three different tendencies")
	for key in appearances: expect(appearances[key] == 3, key + " occurs in exactly three questions")
	var distinct: Dictionary = {}
	for encoded in range(729):
		var remainder = encoded
		var answers: Array = []
		for index in range(6):
			answers.append(remainder % 3)
			remainder = int(remainder / 3)
		var state = _complete(answers)
		var values = Creation.final_attributes(state)
		var legal = Creation.validate(state, true).ok and _sum(values) == 30
		for key in Creation.ATTRIBUTE_KEYS: legal = legal and int(values[key]) >= 4 and int(values[key]) <= 7
		expect(legal, "all 729 answer paths preserve total thirty and range four to seven: " + str(encoded))
		distinct[JSON.stringify(values)] = true
		expect(Creation.summary(state).answer_rows.size() == 6, "every valid route discloses all six sources")
	expect(distinct.size() > 30, "different answers offer substantively different starting builds")
	var fresh = Creation.draft()
	expect(Creation.validate(fresh).ok and not Creation.validate(fresh, true).ok and _sum(Creation.final_attributes(fresh)) == 24, "unanswered draft can save but cannot confirm")
	for index in range(6):
		fresh = Creation.with_answer(fresh, index, index % 3).creation
		expect(_sum(Creation.final_attributes(fresh)) == 25 + index, "partial route grants one point per answer")

func _test_adjustments() -> void:
	var original = _complete([0, 0, 0, 0, 0, 0])
	var snapshot = original.duplicate(true)
	var first = Creation.move_point(original, "fortune", "strength")
	expect(first.ok and original == snapshot, "successful transfer is pure and preserves caller's state")
	expect(Creation.final_attributes(first.creation).strength == 8, "seven-point answer tendency may reach eight")
	expect(not Creation.move_point(first.creation, "fortune", "strength").ok, "maximum eight cannot be exceeded even with allowance left")
	var second = Creation.move_point(first.creation, "fortune", "resolve")
	expect(second.ok and Creation.final_attributes(second.creation).fortune == 2 and _sum(Creation.final_attributes(second.creation)) == 30, "second transfer can reach two while preserving thirty")
	expect(not Creation.move_point(second.creation, "constitution", "resolve").ok, "third point transfer rejected")
	var reverse = Creation.move_point(first.creation, "strength", "fortune")
	expect(reverse.ok and Creation.summary(reverse.creation).moves_used == 2 and not Creation.move_point(reverse.creation, "fortune", "strength").ok, "reversing a move still uses the second allowance")
	var reset = Creation.reset_adjustments(second.creation)
	expect(reset.ok and Creation.final_attributes(reset.creation) == Creation.final_attributes(original) and reset.creation.adjustments.is_empty(), "reset returns exactly to answer-derived build")
	second.creation.move_source = "constitution"
	var edited = Creation.with_answer(second.creation, 0, 1)
	expect(edited.ok and edited.creation.adjustments.is_empty() and edited.creation.move_source == "", "re-answering clears transfers and unfinished transfer selection")
	expect(Creation.final_attributes(edited.creation) == Creation.final_attributes(_complete([1, 0, 0, 0, 0, 0])), "re-answer recomputes instead of accumulating previous answer bonuses")
	for invalid in [["strength", "strength"], ["unknown", "fortune"], ["strength", "unknown"]]:
		expect(not Creation.move_point(original, invalid[0], invalid[1]).ok and original == snapshot, "invalid transfer is atomic")
	expect(not Creation.move_point(Creation.draft(), "strength", "fortune").ok, "unfinished route cannot move points")

func _test_rejections_and_persistence() -> void:
	var fresh = Creation.draft()
	for pair in [[-1, 0], [6, 0], [0, -1], [0, 3], [2, 0]]:
		expect(not Creation.with_answer(fresh, pair[0], pair[1]).ok and fresh == Creation.draft(), "invalid or skipped question cannot change draft")
	var invalids: Array = []
	for field_value in [["version", 2], ["answers", [0, -1, 1, -1, -1, -1]], ["answers", [true, -1, -1, -1, -1, -1]], ["answers", [0.5, -1, -1, -1, -1, -1]], ["answers", [3, -1, -1, -1, -1, -1]], ["answers", []], ["page", "summary"], ["page", "aftermath"], ["page", "missing"], ["question", 1], ["question", 0.5], ["review_return", true], ["review_return", "true"], ["move_source", "unknown"], ["adjustments", [{"from": "strength", "to": "resolve"}]]]:
		var broken = fresh.duplicate(true)
		broken[field_value[0]] = field_value[1]
		invalids.append(broken)
	for state in invalids: expect(not Creation.validate(state).ok and Creation.final_attributes(state).is_empty(), "malformed draft rejected before calculating attributes")
	var completed = Creation.default_completed()
	for page in ["question", "aftermath", "summary", "review"]:
		var source = completed.duplicate(true)
		source.page = page
		source.question = 2
		source.review_return = page in ["question", "aftermath"]
		source.move_source = "constitution" if page == "summary" else ""
		var decoded: Dictionary = JSON.parse_string(JSON.stringify(source))
		expect(Creation.validate(decoded, true).ok and Creation.final_attributes(decoded) == Creation.final_attributes(source), "JSON numeric conversion preserves " + page + " page and ability calculations")
		expect(decoded.page == source.page and decoded.move_source == source.move_source and decoded.question == source.question, "saved exact page and transfer-selection position survives " + page)
	var overflow = completed.duplicate(true)
	overflow.adjustments = [{"from": "fortune", "to": "strength"}, {"from": "fortune", "to": "strength"}]
	expect(not Creation.validate(overflow).ok, "tampered adjustments cannot raise a stat above eight")

func _test_story_and_disclosure() -> void:
	var intros: Dictionary = {}
	var greetings: Dictionary = {}
	var closings: Dictionary = {}
	var state = Creation.default_completed()
	for origin in ["herbalist", "courier", "performer"]:
		intros[Creation.scene(state, 0, origin, "小溪").body] = true
		greetings[Creation.scene(state, 5, origin, "小溪").body] = true
		closings[Creation.response(state, 5, origin, "小溪").body] = true
		expect(Creation.scene(state, 0, origin, "小溪").speaker == "小溪", "custom name participates in departure scene")
	expect(intros.size() == 3 and greetings.size() == 3 and closings.size() == 3, "three origins have distinct departure and familiar-person responses")
	var motives: Dictionary = {}
	for choice in range(3):
		var chosen = _complete([choice, choice, choice, choice, choice, choice])
		var info = Creation.summary(chosen)
		motives[info.motivation.id] = true
		expect(info.echoes.size() == 6 and info.choice_echoes.size() == 3, "authored decisions leave complete motivation and road-memory records")
		for index in range(6):
			var response = Creation.response(chosen, index, "herbalist", "小溪")
			expect(str(response.body).length() > 150, "every choice has a substantive consequence scene")
		expect(info.answer_rows[0].effect.contains("+1") and not Creation.scene(chosen, 0, "herbalist", "小溪").body.contains("+1"), "point sources are disclosed at review instead of pre-answer prose")
	expect(motives.size() == 3, "three departure motives remain identifiable")
	for index in [3, 4]:
		var followups: Dictionary = {}
		for choice in range(3):
			var selected = [0, 0, 0, 0, 0, 0]
			selected[index - 1] = choice
			followups[Creation.scene(_complete(selected), index, "courier", "小溪").body] = true
		expect(followups.size() == 3, "successive cart scene remembers previous action: " + str(index))
	expect(Creation.effect_text("constitution", 6).contains("70"), "constitution disclosure matches actual maximum health")
	expect(Creation.effect_text("strength", 7).contains("+3") and Creation.effect_text("strength", 7).contains("整張只加一次"), "strength disclosure explains integer and whole-card bonus")
	expect(Creation.effect_text("agility", 5).contains("+2"), "agility disclosure matches first guard bonus")
	expect(Creation.effect_text("resolve", 6).contains("3 張"), "resolve disclosure matches opening mulligan cap")
	expect(Creation.effect_text("aptitude", 6).contains("只需 1 點") and Creation.effect_text("aptitude", 5).contains("需 2 點"), "aptitude threshold and normal mastery cost disclosed")
	expect(Creation.effect_text("fortune", 6).contains("仍須親自調查") and Creation.effect_text("fortune", 5).contains("同樣能取得"), "fortune clue is convenience and never a content lock")
	expect(Creation.card_advice(state).contains("各兩張") and Creation.card_advice(state).contains("意圖"), "summary provides actual starter deck and first-turn advice")
