class_name WeiyuanCardBattle
extends RefCounted
## Pure turn model: no scene, clock, reward, calendar or file mutations.
const Cards = preload("res://scripts/card_catalog.gd")
const ATTRIBUTES = ["constitution", "strength", "agility", "resolve", "aptitude", "fortune"]
const MODES = ["practice", "spar", "grove", "ridge", "exam"]
const VERSION = 1
const MAX_TURNS = 200
var data: Dictionary = {}

func configure(mode: String, stats: Dictionary, restore: Dictionary = {}) -> Dictionary:
	var checked := _validate_stats(stats)
	if mode not in MODES: return _failure("不認得這場切磋。")
	if not checked.ok: return checked
	if not restore.is_empty():
		checked = validate_snapshot(restore, mode, stats)
		if not checked.ok: return checked
		data = _normalise_json(restore)
		data.erase("_view")
		return {"ok": true, "message": "已恢復原來的回合。", "events": []}
	var fixed := _fixed_stats(stats)
	var attributes: Dictionary = fixed.attributes
	data = {
		"version": VERSION, "mode": mode, "stats": fixed, "seed": fixed.seed, "rng_state": fixed.seed,
		"phase": "mulligan", "turn": 1, "hp": 52 + int(attributes.constitution) * 3,
		"max_hp": 52 + int(attributes.constitution) * 3, "block": 0, "qi": 3,
		"hand": [], "draw_pile": fixed.deck.duplicate(), "discard_pile": [], "exhaust_pile": [],
		"enemies": _make_enemies(mode, int(fixed.exam_aid)), "medicine_used": 0,
		"medicine_used_this_turn": false, "mulligan_used": false,
		"first_attack_used": false, "first_block_used": false, "skills_played": 0,
		"next_attack_bonus": 0, "hits": 0, "damage_taken": 0, "cards_played": 0,
		"last_events": [], "log": [],
	}
	_shuffle(data.draw_pile)
	_draw(5)
	_refresh_intents()
	return _success("先看敵人意圖；可換一次起手，或直接開始。")

func skip_mulligan() -> Dictionary:
	if data.is_empty() or data.phase != "mulligan": return _failure("現在不能決定起手。")
	data.phase = "player"
	data.mulligan_used = true
	data.last_events = []
	return _success("起手已定，開始出牌。")

func mulligan(indices: Array) -> Dictionary:
	if data.is_empty() or data.phase != "mulligan": return _failure("每場只能在開局換牌一次。")
	if indices.is_empty(): return skip_mulligan()
	if indices.size() > _mulligan_limit(): return _failure("超過定力允許的換牌張數。")
	var selected: Array[int] = []
	for index in indices:
		if not _integer(index, 0, data.hand.size() - 1) or int(index) in selected:
			return _failure("換牌位置無效或重複。")
		selected.append(int(index))
	selected.sort()
	selected.reverse()
	var removed: Array = []
	for index in selected: removed.append(data.hand.pop_at(index))
	data.last_events = []
	# Replacements come from the other half of the initial deck. Returned cards
	# cannot immediately redraw themselves, then rejoin the draw pile fairly.
	_draw(removed.size())
	data.draw_pile.append_array(removed)
	_shuffle(data.draw_pile)
	data.phase = "player"
	data.mulligan_used = true
	return _success("已換好 %d 張起手。" % removed.size())

