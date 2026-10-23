extends SceneTree
const Battle = preload("res://scripts/card_battle.gd")
const Cards = preload("res://scripts/card_catalog.gd")
var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		push_error("FAIL: " + label)

func _stats(seed: int = 42) -> Dictionary:
	return {"attributes": {"constitution": 5, "strength": 5, "agility": 5, "resolve": 5, "aptitude": 5, "fortune": 5}, "origin": "courier", "deck": Cards.starting_deck(), "upgraded_cards": [], "medicine": 2, "seed": seed}

func _battle(mode: String = "exam", seed: int = 42) -> WeiyuanCardBattle:
	var b := Battle.new()
	b.configure(mode, _stats(seed))
	b.skip_mulligan()
	return b

func _fixture(hand: Array, upgraded: bool = false, mode: String = "exam") -> WeiyuanCardBattle:
	var s := _stats()
	var deck := hand.duplicate()
	for id in Cards.BASIC_CARDS:
		for copy in range(2):
			if deck.size() < 10 and deck.count(id) < 2: deck.append(id)
	s.deck = deck
	if upgraded: s.upgraded_cards = hand.duplicate()
	var b := Battle.new()
	b.configure(mode, s)
	b.skip_mulligan()
	b.data.hand = hand.duplicate()
	b.data.draw_pile = deck.duplicate()
	for id in hand: b.data.draw_pile.erase(id)
	return b

func _play(b: WeiyuanCardBattle, id: String, target: int = 0) -> Dictionary:
	return b.play_card(b.data.hand.find(id), target)

func _valid(b: WeiyuanCardBattle) -> bool:
	return Battle.validate_snapshot(JSON.parse_string(JSON.stringify(b.snapshot())), b.data.mode, b.data.stats).ok

