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

func _stats(seed: int = 42, preset: String = "guiyuan") -> Dictionary:
	var p: Dictionary = Cards.PRESETS[preset]
	return {"attributes": {"constitution": 5, "strength": 5, "agility": 5, "resolve": 5, "aptitude": 5, "fortune": 5},
		"origin": "courier", "deck": p.deck.duplicate(), "refinements": {}, "weapon": p.weapon,
		"inner": p.inner, "upgraded_cards": [], "medicine": 1, "seed": seed}

func _battle(mode: String = "exam", seed: int = 42, preset: String = "guiyuan") -> WeiyuanCardBattle:
	var b := Battle.new()
	_check(b.configure(mode, _stats(seed, preset)).ok, "encounter starts: " + mode + "/" + preset)
	b.skip_mulligan()
	return b

# Fixtures rearrange known card zones to isolate a rule. Only the final matrix
# exercises real shuffled draws and untouched enemy HP for full legal wins.
func _fixture(hand: Array, inner: String = "guiyuan", mode: String = "exam", refinements: Dictionary = {}) -> WeiyuanCardBattle:
	var s := _stats()
	s.inner = inner
	s.weapon = "sword"
	s.refinements = refinements
	s.upgraded_cards = refinements.keys()
	var deck := hand.duplicate()
	for id in Cards.CARDS:
		# A unique footwork copy lets the cycle test distinguish the executing
		# card from a second, legally drawn copy with the same name.
		if id == "cloud_step" and id in hand: continue
		for copy in range(2):
			if deck.size() < 10 and deck.count(id) < 2: deck.append(id)
	s.deck = deck
	var b := Battle.new()
	_check(b.configure(mode, s).ok, "isolated legal deck fixture starts")
	b.skip_mulligan()
	b.data.hand = hand.duplicate()
	b.data.draw_pile = deck.duplicate()
	for id in hand: b.data.draw_pile.erase(id)
	return b

func _momentum(b: WeiyuanCardBattle, amount: int) -> void:
	b.data.momentum = amount
	b.data.momentum_generated = amount

func _play(b: WeiyuanCardBattle, id: String, boost: bool = false, target: int = 0) -> Dictionary:
	return b.play_card(b.data.hand.find(id), target, boost)

func _valid(b: WeiyuanCardBattle) -> bool:
	var checked: Dictionary = Battle.validate_snapshot(JSON.parse_string(JSON.stringify(b.snapshot())), b.data.mode, b.data.stats)
	if not checked.ok: print("SNAPSHOT REJECTED: ", checked.message)
	return checked.ok