func play_card(hand_index: int, target_index: int = 0) -> Dictionary:
	if not _can_play(): return _failure("現在不能出牌。")
	if hand_index < 0 or hand_index >= data.hand.size(): return _failure("手牌位置不存在。")
	var id: String = str(data.hand[hand_index])
	var c := Cards.card(id, id in data.stats.upgraded_cards)
	if data.qi < c.cost: return _failure("真氣不足。")
	if c.target == "enemy" and (target_index < 0 or target_index >= data.enemies.size() or data.enemies[target_index].hp <= 0):
		return _failure("請選一名仍在場的對手。")
	data.last_events = [{"kind": "card", "id": id, "name": c.name, "target": target_index}]
	data.hand.remove_at(hand_index)
	data.qi -= int(c.cost)
	data.cards_played += 1
	var bonus: int = 0
	if c.type == "attack":
		if not data.first_attack_used: bonus += int(data.stats.attributes.strength) / 2
		data.first_attack_used = true
		bonus += int(data.next_attack_bonus)
		data.next_attack_bonus = 0
		if c.has("guard_bonus") and data.block > 0: bonus += int(c.guard_bonus)
		if c.get("block_damage", false):
			bonus += int(data.block)
			data.block = 0
		var targets: Array = []
		if c.get("all", false):
			for i in range(data.enemies.size()):
				if data.enemies[i].hp > 0: targets.append(i)
		else: targets.append(target_index)
		# Flat bonuses belong to the whole card, not each hit/target.
		for target in targets:
			for hit in range(int(c.get("hits", 1))):
				if data.enemies[target].hp > 0:
					_damage_enemy(target, int(c.damage) + bonus)
					bonus = 0
	if c.has("weak") and data.enemies[target_index].hp > 0:
		data.enemies[target_index].weak += int(c.weak)
	if c.has("vulnerable") and data.enemies[target_index].hp > 0:
		data.enemies[target_index].vulnerable += int(c.vulnerable)
	if c.has("block"):
		var amount: int = int(c.block)
		if not data.first_block_used: amount += int(data.stats.attributes.agility) / 2
		data.first_block_used = true
		data.block += amount
		data.last_events.append({"kind": "block", "amount": amount})
	if c.has("heal"):
		var healed := mini(int(c.heal), int(data.max_hp) - int(data.hp))
		data.hp += healed
		data.last_events.append({"kind": "heal", "amount": healed})
	data.next_attack_bonus += int(c.get("next_attack", 0))
	data.qi = mini(20, int(data.qi) + int(c.get("energy", 0)))
	if c.has("skill_refund") and data.skills_played > 0: data.qi = mini(20, int(data.qi) + int(c.skill_refund))
	if c.type == "skill": data.skills_played += 1
	_draw(int(c.get("draw", 0)))
	if c.get("exhaust", false): data.exhaust_pile.append(id)
	else: data.discard_pile.append(id)
	_refresh_intents()
	if _living_count() == 0: data.phase = "won"
	return _success("使出「%s」。" % c.name)

func preview_card(hand_index: int, target_index: int = 0) -> Dictionary:
	if data.is_empty() or hand_index < 0 or hand_index >= data.hand.size(): return _failure("手牌位置不存在。")
	if data.phase in ["won", "lost"]: return _failure("本場已結束。")
	var id: String = str(data.hand[hand_index])
	var c := Cards.card(id, id in data.stats.upgraded_cards)
	var preview := WeiyuanCardBattle.new()
	preview.data = data.duplicate(true)
	preview.data.phase = "player"
	preview.data.mulligan_used = true
	# A preview never spends the real qi/RNG state, and remains useful when
	# unaffordable. Drawn identities are deliberately omitted from its result.
	preview.data.qi = maxi(int(data.qi), int(c.cost))
	var result := preview.play_card(hand_index, target_index)
	if not result.ok: return result
	var damage: Array = []
	var parts: Array[String] = []
	var gained_block := 0
	var healed := 0
	for event in result.events:
		if event.kind == "hit":
			damage.append({"target": event.target, "amount": event.amount, "blocked": event.blocked, "hp_loss": event.hp_loss})
			parts.append("對%s扣 %d 氣血%s" % [data.enemies[event.target].name, event.hp_loss, "（另有 %d 傷害被防護抵擋）" % event.blocked if event.blocked > 0 else ""])
		elif event.kind == "block":
			gained_block += int(event.amount)
		elif event.kind == "heal":
			healed += int(event.amount)
	if gained_block > 0: parts.append("獲得 %d 防護" % gained_block)
	if c.has("heal"): parts.append("回復 %d 氣血" % healed)
	if parts.is_empty(): parts.append(c.description)
	return {"ok": true, "message": "預覽不會消耗資源。", "description": "本次：" + "；".join(parts), "damage": damage, "block": gained_block, "heal": healed, "energy_after": preview.data.qi, "can_play": _can_play() and data.qi >= c.cost}