func _run() -> void:
	_test_catalog()
	_test_all_cards()
	_test_previews()
	_test_order_and_attributes()
	_test_turns_and_mulligan()
	_test_snapshots()
	_test_real_fights()
	print("TESTS COMPLETE: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)

func _test_catalog() -> void:
	_check(Cards.CARDS.size() == 18, "exact eighteen-card first chapter pool")
	var deck := Cards.starting_deck()
	_check(deck.size() == 10 and Cards.validate_deck(deck, Cards.BASIC_CARDS).ok, "five basic pairs form a legal starting deck")
	for id in Cards.BASIC_CARDS: _check(deck.count(id) == 2, "starting pair " + id)
	for origin in Cards.ORIGIN_CARDS:
		_check(Cards.starting_learned(origin).size() == 6 and Cards.ORIGIN_CARDS[origin] in Cards.starting_learned(origin), "origin learns craft without changing deck: " + origin)
	var bad := deck.duplicate(); bad[0] = "guard"
	_check(not Cards.validate_deck(bad, Cards.CARDS.keys()).ok, "third copy rejected")
	bad = deck.duplicate(); bad[0] = "sword_qi"
	_check(not Cards.validate_deck(bad, Cards.BASIC_CARDS).ok, "unlearned school card rejected")
	_check(not Cards.validate_deck(["strike"], Cards.BASIC_CARDS).ok and Cards.card("missing").is_empty(), "bad deck size and unknown card fail safely")
	for id in Cards.CARDS:
		var card := Cards.card(id)
		_check(card.has("description") and card.description.length() > 0 and card.target in ["enemy", "self", "all_enemies"], "display and targeting metadata: " + id)
		_check(Cards.card(id, true) != card and Cards.card(id, true).id == id, "upgrade changes effect but preserves identity: " + id)
	var independent := Cards.card("strike", true); independent.damage = 999
	_check(Cards.card("strike").damage == 6 and Cards.card("strike", true).damage == 9, "card result edits cannot mutate the shared catalog")
	_check(Cards.cards_for_activity("medicine_lesson") == ["herb_poultice"] and Cards.cards_for_activity("courier_work") == ["courier_dash"] and Cards.cards_for_activity("stage_work") == ["stage_flourish"], "all three crafts have cross-origin activity sources")

func _test_all_cards() -> void:
	# Independently specified resulting values: damage includes strength=5's
	# once-per-card +2; block includes agility=5's first-block +2.
	var outcomes := {
		"strike": [[8,0,2,0,0,0,0,0], [11,0,2,0,0,0,0,0]],
		"guard": [[0,7,2,0,0,0,0,0], [0,10,2,0,0,0,0,0]],
		"breath": [[0,0,4,0,0,0,0,0], [0,0,5,0,0,0,0,0]],
		"observe": [[0,0,2,2,0,0,0,0], [0,0,2,3,0,0,0,0]],
		"feint": [[6,0,2,0,1,0,0,0], [8,0,2,0,2,0,0,0]],
		"sword_qi": [[10,0,1,0,0,0,0,0], [13,0,1,0,0,0,0,0]],
		"steady_guard": [[0,10,2,0,0,0,3,0], [0,13,2,0,0,0,4,0]],
		"opening_thrust": [[9,0,2,0,0,0,0,0], [12,0,2,0,0,0,0,0]],
		"cloud_step": [[0,7,2,1,0,0,0,0], [0,10,2,1,0,0,0,0]],
		"flowing_cut": [[7,0,2,0,0,0,0,0], [10,0,2,0,0,0,0,0]],
		"returning_swallow": [[8,0,2,0,0,0,0,0], [12,0,2,0,0,0,0,0]],
		"herb_poultice": [[0,5,2,0,0,0,0,5], [0,7,2,0,0,0,0,8]],
		"courier_dash": [[0,5,3,1,0,0,0,0], [0,8,3,1,0,0,0,0]],
		"stage_flourish": [[0,0,2,1,0,2,0,0], [0,0,2,2,0,3,0,0]],
		"bridge_oath": [[0,9,2,1,0,0,0,0], [0,12,2,1,0,0,0,0]],
		"letter_focus": [[0,0,3,0,0,0,4,0], [0,0,3,0,0,0,7,0]],
		"old_ballad": [[0,0,3,2,0,0,0,0], [0,0,3,3,0,0,0,0]],
		"mountain_echo": [[14,0,1,0,0,0,0,0], [18,0,1,0,0,0,0,0]],
	}
	for id in outcomes:
		for upgrade in [false, true]:
			var b := _fixture([id], upgrade)
			b.data.hp -= 20
			var hp_before: int = b.data.hp
			var foe_before: int = b.data.enemies[0].hp
			var result := _play(b, id)
			var actual := [foe_before - int(b.data.enemies[0].hp), b.data.block, b.data.qi, b.data.hand.size(), b.data.enemies[0].weak, b.data.enemies[0].vulnerable, b.data.next_attack_bonus, int(b.data.hp) - hp_before]
			_check(result.ok and actual == outcomes[id][1 if upgrade else 0], "%s %s core effects %s" % [id, "upgraded" if upgrade else "base", actual])
			_check(_valid(b), "card leaves valid conserving JSON snapshot: " + id)
	var multi := _fixture(["sword_qi"], false, "grove")
	_play(multi, "sword_qi")
	_check(multi.data.enemies[0].hp == 20 and multi.data.enemies[1].hp == 18, "area card gets strength once across all targets")
	multi = _fixture(["returning_swallow"])
	_play(multi, "returning_swallow")
	_check(multi.data.hits == 2 and multi.data.enemies[0].hp == 88, "two-hit card strength is not doubled")
	var echo := _fixture(["mountain_echo"])
	echo.data.block = 7
	_play(echo, "mountain_echo")
	_check(echo.data.block == 0 and echo.data.enemies[0].hp == 75, "mountain echo spends all block into one attack")

func _test_previews() -> void:
	var b := _fixture(["strike", "cloud_step", "sword_qi"])
	b.data.enemies[0].block = 3
	var before := JSON.stringify(b.snapshot())
	var result := b.preview_card(0)
	_check(result.ok and result.damage == [{"target": 0, "amount": 5, "blocked": 3, "hp_loss": 5}] and "體力" in result.description and "抵擋" in result.description, "preview distinguishes HP loss from prevented damage")
	_check(b.preview_card(1).block == 7 and JSON.stringify(b.snapshot()) == before, "drawing skill preview applies agility without changing hand or RNG")
	b.data.qi = 0
	before = JSON.stringify(b.snapshot())
	_check(b.preview_card(0).ok and not b.preview_card(0).can_play and JSON.stringify(b.snapshot()) == before, "unaffordable card can preview without spending real qi")
	b = _fixture(["sword_qi"], false, "grove")
	result = b.preview_card(0)
	_check(result.damage.size() == 2 and result.damage[0].amount == 10 and result.damage[1].amount == 8, "area preview has actual per-target once-only bonus")
	b.data.enemies[0].hp = 2
	result = b.preview_card(0)
	_check(result.damage[0].amount == 10 and result.damage[0].hp_loss == 2, "overkill preview keeps card damage separate from actual remaining HP loss")
	var opening := Battle.new(); opening.configure("practice", _stats())
	var same := Battle.new(); same.configure("practice", _stats())
	opening.mulligan([]); same.skip_mulligan()
	_check(opening.snapshot() == same.snapshot(), "zero-card exchange equals skip without silently reshuffling future draws")

func _test_order_and_attributes() -> void:
	var right := _fixture(["steady_guard", "opening_thrust"])
	var wrong := _fixture(["steady_guard", "opening_thrust"])
	_play(right, "steady_guard"); _play(right, "opening_thrust")
	_play(wrong, "opening_thrust"); _play(wrong, "steady_guard")
	_check(right.data.enemies[0].hp == 80 and wrong.data.enemies[0].hp == 87, "guard-before-opening order changes damage by seven")
	right = _fixture(["cloud_step", "flowing_cut"])
	wrong = _fixture(["cloud_step", "flowing_cut"])
	_play(right, "cloud_step"); _play(right, "flowing_cut")
	_play(wrong, "flowing_cut"); _play(wrong, "cloud_step")
	_check(right.data.qi == 2 and wrong.data.qi == 1, "skill-before-flowing-cut refunds exactly one energy")
	right = _fixture(["letter_focus", "returning_swallow"])
	_play(right, "letter_focus"); _play(right, "returning_swallow")
	_check(right.data.enemies[0].hp == 84 and right.data.next_attack_bonus == 0, "temporary attack bonus consumed once across two hits")
	right = _fixture(["stage_flourish", "strike"])
	_play(right, "stage_flourish"); _play(right, "strike")
	_check(right.data.enemies[0].hp == 84, "setting vulnerability before strike increases actual damage")
	right = _fixture(["guard", "guard", "strike", "strike"])
	right.data.qi = 4
	_play(right, "guard"); _play(right, "guard"); _play(right, "strike"); _play(right, "strike")
	_check(right.data.block == 12 and right.data.enemies[0].hp == 82, "strength and agility apply only to their first respective card")
	var s := _stats(); s.training = 9999; s.insight = 9999
	var b := Battle.new(); b.configure("practice", s)
	_check(b.data.max_hp == 67 and b.status().mulligan_limit == 2, "root bone and resolve formulas ignore old universal training scaling")
	s.attributes.constitution = 2; s.attributes.resolve = 8
	b.configure("practice", s)
	_check(b.data.max_hp == 58 and b.status().mulligan_limit == 3, "attribute redistribution changes health and opening control")

func _test_turns_and_mulligan() -> void:
	var b := Battle.new(); b.configure("practice", _stats())
	var untouched := JSON.stringify(b.snapshot())
	_check(not b.play_card(0).ok and not b.end_turn().ok and not b.use_medicine().ok, "opening decision blocks normal actions")
	_check(not b.mulligan([0,0]).ok and not b.mulligan([0,1,2]).ok and not b.mulligan([9]).ok and JSON.stringify(b.snapshot()) == untouched, "invalid mulligans are atomic")
	var original_hand: Array = b.data.hand.duplicate()
	var original_draw: Array = b.data.draw_pile.duplicate()
	_check(b.mulligan([0,2]).ok and b.data.hand.size() == 5 and b.data.draw_pile.size() == 5 and _valid(b), "legal opening exchange conserves all ten cards")
	_check(b.data.hand.slice(3).all(func(id): return id in original_draw), "replacement cards come from original draw pile before returns")
	_check(not b.mulligan([0]).ok and not b.skip_mulligan().ok, "opening exchange cannot be repeated")
	b = _fixture(["guard", "breath", "observe"], false, "practice")
	_play(b,"guard"); _play(b,"breath")
	_check(b.data.exhaust_pile == ["breath"] and b.data.qi == 3, "breath leaves circulation and supplies energy")
	b.end_turn()
	_check(b.data.turn == 2 and b.data.block == 0 and b.data.hp == b.data.max_hp and b.data.qi == 3 and b.data.hand.size() == 5, "enemy attack consumes block; new turn clears block and resets qi/hand")
	_check(not b.data.first_attack_used and not b.data.first_block_used and _valid(b), "new turn refreshes bonuses and preserves deck")
	b = _fixture(["breath", "breath"], false, "practice")
	_play(b,"breath"); _play(b,"breath")
	_check(b.data.qi == 5 and b.data.exhaust_pile.size() == 2, "both breathing cards supply temporary surplus qi")
	b.end_turn()
	_check(b.data.qi == 3 and _valid(b), "unused surplus qi cannot carry over to next turn")
	b = _fixture(["feint"], false, "practice")
	_play(b,"feint")
	_check(b.data.enemies[0].intent.display_damage == 3, "public intention shows actual weakened damage")
	b.end_turn()
	_check(b.data.hp == 64 and b.data.enemies[0].weak == 0, "weakness affects enemy turn before expiring")
	b.data.hp = 20
	_check(b.use_medicine().ok and b.data.hp == 40 and b.report().medicine_used == 1, "medicine restores twenty and reports usage")
	_check(not b.use_medicine().ok, "medicine limited to once per player turn")
	b.end_turn()
	_check(b.use_medicine().ok and b.status().medicine_left == 0, "medicine becomes available next turn without restoring stock")
	b = _fixture(["observe"], false, "exam")
	# The played draw card is deliberately the only card outside the hand.
	b.data.hand = b.data.stats.deck.duplicate()
	b.data.draw_pile.clear()
	var index: int = b.data.hand.find("observe")
	b.play_card(index)
	_check(b.data.hand.size() == 9 and b.data.discard_pile == ["observe"], "drawing cannot recycle the card currently resolving")
	_check(_valid(b), "empty draw/discard still conserves resolving card")
	var before := JSON.stringify(b.snapshot())
	_check(not b.play_card(-1).ok and not b.play_card(999).ok and JSON.stringify(b.snapshot()) == before, "invalid hand indices do not mutate state")
	b = _fixture(["strike"])
	b.data.qi = 0; before = JSON.stringify(b.snapshot())
	_check(not b.play_card(0).ok and JSON.stringify(b.snapshot()) == before, "insufficient qi is atomic")
	b.data.qi = 3; before = JSON.stringify(b.snapshot())
	_check(not b.play_card(0,99).ok and JSON.stringify(b.snapshot()) == before, "invalid target is atomic")

func _test_snapshots() -> void:
	var original := _battle("ridge", 2147483646)
	for action in range(5): _bot_step(original)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(original.snapshot()))
	_check(Battle.validate_snapshot(saved,"ridge", original.data.stats).ok, "JSON snapshot validates fixed seed and battle state")
	var resumed := Battle.new()
	_check(resumed.configure("ridge", original.data.stats, saved).ok and resumed.snapshot() == original.snapshot(), "JSON reload normalizes integers into identical state")
	for action in range(200):
		if original.status().resolved: break
		_bot_step(original); _bot_step(resumed)
		_check(original.snapshot() == resumed.snapshot(), "reloaded future actions and shuffles remain exact: %d" % action)
	_check(original.report() == resumed.report(), "reloaded battle settles identical report")
	var retry := Battle.new(); retry.configure("ridge", original.data.stats)
	var fresh := Battle.new(); fresh.configure("ridge", original.data.stats)
	_check(retry.snapshot() == fresh.snapshot() and retry.data.turn == 1 and retry.data.medicine_used == 0, "retry reconstructs original seed/deck without retained damage or medicine use")
	var detached := fresh.status(); detached.hand.clear(); detached.stats.attributes.strength = 99
	_check(fresh.data.hand.size() == 5 and fresh.data.stats.attributes.strength == 5, "read-only status is a deep copy of cards and fixed stats")
	var opening: Dictionary = fresh.snapshot()
	opening._view = {"selected_hand": 1}
	_check(Battle.validate_snapshot(opening).ok, "optional view snapshot accepted")
	var corruptions: Array = []
	for field in ["rng_state", "seed", "hp", "qi", "turn"]:
		var bad: Dictionary = saved.duplicate(true); bad[field] = -1; corruptions.append(bad)
	var bad: Dictionary = saved.duplicate(true); bad.rng_state = 1.5; corruptions.append(bad)
	bad = saved.duplicate(true); bad.rng_state = 2147483648; corruptions.append(bad)
	bad = saved.duplicate(true); bad.hand.append("strike"); corruptions.append(bad)
	bad = saved.duplicate(true); bad.hand[0] = "missing"; corruptions.append(bad)
	bad = saved.duplicate(true); bad.phase = "won"; corruptions.append(bad)
	bad = saved.duplicate(true); bad.enemies[0].intent.damage += 50; corruptions.append(bad)
	bad = saved.duplicate(true); bad.medicine_used = 999; corruptions.append(bad)
	bad = saved.duplicate(true); bad.erase("first_attack_used"); corruptions.append(bad)
	bad = saved.duplicate(true); bad.rng_state = "123"; corruptions.append(bad)
	bad = saved.duplicate(true); bad.medicine_used = 0; bad.medicine_used_this_turn = true; corruptions.append(bad)
	bad = saved.duplicate(true); bad.last_events = [{"kind": "bad", "amount": NAN}]; corruptions.append(bad)
	var stable := JSON.stringify(fresh.snapshot())
	for index in range(corruptions.size()):
		_check(not fresh.configure("ridge", original.data.stats, corruptions[index]).ok and JSON.stringify(fresh.snapshot()) == stable, "bad snapshot rejected without fresh battle or mutation: %d" % index)
	var other: Dictionary = original.data.stats.duplicate(true); other.seed += 1
	_check(not Battle.validate_snapshot(saved,"ridge",other).ok, "snapshot cannot cross pending encounter seeds")
	other = original.data.stats.duplicate(true); other.upgraded_cards = ["strike"]
	_check(not Battle.validate_snapshot(saved,"ridge",other).ok, "snapshot cannot alter locked upgrades")
	_check(not Battle.validate_snapshot(saved,"exam",original.data.stats).ok, "snapshot cannot cross encounter modes")