func _run() -> void:
	_test_payment_and_cards()
	_test_inners()
	_test_choices_and_retention()
	_test_reaction_order()
	_test_locked_intentions()
	_test_snapshots_and_previews()
	_test_legal_fights()
	_test_distinct_character_profiles()
	print("TESTS COMPLETE: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)

func _test_payment_and_cards() -> void:
	var b := _fixture(["opening_thrust", "gather_momentum", "guard"])
	var original := b.snapshot()
	_check(not _play(b, "opening_thrust", true).ok and b.snapshot() == original, "cannot borrow future momentum or mutate on unpaid boost")
	_check(_play(b, "gather_momentum").ok and b.data.momentum == 1 and b.data.qi == 2, "gather spends qi before gaining one momentum")
	_check(_play(b, "guard").ok and b.data.block == 7, "first card block adds agility once")
	var before := int(b.data.enemies[0].hp)
	_check(_play(b, "opening_thrust", true).ok and before - b.data.enemies[0].hp == 14, "opening thrust uses existing guard plus strength and explicit boost once")
	_check(b.data.momentum == 0 and b.data.qi == 0 and b.data.boosts_used == 1 and _valid(b), "payment and exact snapshot remain valid")
	for branch in ["", "stable", "specialist"]:
		b = _fixture(["opening_thrust", "guard"], "guiyuan", "exam", {} if branch == "" else {"opening_thrust": branch})
		_momentum(b, 3)
		_play(b, "guard")
		before = b.data.enemies[0].hp
		_play(b, "opening_thrust", true)
		_check(before - b.data.enemies[0].hp == (19 if branch == "specialist" else 14), "opening branch has exact total damage: " + branch)
		_check(b.data.momentum == (1 if branch == "specialist" else 2), "opening branch pays exact momentum: " + branch)
	for branch in ["", "stable", "specialist"]:
		b = _fixture(["sword_qi"], "guiyuan", "exam", {} if branch == "" else {"sword_qi": branch})
		_momentum(b, 3)
		b.data.enemies[0].block = 8
		before = b.data.enemies[0].hp
		_play(b, "sword_qi", true)
		_check(before - b.data.enemies[0].hp == {"": 24, "stable": 21, "specialist": 32}[branch], "guiyuan bonus and sword refinement resolve once: " + branch)
		_check(b.data.qi == (2 if branch == "stable" else 1), "sword refinement qi is correct")
	b = _fixture(["pushing_palm", "probing_stone"])
	b.data.enemies[0].block = 9
	_play(b, "probing_stone")
	_check(b.data.enemies[0].block == 7 and b.data.qi == 3 and not b.data.first_attack_used, "zero-cost stone strips guard without becoming an attack")
	before = b.data.enemies[0].hp
	_play(b, "pushing_palm")
	_check(b.data.enemies[0].block == 0 and before - b.data.enemies[0].hp == 5, "palm removes six guard before its first-attack damage")
	b = _fixture(["breath", "observe"])
	_play(b, "breath")
	_check(b.data.qi == 4 and b.data.exhaust_pile == ["breath"], "breath grants one qi and exhausts")
	_play(b, "observe")
	_check(b.data.hand.size() == 2 and b.data.qi == 3 and "observe" not in b.data.hand, "observe draws two and cannot redraw itself")
	b.data.hp -= 25
	_check(b.use_medicine().ok and b.data.qi == 2 and b.data.hp == b.data.max_hp - 5 and b.data.medicine_used == 1, "medicine spends qi and heals twenty")
	b.end_turn()
	original = b.snapshot()
	_check(not b.use_medicine().ok and b.snapshot() == original, "medicine remains once per entire battle after a new turn")
	b = _fixture(["guard"])
	original = b.snapshot()
	_check(not b.use_medicine().ok and b.snapshot() == original, "full-health medicine fails without consuming resources")
	_check(not b.play_card(-1).ok and not b.play_card(20).ok and not b.play_card(0, 0, true).ok, "invalid indices and nonexistent boost fail safely")

func _test_inners() -> void:
	var b := _fixture(["guard", "probing_stone", "pushing_palm", "gather_momentum"], "xingyun")
	_play(b, "guard")
	_play(b, "probing_stone")
	_check(b.data.last_paid_type == "guard" and b.data.momentum == 0, "zero-cost card does not update paid-route memory")
	_play(b, "pushing_palm")
	_check(b.data.momentum == 1 and b.data.xingyun_gain_used, "first different paid route grants exactly one momentum")
	_play(b, "gather_momentum")
	_check(b.data.momentum == 2 and b.data.momentum_gained == 2, "card and inner share the same two-point round limit")
	b = _fixture(["probing_stone", "probing_stone", "gather_momentum"], "xingyun")
	_momentum(b, 2)
	var count: int = b.data.hand.size()
	_play(b, "probing_stone", true)
	_check(b.data.hand.size() == count + 1 and b.data.xingyun_draw_used, "first boosted stone draws its own card plus one inner card")
	count = b.data.hand.size()
	_play(b, "probing_stone", true)
	_check(b.data.hand.size() == count and b.data.momentum == 0, "second boost receives no second inner draw")
	b = _fixture(["gather_momentum", "gather_momentum", "guard"], "shouzhong", "flurry")
	_play(b, "gather_momentum")
	_play(b, "gather_momentum")
	_play(b, "guard")
	b.end_turn()
	_check(b.data.momentum == 2, "guard absorption cannot bypass the shared round gain cap")
	b = _fixture(["guard"], "shouzhong", "flurry")
	_play(b, "guard")
	b.end_turn()
	_check(b.data.momentum == 1 and b.data.hp == b.data.max_hp - 2, "multi-hit enemy grants guardian momentum only once on actual absorption")
	b = _fixture(["opening_thrust"], "shouzhong")
	_momentum(b, 1)
	var hp: int = b.data.enemies[0].hp
	_play(b, "opening_thrust", true)
	_check(hp - b.data.enemies[0].hp == 10 and b.data.block == 2 and not b.data.first_block_used, "inner guard arrives after attack and does not satisfy the same card guard condition or consume agility")
	b = _fixture(["gather_momentum"], "guiyuan", "armored")
	b.end_turn()
	_check(b.data.momentum == 1 and b.data.qi == 3, "guiyuan stores one momentum then refreshes qi, never carrying unused qi")
	b = _fixture(["gather_momentum", "gather_momentum"])
	_momentum(b, 3)
	_play(b, "gather_momentum")
	_check(b.data.momentum == 3 and b.data.momentum_gained == 0, "full momentum pool does not record nonexistent gains")

func _test_choices_and_retention() -> void:
	for branch in ["", "stable", "specialist"]:
		var b := _fixture(["cloud_step", "strike", "guard"], "xingyun", "armored", {} if branch == "" else {"cloud_step": branch})
		_check(_play(b, "cloud_step").ok and b.data.phase == "choice", "footwork opens a resumable choice: " + branch)
		_check(b.data.qi == 2 and b.data.block == (7 if branch == "stable" else 5), "footwork paid and guarded exactly once before choice")
		_check(b.data.in_play == ["cloud_step"] and b.data.pending_choice.max_count == (2 if branch == "specialist" else 1), "playing card held outside drawable piles with branch choice count")
		var snapshot := b.snapshot()
		_check(_valid(b), "pending cycle is a valid JSON snapshot")
		var restored := Battle.new()
		_check(restored.configure("armored", b.data.stats, JSON.parse_string(JSON.stringify(snapshot))).ok, "load resumes exact pending cycle")
		_check(not b.end_turn().ok and not b.use_medicine().ok and not b.play_card(0).ok and b.snapshot() == snapshot, "pending selection blocks all unrelated actions")
		_check(not b.resolve_choice([0, 0]).ok and not b.resolve_choice([99]).ok and b.snapshot() == snapshot, "invalid cycle is atomic")
		var selection := [0, 1] if branch == "specialist" else [0]
		_check(b.resolve_choice(selection).ok and restored.resolve_choice(selection).ok and b.snapshot() == restored.snapshot(), "choice after reload yields identical cards, inner flags and RNG")
		_check(b.data.qi == 2 and b.data.block == (7 if branch == "stable" else 5) and b.data.cards_played == 1, "choice completion never pays or blocks a second time")
		_check("cloud_step" not in b.data.hand and b.data.in_play.is_empty() and _valid(b), "cycle never redraws currently executing card")
		_check(not b.resolve_choice([]).ok, "completed cycle cannot resolve twice")
	var b := _fixture(["cloud_step"], "xingyun", "armored")
	_check(b.play_card(0, 999).ok and _valid(b), "self-targeted cycle canonicalizes irrelevant target before snapshot")
	_check(b.resolve_choice([]).ok and b.data.phase == "player", "empty-hand optional cycle can be skipped")
	b = _battle("armored")
	var retained: String = b.data.hand[2]
	var draw_before: int = b.data.draw_pile.size()
	_check(b.end_turn(2).ok and b.data.hand.size() == 5 and b.data.hand[0] == retained, "one retained card remains at the front and counts toward five")
	_check(b.data.draw_pile.size() == draw_before - 4 and b.data.retains_used == 1, "retaining consumes a draw opportunity rather than producing a sixth hand card")
	var snapshot := b.snapshot()
	_check(not b.end_turn(99).ok and b.snapshot() == snapshot, "invalid retain position cannot advance enemies")
	b = Battle.new()
	_check(b.configure("practice", _stats()).ok and b.data.hand.size() == 5, "initial hand contains exactly five")
	_check(b.mulligan([0, 2]).ok and b.data.hand.size() == 5 and _valid(b), "one opening redraw conserves cards")
	_check(not b.mulligan([]).ok, "opening redraw cannot be repeated")

func _test_reaction_order() -> void:
	var b := _fixture(["yielding_palm", "yielding_palm"], "shouzhong", "flurry")
	_momentum(b, 2)
	_play(b, "yielding_palm", true)
	_play(b, "yielding_palm", true)
	var before: int = b.data.enemies[0].hp
	_check(b.data.retaliation == 6 and b.data.block == 14, "two preparations keep the strongest single retaliation, not a sum")
	b.end_turn()
	_check(before - b.data.enemies[0].hp == 6 and b.data.momentum == 1, "three enemy hits trigger one retaliation and one guardian gain")
	b = _fixture(["yielding_palm"], "shouzhong", "flurry")
	_momentum(b, 1)
	_play(b, "yielding_palm", true)
	b.data.enemies[0].hp = 6 # Isolated death-order fixture.
	b.end_turn()
	_check(b.data.phase == "won" and b.data.hp == b.data.max_hp and b.data.momentum == 0, "retaliation kill cancels the enemy remaining hits and clears battle momentum")
	b = _fixture(["yielding_palm"], "shouzhong", "flurry")
	_momentum(b, 1)
	_play(b, "yielding_palm", true)
	b.data.block = 1
	b.data.hp = 1 # Fatal partially blocked hit must not retaliate.
	before = b.data.enemies[0].hp
	b.end_turn()
	_check(b.data.phase == "lost" and b.data.enemies[0].hp == before, "dead player cannot retaliate after absorbing part of a lethal hit")
	b = _fixture(["opening_thrust", "strike", "hidden_needle"], "shouzhong", "counter")
	_momentum(b, 1)
	var hp: int = b.data.hp
	_play(b, "opening_thrust", true)
	_check(hp - b.data.hp == 3 and b.data.enemies[0].counter_used and b.data.momentum == 0, "inner provides two guard before five-damage enemy counter; counter cannot generate guardian momentum")
	hp = b.data.hp
	_play(b, "strike")
	_check(b.data.hp == hp, "enemy counter only reacts once in the player round")
	b = _fixture(["hidden_needle"], "guiyuan", "counter")
	_momentum(b, 1)
	hp = b.data.hp
	_play(b, "hidden_needle", true)
	_check(b.data.hp == hp and not b.data.enemies[0].counter_used and b.data.delayed.size() == 1, "delayed setup neither attacks immediately nor triggers counter stance")
	var enemy_hp: int = b.data.enemies[0].hp
	var boosts: int = b.data.boosts_used
	b.end_turn()
	_check(enemy_hp - b.data.enemies[0].hp == 8 and b.data.delayed.is_empty(), "eleven delayed damage meets three enemy guard at next player turn")
	_check(b.data.boosts_used == boosts and _valid(b), "delayed hit never repeats payment or boost reward")
	b = _fixture(["hidden_needle", "strike"], "guiyuan", "grove")
	_play(b, "hidden_needle", false, 0)
	b.data.enemies[0].hp = 1
	_play(b, "strike", false, 0)
	var other_hp: int = b.data.enemies[1].hp
	b.end_turn()
	_check(b.data.enemies[1].hp == other_hp and b.data.delayed.is_empty(), "dead delayed target cancels instead of transferring damage")

func _test_locked_intentions() -> void:
	var b := _fixture(["sword_qi"], "guiyuan", "exam")
	_momentum(b, 3)
	b.data.enemies[0].hp = 50
	var promised: Dictionary = b.data.enemies[0].intent.duplicate(true)
	_play(b, "sword_qi", true)
	_check(b.data.enemies[0].hp < 48 and b.data.enemies[0].stage == 1 and b.data.enemies[0].intent == promised, "crossing boss threshold never changes a promised intent mid-turn")
	_check(_valid(b), "mid-turn below-half boss snapshot remains valid with old intent")
	b.end_turn()
	_check(b.data.enemies[0].stage == 2 and str(b.data.enemies[0].intent.label).begins_with("二式"), "boss changes phase at next player turn")
	var r := Battle.new()
	_check(r.configure("exam", b.data.stats, JSON.parse_string(JSON.stringify(b.snapshot()))).ok and r.snapshot() == b.snapshot(), "latched boss phase is exact across JSON restore")

func _test_snapshots_and_previews() -> void:
	for id in Cards.CARDS:
		for branch in (["", "stable", "specialist"] if id in Cards.REFINABLE else [""]):
			for empowered in [false, true]:
				var c: Dictionary = Cards.card(id, branch, empowered)
				if c.is_empty(): continue
				var b := _fixture([id, "guard"] if id != "guard" else [id], "xingyun", "counter", {} if branch == "" else {id: branch})
				_momentum(b, 3)
				var before := b.snapshot()
				var preview := b.preview_card(0, 0, empowered)
				_check(preview.ok and preview.can_play and b.snapshot() == before, "preview is pure for " + id + "/" + branch + "/" + str(empowered))
				_check(not preview.has("hand") and not preview.has("draw_pile") and not preview.has("rng_state"), "preview does not reveal drawn identities")
				var enemy_before: int = b.data.enemies[0].hp
				var hero_before: int = b.data.hp
				var result: Dictionary = b.play_card(0, 0, empowered)
				if b.data.phase == "choice": b.resolve_choice([])
				var predicted := 0
				for hit in preview.damage: predicted += int(hit.hp_loss)
				_check(result.ok and enemy_before - b.data.enemies[0].hp == predicted and hero_before - b.data.hp == preview.recoil, "preview matches damage and counter risk for " + id)
				_check(_valid(b), "card result JSON snapshot valid for " + id)
	var b := _fixture(["cloud_step", "hidden_needle", "gather_momentum"], "xingyun", "charging", {"cloud_step": "specialist"})
	_play(b, "hidden_needle")
	_play(b, "cloud_step")
	var valid := b.snapshot()
	var corruptions := [
		{"version": 1}, {"momentum": 4}, {"momentum_gained": 3}, {"in_play": []}, {"pending_choice": {}},
		{"phase": "player"}, {"rng_state": 1.5}, {"medicine_used": 2}, {"retaliation": 12},
		{"last_paid_type": "skill"}, {"hand": valid.hand + ["strike"]}, {"refinements": {"bad": "bad"}},
	]
	# Unknown top-level metadata does not alter rules, so test the actual fixed stats.
	corruptions.pop_back()
	for fields in corruptions:
		var bad := valid.duplicate(true)
		for key in fields: bad[key] = fields[key]
		_check(not Battle.validate_snapshot(bad, b.data.mode, b.data.stats).ok, "corrupt snapshot rejected: " + str(fields.keys()))
		var receiver := _battle("charging")
		var original := receiver.snapshot()
		_check(not receiver.configure("charging", b.data.stats, bad).ok and receiver.snapshot() == original, "failed restore preserves receiver state")
	var bad := valid.duplicate(true)
	bad.pending_choice.max_count = 1
	_check(not Battle.validate_snapshot(bad).ok, "pending refinement choice limit cannot be changed")
	bad = valid.duplicate(true)
	bad.delayed[0].amount = 999
	_check(not Battle.validate_snapshot(bad).ok, "forged delayed damage rejected")
	bad = valid.duplicate(true)
	bad.enemies[0].intent.damage = 999
	_check(not Battle.validate_snapshot(bad).ok, "forged promised enemy intent rejected")
	var changed: Dictionary = b.data.stats.duplicate(true)
	changed.inner = "guiyuan"
	_check(not Battle.validate_snapshot(valid, "charging", changed).ok, "locked inner cannot be switched through restore")
	changed = _stats()
	changed.weapon = "unarmed"
	_check(not Battle.new().configure("practice", changed).ok, "wrong weapon cannot equip sword deck")

# A policy using only the current hand, visible intent and pure exposed previews.
# It never peeks at future draw identities, alters HP, grants resources or retries.
func _legal_action(b: WeiyuanCardBattle) -> bool:
	if b.data.phase == "choice":
		var discard: Array = []
		for i in range(b.data.hand.size()):
			var c: Dictionary = Cards.card(b.data.hand[i], str(b.data.stats.refinements.get(b.data.hand[i], "")))
			if (c.cost > b.data.qi or b.data.hand[i] == "probing_stone") and discard.size() < b.data.pending_choice.max_count: discard.append(i)
		return b.resolve_choice(discard).ok
	if b.data.phase != "player": return false
	if b.status().can_use_medicine and b.data.hp <= b.data.max_hp - 20:
		return b.use_medicine().ok
	var incoming := 0
	for enemy in b.data.enemies:
		if enemy.hp > 0: incoming += int(enemy.intent.damage) * int(enemy.intent.hits)
	var best := 0.05
	var chosen := [-1, 0, false]
	for i in range(b.data.hand.size()):
		var id: String = b.data.hand[i]
		for boost in [false, true]:
			var c: Dictionary = Cards.card(id, str(b.data.stats.refinements.get(id, "")), boost)
			if c.is_empty() or c.cost > b.data.qi or c.momentum_cost > b.data.momentum: continue
			for target in range(b.data.enemies.size()):
				if b.data.enemies[target].hp <= 0: continue
				var p: Dictionary = b.preview_card(i, target, boost)
				if not p.get("can_play", false): continue
				var dealt := 0
				for hit in p.damage: dealt += int(hit.hp_loss)
				var score: float = dealt * 2.0 - float(p.recoil) * 1.8
				if dealt >= b.data.enemies[target].hp and dealt > 0: score += 35
				score += mini(int(p.block), maxi(0, incoming - int(b.data.block))) * 1.8
				if c.get("delayed_damage", 0) > 0: score += mini(int(c.delayed_damage), int(b.data.enemies[target].hp)) * 1.5
				if c.get("retaliation", 0) > 0 and incoming > 0 and not b.data.retaliation_used: score += maxi(0, int(c.retaliation) - int(b.data.retaliation)) * 1.6
				if c.get("energy", 0) > 0: score += 35
				if c.get("draw", 0) > 0 and b.data.qi > c.cost: score += int(c.draw) * 7
				if c.get("cycle_limit", 0) > 0 and b.data.hand.size() > 1 and b.data.qi > c.cost: score += 5
				if c.get("momentum_gain", 0) > 0 and b.data.momentum < 3 and b.data.momentum_gained < 2: score += 13 if b.data.stats.inner == "guiyuan" else 7
				if c.get("strip_block", 0) > 0: score += mini(int(c.strip_block), int(b.data.enemies[target].block)) * 0.8
				if b.data.stats.inner == "xingyun" and c.cost > 0 and not b.data.xingyun_gain_used and b.data.last_paid_type != "" and b.data.last_paid_type != c.type: score += 6
				if boost: score -= int(c.momentum_cost) * 1.5
				# At one qi, storing the third point for a retained burst can be
				# worth more than a weak attack against a defensive opponent.
				if b.data.stats.inner == "guiyuan" and b.data.qi == 1 and b.data.momentum < 3 and incoming <= b.data.block and c.cost > 0: score -= 12
				if score > best:
					best = score
					chosen = [i, target, boost]
	if chosen[0] >= 0: return b.play_card(chosen[0], chosen[1], chosen[2]).ok
	var retain := -1
	if b.data.stats.inner == "guiyuan": retain = b.data.hand.find("sword_qi")
	elif b.data.stats.inner == "shouzhong" and b.data.momentum > 0: retain = b.data.hand.find("yielding_palm")
	return b.end_turn(retain).ok

func _test_legal_fights() -> void:
	var wins := 0
	var results: Array = []
	for preset in Cards.PRESETS:
		for mode in Battle.TRIAL_MODES:
			for seed in [7, 42, 2026]:
				var b := _battle(mode, seed, preset)
				var actions := 0
				while b.data.phase not in ["won", "lost"] and actions < 500:
					_check(_legal_action(b), "legal public-information action")
					_check(_valid(b), "live shuffled fight snapshot remains valid")
					actions += 1
				var won: bool = b.data.phase == "won"
				if won: wins += 1
				results.append({"preset": preset, "enemy": mode, "seed": seed, "won": won, "turns": b.data.turn, "hp": b.data.hp})
				_check(actions < 500, "legal action policy terminates without loops")
				_check(won, "legal preset wins " + preset + "/" + mode + "/" + str(seed))
				_check(_valid(b) and b.data.momentum == 0, "terminal result retains valid card conservation and clears momentum")
	print("LEGAL FIGHT MATRIX: ", JSON.stringify(results))
	print("LEGAL FIGHTS WON: %d / 36" % wins)
	# Story encounters must also remain reachable with the real basic deck.
	for mode in ["practice", "spar", "grove", "ridge", "exam"]:
		var s := _stats(42)
		s.deck = Cards.starting_deck()
		var b := Battle.new()
		b.configure(mode, s)
		b.skip_mulligan()
		var actions := 0
		while b.data.phase not in ["won", "lost"] and actions < 500:
			_check(_legal_action(b), "legal starting-deck journey action")
			actions += 1
		_check(_valid(b) and actions < 500, "story encounter ends with valid snapshot: " + mode)
		if mode == "practice": _check(b.data.phase == "won", "beginner deck can win the first training encounter")

func _test_distinct_character_profiles() -> void:
	# These are the actual all-first/all-second/all-third questionnaire results,
	# not fabricated stat bonuses. Origins receive no hidden combat advantage.
	var profiles := [[6, 7, 5, 4, 4, 4], [5, 4, 5, 6, 6, 4], [4, 4, 5, 5, 5, 7]]
	var origins := ["herbalist", "courier", "performer"]
	var wins := 0
	for profile in range(profiles.size()):
		for preset in Cards.PRESETS:
			for mode in Battle.TRIAL_MODES:
				var s := _stats(42, preset)
				s.origin = origins[profile]
				for i in range(Battle.ATTRIBUTES.size()): s.attributes[Battle.ATTRIBUTES[i]] = profiles[profile][i]
				var b := Battle.new()
				_check(b.configure(mode, s).ok, "distinct legal character profile configures")
				b.skip_mulligan()
				var actions := 0
				while b.data.phase not in ["won", "lost"] and actions < 500:
					_check(_legal_action(b), "distinct profile uses only legal current-hand actions")
					actions += 1
				if b.data.phase == "won": wins += 1
				_check(b.data.phase == "won" and _valid(b), "profile completes " + origins[profile] + "/" + preset + "/" + mode)
	print("DISTINCT PROFILE FIGHTS WON: %d / 36" % wins)