func use_medicine() -> Dictionary:
	if not _can_play(): return _failure("現在不能用藥。")
	if data.medicine_used_this_turn: return _failure("每回合只能用一次藥。")
	if data.medicine_used >= data.stats.medicine: return _failure("沒有剩餘的回復藥。")
	if data.hp >= data.max_hp: return _failure("氣血充足，先留著藥。")
	var healed := mini(20, int(data.max_hp) - int(data.hp))
	data.hp += healed
	data.medicine_used += 1
	data.medicine_used_this_turn = true
	data.last_events = [{"kind": "medicine", "amount": healed}]
	return _success("回復 %d 氣血；本回合已用藥。" % healed)

func end_turn() -> Dictionary:
	if not _can_play(): return _failure("現在不能結束回合。")
	data.last_events = []
	data.discard_pile.append_array(data.hand)
	data.hand.clear()
	for enemy in data.enemies:
		if enemy.hp <= 0: continue
		enemy.block = 0
		var intent: Dictionary = enemy.intent
		data.last_events.append({"kind": "intent", "enemy": enemy.id, "label": intent.label})
		if intent.block > 0: enemy.block = int(intent.block)
		for hit in range(int(intent.hits)):
			var damage: int = int(intent.damage)
			if enemy.weak > 0: damage = floori(damage * 0.75)
			var prevented := mini(int(data.block), damage)
			data.block -= prevented
			damage -= prevented
			data.hp = maxi(0, int(data.hp) - damage)
			data.damage_taken += damage
			data.last_events.append({"kind": "hurt", "enemy": enemy.id, "amount": damage, "blocked": prevented})
			if data.hp <= 0:
				data.phase = "lost"
				_refresh_intents()
				return _success("本場落敗；可用同一起手重試。")
		enemy.weak = maxi(0, int(enemy.weak) - 1)
		enemy.vulnerable = maxi(0, int(enemy.vulnerable) - 1)
		enemy.intent_index += 1
	if data.turn >= MAX_TURNS:
		data.phase = "lost"
		_refresh_intents()
		return _success("切磋過久，先認輸歇息。")
	data.turn += 1
	data.block = 0
	data.qi = 3
	data.first_attack_used = false
	data.first_block_used = false
	data.skills_played = 0
	data.next_attack_bonus = 0
	data.medicine_used_this_turn = false
	_draw(5)
	_refresh_intents()
	return _success("第 %d 回合，真氣與手牌已補足。" % data.turn)

func status() -> Dictionary:
	if data.is_empty(): return {"ready": false, "resolved": false}
	var result := data.duplicate(true)
	result.ready = true
	result.resolved = data.phase in ["won", "lost"]
	result.won = data.phase == "won"
	result.max_qi = 3
	result.energy = data.qi
	result.max_energy = 3
	result.medicine_left = int(data.stats.medicine) - int(data.medicine_used)
	result.medicine = result.medicine_left
	result.draw_count = data.draw_pile.size()
	result.discard_count = data.discard_pile.size()
	result.exhaust_count = data.exhaust_pile.size()
	result.attributes = data.stats.attributes.duplicate(true)
	result.upgraded_cards = data.stats.upgraded_cards.duplicate()
	result.mulligan_limit = _mulligan_limit()
	result.can_play = _can_play()
	result.can_end_turn = _can_play()
	result.can_use_medicine = _can_play() and not data.medicine_used_this_turn and result.medicine_left > 0 and data.hp < data.max_hp
	return result

func snapshot() -> Dictionary:
	return data.duplicate(true)

func report() -> Dictionary:
	if data.is_empty(): return {}
	return {"medicine_used": data.medicine_used, "hits": data.hits, "damage_taken": data.damage_taken, "turns": data.turn, "mode": data.mode, "won": data.phase == "won", "seed": data.seed, "cards_played": data.cards_played}

func _can_play() -> bool:
	return not data.is_empty() and data.phase == "player"

func _mulligan_limit() -> int:
	return mini(5, 1 + int(data.stats.attributes.resolve) / 3)

func _living_count() -> int:
	var count := 0
	for enemy in data.enemies:
		if enemy.hp > 0: count += 1
	return count