func _bot_step(b: WeiyuanCardBattle) -> void:
	if b.data.phase == "mulligan": b.skip_mulligan(); return
	if b.status().resolved: return
	if b.status().can_use_medicine and b.data.hp <= b.data.max_hp - 20: b.use_medicine(); return
	var target := -1
	var incoming := 0
	for i in range(b.data.enemies.size()):
		var e: Dictionary = b.data.enemies[i]
		if e.hp <= 0: continue
		if target == -1 or e.hp < b.data.enemies[target].hp: target = i
		incoming += int(e.intent.get("display_damage", e.intent.damage)) * int(e.intent.hits)
	var choice := -1
	var best := -1000
	for i in range(b.data.hand.size()):
		var id: String = b.data.hand[i]
		var c := Cards.card(id, id in b.data.stats.upgraded_cards)
		if c.cost > b.data.qi: continue
		var score: int = 0
		if c.has("damage"): score = 40 + int(c.damage) * int(c.get("hits",1))
		if c.has("weak") and b.data.enemies[target].weak == 0 and incoming > b.data.block: score += 20
		if c.has("block") and incoming > b.data.block: score += 60
		if c.has("draw") and b.data.qi > c.cost: score += 15
		if c.has("energy"): score += 100
		if c.has("next_attack") and b.data.hand.any(func(card_id): return Cards.card(card_id).type == "attack"): score += 90
		if c.has("vulnerable") and b.data.hand.any(func(card_id): return Cards.card(card_id).type == "attack"): score += 85
		if score > best: best = score; choice = i
	if choice >= 0: b.play_card(choice,target)
	else: b.end_turn()

func _test_real_fights() -> void:
	for mode in ["practice","spar","grove","ridge","exam"]:
		for seed in [1,42,2026]:
			var b := _battle(mode, seed)
			var shuffles := 0
			for action in range(400):
				if b.status().resolved: break
				_bot_step(b)
				for event in b.data.last_events:
					if event.kind == "shuffle": shuffles += 1
				_check(_valid(b), "%s seed%d valid after action%d" % [mode,seed,action])
			_check(b.data.phase == "won", "%s seed%d is winnable with basic deck and public intentions (hp%d turn%d)" % [mode,seed,b.data.hp,b.data.turn])
			if mode in ["ridge","exam"]: _check(shuffles > 0, "long encounter exercises real conserving reshuffles")
			var settled := JSON.stringify(b.snapshot())
			_check(not b.play_card(0).ok and not b.end_turn().ok and not b.use_medicine().ok and JSON.stringify(b.snapshot()) == settled, "resolved battle cannot act or settle twice")
			var restored := Battle.new()
			_check(restored.configure(mode,b.data.stats,JSON.parse_string(settled)).ok and restored.report() == b.report(), "terminal snapshot restores without redoing rewards")
