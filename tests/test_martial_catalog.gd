extends SceneTree

const Cards = preload("res://scripts/card_catalog.gd")
var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		push_error("FAIL: " + label)

func _run() -> void:
	_test_exact_effects()
	_test_refinements()
	_test_loadouts_and_sources()
	_test_isolation_and_invalid_inputs()
	print("TESTS COMPLETE: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _test_exact_effects() -> void:
	# Independent approved-plan values; these are not derived from catalogue data.
	var expected: Dictionary = {
		"strike": {"cost": 1, "type": "attack", "weapon": "sword", "damage": 6},
		"guard": {"cost": 1, "type": "guard", "weapon": "any", "block": 5},
		"breath": {"cost": 0, "type": "change", "weapon": "any", "energy": 1, "exhaust": true},
		"observe": {"cost": 1, "type": "change", "weapon": "any", "draw": 2},
		"cloud_step": {"cost": 1, "type": "change", "weapon": "any", "block": 3, "cycle_limit": 1},
		"opening_thrust": {"cost": 1, "type": "attack", "weapon": "sword", "damage": 4, "guard_bonus": 4},
		"sword_qi": {"cost": 2, "type": "attack", "weapon": "sword", "damage": 10},
		"pushing_palm": {"cost": 1, "type": "attack", "weapon": "any", "strip_block": 6, "damage": 4},
		"yielding_palm": {"cost": 1, "type": "guard", "weapon": "any", "block": 4},
		"probing_stone": {"cost": 0, "type": "change", "weapon": "any", "strip_block": 2},
		"hidden_needle": {"cost": 1, "type": "change", "weapon": "any", "delayed_damage": 7},
		"gather_momentum": {"cost": 1, "type": "change", "weapon": "any", "momentum_gain": 1},
	}
	var boosted: Dictionary = {
		"opening_thrust": {"momentum_cost": 1, "damage": 8, "guard_bonus": 4},
		"sword_qi": {"momentum_cost": 3, "damage": 22},
		"yielding_palm": {"momentum_cost": 1, "block": 4, "retaliation": 6},
		"probing_stone": {"momentum_cost": 1, "strip_block": 2, "draw": 1},
		"hidden_needle": {"momentum_cost": 1, "delayed_damage": 11},
	}
	_check(Cards.CARDS.size() == expected.size(), "exact twelve-card verification pool")
	for id in expected:
		var card: Dictionary = Cards.card(id)
		for key in expected[id]:
			_check(card.get(key) == expected[id][key], "%s approved %s" % [id, key])
		_check(card.id == id and card.momentum_cost == 0 and not card.empowered and not card.upgraded, "ordinary mode is free of momentum and refinements: " + id)
		_check(card.description == card.normal_description and not str(card.description).is_empty(), "ordinary text exists and uses normal mode: " + id)
		_check(Cards.TYPE_LABELS.has(card.type) and Cards.DISCIPLINES.has(card.discipline), "route and discipline are known: " + id)
		var needs_enemy: bool = id in ["strike", "opening_thrust", "sword_qi", "pushing_palm", "probing_stone", "hidden_needle"]
		_check(card.target == ("enemy" if needs_enemy else "self"), "actual target contract: " + id)
		_check(card.boost_available == boosted.has(id), "only authored moves offer empowerment: " + id)
		if boosted.has(id):
			var strong: Dictionary = Cards.card(id, "", true)
			for key in boosted[id]:
				_check(strong.get(key) == boosted[id][key], "%s empowered %s" % [id, key])
			_check(strong.cost == card.cost and strong.empowered and strong.boost_cost == strong.momentum_cost, "empowerment keeps qi cost and declares exact momentum: " + id)
			_check(strong.description == strong.boost_description and strong.description.contains("消耗 %d 勢" % strong.momentum_cost), "empowered wording declares real cost: " + id)
		else:
			_check(Cards.card(id, "", true).is_empty(), "unauthored empowerment is refused: " + id)
	_check(not Cards.card("sword_qi").get("all", false), "new sword qi is explicitly a single-target finisher")
	_check(Cards.card("cloud_step").description.contains("其他手牌"), "cycle text excludes the card currently being played")
	_check(Cards.card("hidden_needle", "", true).description.contains("目標已死則取消"), "delayed effect text states cancelled dead target")
	_check(Cards.card("yielding_palm", "", true).description.contains("不累加"), "counter preparation is non-stacking in visible text")

func _test_refinements() -> void:
	_check(Cards.REFINABLE == ["opening_thrust", "cloud_step", "sword_qi"], "only three representative techniques refine")
	var steady: Dictionary = Cards.card("opening_thrust", "stable")
	var focused: Dictionary = Cards.card("opening_thrust", "specialist", true)
	_check(steady.damage == 6 and steady.guard_bonus == 2 and steady.boost_cost == 1, "steady sword trades conditional bonus for base damage")
	_check(Cards.card("opening_thrust", "stable", true).damage == 10, "steady sword retains approved +4 empowerment")
	_check(focused.damage == 13 and focused.guard_bonus == 4 and focused.momentum_cost == 2, "focused sword pays two momentum for nine extra damage")
	_check(Cards.card("opening_thrust", "specialist").damage == 4, "focused sword never leaks empowered damage into ordinary mode")
	steady = Cards.card("cloud_step", "stable")
	focused = Cards.card("cloud_step", "specialist")
	_check(steady.block == 5 and steady.cycle_limit == 1, "steady footwork boosts guard only")
	_check(focused.block == 3 and focused.cycle_limit == 2, "focused footwork improves exchange rather than free drawing")
	steady = Cards.card("sword_qi", "stable")
	focused = Cards.card("sword_qi", "specialist")
	var strong: Dictionary = Cards.card("sword_qi", "specialist", true)
	_check(steady.cost == 1 and steady.damage == 7 and Cards.card("sword_qi", "stable", true).damage == 19, "steady finisher trades base force for lower qi cost")
	_check(focused.cost == 2 and focused.damage == 10 and not focused.has("strip_block"), "focused finisher never strips guard in ordinary mode")
	_check(strong.cost == 2 and strong.damage == 22 and strong.strip_block == 8 and strong.momentum_cost == 3, "focused finisher strips eight only when empowered")
	_check(strong.description.find("移除") < strong.description.find("造成"), "finisher text communicates armor removal before damage")
	for id in Cards.REFINABLE:
		for branch in ["stable", "specialist"]:
			var refined: Dictionary = Cards.card(id, branch)
			_check(refined.refinement == branch and refined.upgraded and refined.id == id, "refinement preserves technique identity: " + id + "/" + branch)
			_check(not Cards.refinement_description(id, branch).is_empty(), "each refinement exposes complete comparison text")
		_check(Cards.card(id, true) == Cards.card(id, "stable"), "legacy true safely maps to stable for refinable techniques")

func _test_loadouts_and_sources() -> void:
	_check(Cards.INNERS.keys() == ["shouzhong", "xingyun", "guiyuan"], "exact three active inners")
	_check(Cards.WEAPONS.keys() == ["sword", "saber", "polearm", "unarmed"], "all approved equipment choices exist")
	for inner in Cards.INNERS:
		_check(not str(Cards.INNERS[inner].gain_description).is_empty() and not str(Cards.INNERS[inner].spend_description).is_empty(), "inner explains both economy and payoff: " + inner)
	var sources: Dictionary = {
		"sword_lesson": ["sword_qi", "opening_thrust"],
		"practice": ["pushing_palm"], "spar": ["yielding_palm"],
		"ridge_tracks": ["cloud_step"], "hermit_visit": ["hidden_needle"],
	}
	for activity in sources:
		_check(Cards.cards_for_activity(activity) == sources[activity], "guaranteed story source: " + activity)
	_check(Cards.inners_for_activity("sword_lesson") == ["shouzhong"] and Cards.inners_for_activity("ridge_tracks") == ["xingyun"], "school inners have guaranteed sources")
	_check(Cards.cards_for_activity("missing").is_empty() and Cards.inners_for_activity("missing").is_empty(), "unknown events cannot grant techniques")
	var learned: Array = Cards.starting_learned("herbalist")
	_check(learned == ["strike", "guard", "breath", "observe", "probing_stone", "gather_momentum"], "starting knowledge is explicit and contains spendable momentum technique")
	for origin in ["herbalist", "courier", "performer"]:
		_check(Cards.starting_learned(origin) == learned, "origin does not gate core techniques: " + origin)
	_check(Cards.validate_deck(Cards.starting_deck(), learned).ok, "starting sword deck is valid")
	for id in Cards.BASIC_CARDS:
		_check(Cards.starting_deck().count(id) == 2, "starting pair: " + id)
	var all: Array = Cards.CARDS.keys()
	for preset in Cards.PRESETS:
		var data: Dictionary = Cards.PRESETS[preset]
		_check(Cards.validate_deck(data.deck, all, data.weapon).ok and Cards.INNERS.has(data.inner), "preset is a legal complete build: " + preset)
		_check(data.deck.size() == 10, "preset contains ten cards: " + preset)
		for id in data.deck:
			_check(data.deck.count(id) <= 2, "preset respects copy cap: " + preset + "/" + id)
	_check(Cards.PRESETS.shouzhong.deck == ["strike", "strike", "guard", "guard", "opening_thrust", "opening_thrust", "yielding_palm", "yielding_palm", "pushing_palm", "gather_momentum"], "shouzhong preset matches approved plan")
	_check(Cards.PRESETS.xingyun.deck == ["guard", "breath", "observe", "cloud_step", "cloud_step", "pushing_palm", "pushing_palm", "probing_stone", "probing_stone", "hidden_needle"], "xingyun preset matches approved plan")
	_check(Cards.PRESETS.guiyuan.deck == ["strike", "strike", "guard", "guard", "breath", "observe", "sword_qi", "sword_qi", "gather_momentum", "gather_momentum"], "guiyuan preset matches approved plan")
	for weapon in Cards.WEAPONS:
		_check(Cards.validate_deck(Cards.PRESETS.xingyun.deck, all, weapon).ok, "general arts work with every weapon: " + weapon)
		if weapon != "sword":
			_check(not Cards.validate_deck(Cards.PRESETS.shouzhong.deck, all, weapon).ok, "sword-only moves require sword: " + weapon)
	var accessible: Array = learned.duplicate()
	for activity in sources:
		for id in Cards.cards_for_activity(activity):
			if id not in accessible: accessible.append(id)
	_check(accessible.size() == 12, "all twelve techniques have non-random acquisition routes")

func _test_isolation_and_invalid_inputs() -> void:
	var changed: Dictionary = Cards.card("sword_qi", "specialist", true)
	changed.damage = 999
	changed.boost.damage_bonus = 900
	_check(Cards.card("sword_qi", "specialist", true).damage == 22 and Cards.CARDS.sword_qi.boost.damage_bonus == 12, "nested caller mutations cannot change source effects")
	var starting: Array = Cards.starting_deck()
	starting.clear()
	_check(Cards.starting_deck().size() == 10, "starting deck is an owned copy")
	var grants: Array = Cards.cards_for_activity("sword_lesson")
	grants.clear()
	_check(Cards.cards_for_activity("sword_lesson").size() == 2, "event grants are owned copies")
	var inner_grants: Array = Cards.inners_for_activity("ridge_tracks")
	inner_grants.append("guiyuan")
	_check(Cards.inners_for_activity("ridge_tracks") == ["xingyun"], "inner grants are owned copies")
	_check(Cards.card("unknown").is_empty(), "unknown technique rejected")
	_check(Cards.card("sword_qi", "invalid").is_empty() and Cards.card("strike", "stable").is_empty(), "unknown or unsupported refinement rejected")
	_check(Cards.card("sword_qi", 2).is_empty() and Cards.card("strike", true) == Cards.card("strike"), "typed refinement validation with harmless legacy bool compatibility")
	_check(Cards.refinement_description("unknown", "stable").is_empty(), "unknown refinement has no fabricated text")
	var all: Array = Cards.CARDS.keys()
	var bad: Array = Cards.starting_deck()
	bad[0] = "guard"
	_check(not Cards.validate_deck(bad, all).ok, "third copy is rejected")
	bad = Cards.starting_deck()
	bad[0] = "sword_qi"
	_check(not Cards.validate_deck(bad, Cards.BASIC_CARDS).ok, "unlearned techniques are rejected")
	bad[0] = "invalid"
	_check(not Cards.validate_deck(bad, all).ok, "unknown card is rejected")
	bad[0] = 1
	_check(not Cards.validate_deck(bad, all).ok, "non-string card is rejected")
	_check(not Cards.validate_deck([], all).ok and not Cards.validate_deck("deck", all).ok and not Cards.validate_deck(Cards.starting_deck(), {}).ok, "malformed deck and knowledge containers rejected")
	_check(not Cards.validate_deck(Cards.starting_deck(), all, "bow").ok, "unsupported equipment rejected")