func _draw(amount: int) -> void:
	for i in range(amount):
		if data.draw_pile.is_empty():
			if data.discard_pile.is_empty(): break
			data.draw_pile = data.discard_pile.duplicate()
			data.discard_pile.clear()
			_shuffle(data.draw_pile)
			data.last_events.append({"kind": "shuffle"})
		data.hand.append(data.draw_pile.pop_back())

func _shuffle(pile: Array) -> void:
	for i in range(pile.size() - 1, 0, -1):
		# An exact 31-bit state fits both JSON and browser integer precision.
		data.rng_state = (int(data.rng_state) * 1103515245 + 12345) % 2147483648
		var j: int = int(data.rng_state) % (i + 1)
		var saved: Variant = pile[i]
		pile[i] = pile[j]
		pile[j] = saved

func _damage_enemy(index: int, amount: int) -> void:
	var enemy: Dictionary = data.enemies[index]
	if enemy.vulnerable > 0: amount = floori(amount * 1.5)
	var prevented := mini(int(enemy.block), amount)
	enemy.block -= prevented
	amount -= prevented
	var hp_loss := mini(int(enemy.hp), amount)
	enemy.hp -= hp_loss
	data.hits += 1
	data.last_events.append({"kind": "hit", "target": index, "amount": amount, "blocked": prevented, "hp_loss": hp_loss})

func _refresh_intents() -> void:
	for enemy in data.enemies: enemy.intent = _intent(enemy, str(data.mode))

func _success(message: String) -> Dictionary:
	data.log.append(message)
	if data.log.size() > 32: data.log.pop_front()
	return {"ok": true, "message": message, "events": data.last_events.duplicate(true)}

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message, "events": []}

static func _make_enemies(mode: String, aid: int) -> Array:
	var specs: Array
	match mode:
		"practice": specs = [["bandit", 28]]
		"spar": specs = [["bandit", 44]]
		"grove": specs = [["bandit", 30], ["lancer", 26]]
		"ridge": specs = [["bandit", 36], ["lancer", 34]]
		_: specs = [["examiner", 96 - aid * 6]]
	var result: Array = []
	for i in range(specs.size()):
		var kind: String = specs[i][0]
		result.append({"id": i, "kind": kind, "name": {"bandit": "短刀客", "lancer": "長兵客", "examiner": "考核教頭"}[kind], "hp": specs[i][1], "max_hp": specs[i][1], "block": 0, "weak": 0, "vulnerable": 0, "intent_index": i, "intent": {}})
	return result

static func _intent(enemy: Dictionary, mode: String) -> Dictionary:
	if enemy.hp <= 0: return {"kind": "defeated", "label": "已退場", "damage": 0, "display_damage": 0, "hits": 0, "block": 0}
	var damage := 0
	var hits := 0
	var block := 0
	var label := ""
	var turn: int = int(enemy.intent_index)
	if enemy.kind == "bandit":
		match turn % 3:
			0: damage = 5 if mode == "practice" else 7; hits = 1; label = "近身劈擊"
			1: block = 4; label = "收刀防守"
			2: damage = 8 if mode == "practice" else 10; hits = 1; label = "蓄勢重斬"
	elif enemy.kind == "lancer":
		match turn % 3:
			0: damage = 4; hits = 2; label = "連刺兩下"
			1: block = 5; label = "架槍守勢"
			2: damage = 9; hits = 1; label = "直線突刺"
	else:
		var fierce: bool = int(enemy.hp) * 2 <= int(enemy.max_hp)
		match turn % 4:
			0: damage = 9; hits = 1; label = "照面一劍"
			1: block = 7; label = "沉肩蓄勢"
			2: damage = 4; hits = 3; label = "連環三試"
			3: damage = 14; hits = 1; label = "破勢重劍"
		if fierce:
			if hits > 0: damage += 2
			else: block += 2
			label = "二式 · " + label
	var visible_damage := floori(damage * 0.75) if enemy.weak > 0 else damage
	var description := "%s · %d防護" % [label, block] if hits == 0 else "%s · %d%s傷害" % [label, visible_damage, "×%d" % hits if hits > 1 else ""]
	return {"kind": "guard" if hits == 0 else "attack", "label": description, "damage": damage, "display_damage": visible_damage, "hits": hits, "block": block}

static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= low and float(value) <= high

static func _validate_stats(stats: Dictionary) -> Dictionary:
	if not stats.get("attributes") is Dictionary: return _failure("缺少六項人物屬性。")
	var total := 0
	for key in ATTRIBUTES:
		if not _integer(stats.attributes.get(key), 2, 8): return _failure("人物屬性必須介於二至八。")
		total += int(stats.attributes[key])
	if total != 30: return _failure("六項人物屬性總和必須為三十。")
	var deck_check := Cards.validate_deck(stats.get("deck"), Cards.CARDS.keys())
	if not deck_check.ok: return deck_check
	if stats.get("origin") not in Cards.ORIGIN_CARDS: return _failure("出身資料無效。")
	if not _integer(stats.get("medicine", 0), 0, 999) or not _integer(stats.get("seed", 1), 0, 2147483647): return _failure("藥物或隨機種子資料無效。")
	if not stats.get("exam_aid", 0) is bool and not _integer(stats.get("exam_aid", 0), 0, 3): return _failure("考核支援資料無效。")
	var upgraded: Variant = stats.get("upgraded_cards", [])
	if not upgraded is Array or upgraded.size() > 18: return _failure("精修資料無效。")
	var seen: Array = []
	for id in upgraded:
		if not id is String or not Cards.has(id) or id in seen: return _failure("精修招式無效或重複。")
		seen.append(id)
	return {"ok": true, "message": "戰鬥資料可用。"}

static func _fixed_stats(stats: Dictionary) -> Dictionary:
	var attrs: Dictionary = {}
	for key in ATTRIBUTES: attrs[key] = int(stats.attributes[key])
	return {"attributes": attrs, "deck": stats.deck.duplicate(), "upgraded_cards": stats.get("upgraded_cards", []).duplicate(), "medicine": int(stats.get("medicine", 0)), "origin": str(stats.origin), "seed": int(stats.get("seed", 1)), "exam_aid": clampi(int(stats.get("exam_aid", 0)), 0, 3)}

static func validate_snapshot(saved: Variant, mode: String = "", stats: Dictionary = {}) -> Dictionary:
	if not saved is Dictionary or saved.is_empty(): return _failure("戰鬥快照遺失。")
	if not _json_safe(saved): return _failure("戰鬥快照含有不可儲存的資料。")
	if saved.get("version") != VERSION or saved.get("mode") not in MODES or (not mode.is_empty() and saved.mode != mode): return _failure("戰鬥快照版本或場次不符。")
	if not saved.get("stats") is Dictionary: return _failure("戰鬥快照缺少固定人物資料。")
	var checked := _validate_stats(saved.stats)
	if not checked.ok: return checked
	var fixed := _fixed_stats(saved.stats)
	if not stats.is_empty():
		checked = _validate_stats(stats)
		if not checked.ok: return checked
		if not _same(fixed, _fixed_stats(stats)): return _failure("戰鬥快照不屬於這次鎖定的牌組、屬性或種子。")
	var max_hp: int = 52 + int(fixed.attributes.constitution) * 3
	for key in ["seed", "rng_state"]:
		if not _integer(saved.get(key), 0, 2147483647): return _failure("隨機狀態損壞。")
	if saved.seed != fixed.seed or saved.get("max_hp") != max_hp: return _failure("人物上限或種子已改動。")
	var ranges := {"turn": [1, MAX_TURNS], "hp": [0, max_hp], "block": [0, 200], "qi": [0, 20], "medicine_used": [0, fixed.medicine], "skills_played": [0, 100], "next_attack_bonus": [0, 100], "hits": [0, 10000], "damage_taken": [0, 100000], "cards_played": [0, 10000]}
	for key in ranges:
		if not _integer(saved.get(key), int(ranges[key][0]), int(ranges[key][1])): return _failure("戰鬥數值損壞：" + key)
	for key in ["medicine_used_this_turn", "mulligan_used", "first_attack_used", "first_block_used"]:
		if not saved.get(key) is bool: return _failure("戰鬥旗標損壞：" + key)
	if saved.medicine_used_this_turn and saved.medicine_used == 0: return _failure("用藥旗標與庫存不符。")
	if saved.skills_played > saved.cards_played or saved.hits > saved.cards_played * 4: return _failure("出牌紀錄不符。")
	if saved.get("phase") not in ["mulligan", "player", "won", "lost"]: return _failure("戰鬥階段損壞。")
	var actual: Dictionary = {}
	var expected: Dictionary = {}
	for id in fixed.deck: expected[id] = int(expected.get(id, 0)) + 1
	for pile in ["hand", "draw_pile", "discard_pile", "exhaust_pile"]:
		if not saved.get(pile) is Array or saved[pile].size() > 10: return _failure("牌堆資料損壞。")
		for id in saved[pile]:
			if not id is String or not Cards.has(id): return _failure("牌堆含未知招式。")
			if pile == "exhaust_pile" and not Cards.card(id, id in fixed.upgraded_cards).get("exhaust", false): return _failure("不可除外的招式被移入除外堆。")
			actual[id] = int(actual.get(id, 0)) + 1
	if actual != expected: return _failure("牌堆不守恆，不能繼續此快照。")
	var foes := _make_enemies(str(saved.mode), int(fixed.exam_aid))
	if not saved.get("enemies") is Array or saved.enemies.size() != foes.size(): return _failure("對手資料損壞。")
	var alive := 0
	for i in range(foes.size()):
		var enemy: Variant = saved.enemies[i]
		if not enemy is Dictionary: return _failure("對手資料損壞。")
		for key in ["id", "kind", "name", "max_hp"]:
			if enemy.get(key) != foes[i][key]: return _failure("對手身分或氣血上限不符。")
		for key in ["hp", "block", "weak", "vulnerable", "intent_index"]:
			var maximum: int = int(enemy.max_hp) if key == "hp" else (MAX_TURNS + 2 if key == "intent_index" else 200)
			if not _integer(enemy.get(key), 0, maximum): return _failure("對手狀態損壞。")
		if enemy.hp > 0: alive += 1
		# Intent is derived, not trusted from an external save.
		if not _same(enemy.get("intent"), _intent(enemy, str(saved.mode))): return _failure("對手意圖與狀態不符。")
	if saved.phase == "won" and (alive != 0 or saved.hp <= 0): return _failure("勝負結果不符。")
	if saved.phase in ["player", "mulligan"] and (alive == 0 or saved.hp <= 0): return _failure("未結算的勝負狀態無效。")
	if saved.phase == "lost" and saved.hp > 0 and saved.turn != MAX_TURNS: return _failure("落敗結果不符。")
	if saved.phase == "mulligan" and (saved.turn != 1 or saved.mulligan_used or saved.cards_played != 0 or saved.medicine_used != 0 or saved.hand.size() != 5): return _failure("換牌階段無效。")
	if saved.phase != "mulligan" and not saved.mulligan_used: return _failure("尚未確認起手。")
	if not saved.get("log") is Array or saved.log.size() > 32 or not saved.get("last_events") is Array or saved.last_events.size() > 64: return _failure("戰鬥紀錄損壞。")
	for line in saved.log:
		if not line is String or line.length() > 500: return _failure("戰鬥紀錄文字損壞。")
	for event in saved.last_events:
		if not event is Dictionary or not event.get("kind") is String: return _failure("戰鬥演出紀錄損壞。")
	return {"ok": true, "message": "戰鬥快照有效。"}


static func _same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float): return float(a) == float(b)
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not _same(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for i in range(a.size()):
			if not _same(a[i], b[i]): return false
		return true
	return a == b

static func _normalise_json(value: Variant) -> Variant:
	if value is float and is_finite(value) and value == floorf(value): return int(value)
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value: result[key] = _normalise_json(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(_normalise_json(item))
		return result
	return value


static func _json_safe(value: Variant, depth: int = 0) -> bool:
	if depth > 20: return false
	if value == null or value is bool or value is int: return true
	if value is float: return is_finite(value)
	if value is String or value is StringName: return str(value).length() <= 4000
	if value is Array:
		if value.size() > 100: return false
		for item in value:
			if not _json_safe(item, depth + 1): return false
		return true
	if value is Dictionary:
		if value.size() > 100: return false
		for key in value:
			if not (key is String or key is StringName) or not _json_safe(value[key], depth + 1): return false
		return true
	return false
