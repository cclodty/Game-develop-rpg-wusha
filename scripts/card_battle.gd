class_name WeiyuanCardBattle
extends RefCounted
## Pure martial rules: explicit resource payment, resumable choices and exact RNG.
const Cards = preload("res://scripts/card_catalog.gd")
const ATTRIBUTES = ["constitution", "strength", "agility", "resolve", "aptitude", "fortune"]
const TRIAL_MODES = ["flurry", "armored", "charging", "counter"]
const MODES = ["practice", "spar", "grove", "ridge", "exam", "flurry", "armored", "charging", "counter"]
const VERSION = 2
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
		return {"ok": true, "message": "已恢復原來的回合與待選招式。", "events": []}
	var fixed := _fixed_stats(stats)
	var max_hp: int = 52 + int(fixed.attributes.constitution) * 3
	data = {
		"version": VERSION, "mode": mode, "stats": fixed, "seed": fixed.seed, "rng_state": fixed.seed,
		"phase": "mulligan", "turn": 1, "hp": max_hp, "max_hp": max_hp, "block": 0, "qi": 3,
		"momentum": 0, "momentum_gained": 0, "momentum_generated": 0, "momentum_spent": 0,
		"hand": [], "draw_pile": fixed.deck.duplicate(), "discard_pile": [], "exhaust_pile": [], "in_play": [],
		"pending_choice": {}, "delayed": [], "next_effect_id": 1,
		"enemies": _make_enemies(mode, int(fixed.exam_aid), str(fixed.encounter_variant)),
		"medicine_used": 0, "medicine_used_this_turn": false, "mulligan_used": false,
		"first_attack_used": false, "first_block_used": false, "last_paid_type": "",
		"shouzhong_triggered": false, "xingyun_gain_used": false, "xingyun_draw_used": false, "guiyuan_gain_used": false,
		"retaliation": 0, "retaliation_used": false,
		"hits": 0, "damage_taken": 0, "cards_played": 0, "boosts_used": 0, "retains_used": 0,
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
	var selected := _selected_indices(indices, data.hand.size(), _mulligan_limit())
	if not selected.ok: return selected
	var removed: Array = []
	for index in selected.indices: removed.append(data.hand.pop_at(index))
	data.last_events = []
	_draw(removed.size())
	data.draw_pile.append_array(removed)
	_shuffle(data.draw_pile)
	data.phase = "player"
	data.mulligan_used = true
	return _success("已換好 %d 張起手。" % removed.size())

func play_card(hand_index: int, target_index: int = 0, empowered: bool = false) -> Dictionary:
	if not _can_play(): return _failure("請先完成目前的選牌，再出招。")
	if hand_index < 0 or hand_index >= data.hand.size(): return _failure("手牌位置不存在。")
	var id: String = str(data.hand[hand_index])
	var c := _card(id, empowered)
	if c.is_empty(): return _failure("這張牌沒有此運勁方式或練法。")
	if int(data.qi) < int(c.cost): return _failure("真氣不足。")
	if int(data.momentum) < int(c.momentum_cost): return _failure("勢不足；可改用普通施展。")
	if c.target == "enemy" and not _valid_target(target_index): return _failure("請選一名仍在場的對手。")
	if c.target != "enemy": target_index = 0
	# The played card remains outside every drawable pile until all choices and
	# inner rewards finish. Payment precedes every resource-producing effect.
	data.last_events = [{"kind": "card", "id": id, "name": c.name, "target": target_index, "empowered": empowered}]
	data.hand.remove_at(hand_index)
	data.in_play.append(id)
	data.qi -= int(c.cost)
	data.momentum -= int(c.momentum_cost)
	data.momentum_spent += int(c.momentum_cost)
	data.cards_played += 1
	if empowered: data.boosts_used += 1
	if int(c.momentum_cost) > 0: data.last_events.append({"kind": "momentum_spent", "amount": int(c.momentum_cost)})
	var context := {"kind": "cycle", "card_id": id, "target": target_index, "empowered": empowered,
		"paid_qi": int(c.cost), "paid_momentum": int(c.momentum_cost), "type": str(c.type), "max_count": int(c.get("cycle_limit", 0))}
	_apply_card_effects(c, target_index)
	if int(c.get("cycle_limit", 0)) > 0:
		data.phase = "choice"
		data.pending_choice = context
		return _success("選擇要換掉的其他手牌，或略過；真氣與防護已結算。")
	_finish_card(c, context)
	return _success("使出「%s」%s。" % [c.name, "（運勁）" if empowered else ""])

func resolve_choice(indices: Array) -> Dictionary:
	if data.is_empty() or data.phase != "choice": return _failure("現在沒有待完成的換牌。")
	var selected := _selected_indices(indices, data.hand.size(), int(data.pending_choice.max_count))
	if not selected.ok: return selected
	var context: Dictionary = data.pending_choice.duplicate(true)
	var c := _card(str(context.card_id), bool(context.empowered))
	data.last_events = []
	for index in selected.indices: data.discard_pile.append(data.hand.pop_at(index))
	_draw(selected.indices.size())
	data.pending_choice = {}
	data.phase = "player"
	_finish_card(c, context)
	return _success("已換好 %d 張牌，內功回報已結算。" % selected.indices.size())

func _apply_card_effects(c: Dictionary, target: int) -> void:
	if int(c.get("strip_block", 0)) > 0 and _valid_target(target):
		var stripped := mini(int(data.enemies[target].block), int(c.strip_block))
		data.enemies[target].block -= stripped
		data.last_events.append({"kind": "strip_block", "target": target, "amount": stripped})
	if c.type == "attack" and int(c.get("damage", 0)) > 0:
		var bonus := 0
		if not data.first_attack_used: bonus += int(data.stats.attributes.strength) / 2
		data.first_attack_used = true
		if data.block > 0: bonus += int(c.get("guard_bonus", 0))
		if data.stats.inner == "guiyuan" and int(c.momentum_cost) == 3: bonus += 8
		# Flat additions apply once to the whole attack, never every hit/target.
		for hit in range(int(c.get("hits", 1))):
			if _valid_target(target):
				_damage_enemy(target, int(c.damage) + bonus, "attack")
				bonus = 0
	if int(c.get("block", 0)) > 0:
		var amount := int(c.block)
		if not data.first_block_used: amount += int(data.stats.attributes.agility) / 2
		data.first_block_used = true
		_add_block(amount, "card")
	if int(c.get("retaliation", 0)) > 0:
		data.retaliation = maxi(int(data.retaliation), int(c.retaliation))
		data.last_events.append({"kind": "retaliation_ready", "amount": int(data.retaliation)})
	if int(c.get("delayed_damage", 0)) > 0 and _valid_target(target):
		var effect := {"id": int(data.next_effect_id), "source": str(c.id), "target": target,
			"amount": int(c.delayed_damage), "due_turn": int(data.turn) + 1, "empowered": bool(c.empowered)}
		data.next_effect_id += 1
		data.delayed.append(effect)
		data.last_events.append({"kind": "delayed", "target": target, "amount": effect.amount, "due_turn": effect.due_turn})
	var energy := int(c.get("energy", 0))
	if energy > 0:
		data.qi = mini(20, int(data.qi) + energy)
		data.last_events.append({"kind": "energy", "amount": energy})
	_gain_momentum(int(c.get("momentum_gain", 0)), "card")
	_draw(int(c.get("draw", 0)))

func _finish_card(c: Dictionary, context: Dictionary) -> void:
	var inner: String = str(data.stats.inner)
	var paid_qi: int = int(context.paid_qi)
	var paid_momentum: int = int(context.paid_momentum)
	if inner == "xingyun" and paid_qi > 0:
		if not data.xingyun_gain_used and not str(data.last_paid_type).is_empty() and data.last_paid_type != c.type:
			data.xingyun_gain_used = true
			_gain_momentum(1, "xingyun")
		data.last_paid_type = str(c.type)
	if inner == "shouzhong" and paid_momentum > 0: _add_block(2 * paid_momentum, "shouzhong")
	if inner == "xingyun" and paid_momentum > 0 and not data.xingyun_draw_used:
		data.xingyun_draw_used = true
		_draw(1)
	# A counter stance answers a direct attack after the player's inner reward.
	var target: int = int(context.target)
	if c.type == "attack" and _valid_target(target):
		var enemy: Dictionary = data.enemies[target]
		if int(enemy.intent.get("counter_damage", 0)) > 0 and not enemy.counter_used:
			enemy.counter_used = true
			_hurt_player(target, int(enemy.intent.counter_damage), false)
	data.in_play.clear()
	if c.get("exhaust", false): data.exhaust_pile.append(str(c.id))
	else: data.discard_pile.append(str(c.id))
	_settle()

func preview_card(hand_index: int, target_index: int = 0, empowered: bool = false) -> Dictionary:
	if data.is_empty() or hand_index < 0 or hand_index >= data.hand.size(): return _failure("手牌位置不存在。")
	if data.phase in ["won", "lost", "choice"]: return _failure("請先完成目前的選擇。")
	var c := _card(str(data.hand[hand_index]), empowered)
	if c.is_empty(): return _failure("這張牌沒有此運勁方式。")
	var preview := WeiyuanCardBattle.new()
	preview.data = data.duplicate(true)
	preview.data.phase = "player"
	preview.data.mulligan_used = true
	preview.data.qi = maxi(int(data.qi), int(c.cost))
	preview.data.momentum = maxi(int(data.momentum), int(c.momentum_cost))
	var result := preview.play_card(hand_index, target_index, empowered)
	if not result.ok: return result
	var events: Array = result.events.duplicate(true)
	var requires_choice: bool = preview.data.phase == "choice"
	if requires_choice:
		var completed := preview.resolve_choice([])
		events.append_array(completed.events)
	var damage: Array = []
	var delayed: Array = []
	var parts: Array[String] = []
	var block := 0
	var recoil := 0
	var momentum_gain := 0
	var draws := 0
	for event in events:
		match str(event.kind):
			"hit":
				damage.append({"target": event.target, "amount": event.amount, "blocked": event.blocked, "hp_loss": event.hp_loss})
				parts.append("對%s扣 %d 氣血%s" % [data.enemies[event.target].name, event.hp_loss, "（防護擋下 %d）" % event.blocked if event.blocked > 0 else ""])
			"block": block += int(event.amount)
			"hurt": recoil += int(event.hp_loss)
			"momentum": momentum_gain += int(event.amount)
			"draw": draws += int(event.count)
			"delayed":
				delayed.append(event.duplicate(true))
				parts.append("下回合對%s造成 %d 延遲傷害（仍受防護抵消）" % [data.enemies[event.target].name, event.amount])
			"retaliation_ready": parts.append("準備一次 %d 傷害反擊" % event.amount)
			"strip_block":
				if event.amount > 0: parts.append("移除 %d 敵方防護" % event.amount)
	if block > 0: parts.append("獲得 %d 防護" % block)
	if recoil > 0: parts.append("對手反制扣自己 %d 氣血" % recoil)
	if momentum_gain > 0: parts.append("獲得 %d 勢" % momentum_gain)
	if draws > 0: parts.append("抽 %d 張牌（不預知牌面）" % draws)
	if requires_choice: parts.append("再選最多 %d 張其他手牌換牌，可略過" % c.cycle_limit)
	if int(c.momentum_cost) > 0: parts.append("消耗 %d 勢" % c.momentum_cost)
	if parts.is_empty(): parts.append(str(c.description))
	return {"ok": true, "message": "預覽不會消耗資源。", "description": "本次：" + "；".join(parts),
		"damage": damage, "block": block, "heal": 0, "recoil": recoil, "delayed": delayed,
		"requires_choice": requires_choice, "momentum_gain": momentum_gain, "momentum_cost": int(c.momentum_cost),
		"energy_after": preview.data.qi, "momentum_after": preview.data.momentum,
		"can_play": _can_play() and data.qi >= c.cost and data.momentum >= c.momentum_cost}

func use_medicine() -> Dictionary:
	if not _can_play(): return _failure("請先完成選牌，再用藥。")
	if int(data.medicine_used) >= 1: return _failure("每場只能用一次藥。")
	if int(data.stats.medicine) <= 0: return _failure("沒有剩餘的回復藥。")
	if int(data.qi) < 1: return _failure("用藥需要一點真氣。")
	if data.hp >= data.max_hp: return _failure("氣血充足，先留著藥。")
	var healed := mini(20, int(data.max_hp) - int(data.hp))
	data.qi -= 1
	data.hp += healed
	data.medicine_used = 1
	data.medicine_used_this_turn = true
	data.last_events = [{"kind": "medicine", "amount": healed}]
	return _success("回復 %d 氣血，消耗一真氣；本場已用藥。" % healed)

func end_turn(retain_index: int = -1) -> Dictionary:
	if not _can_play(): return _failure("請先完成目前的選牌，再結束回合。")
	if retain_index < -1 or retain_index >= data.hand.size(): return _failure("保留牌的位置已改變。")
	data.last_events = []
	var retained: Array = []
	if retain_index >= 0:
		retained.append(data.hand[retain_index])
		data.retains_used += 1
		data.last_events.append({"kind": "retain", "id": data.hand[retain_index]})
	for i in range(data.hand.size()):
		if i != retain_index: data.discard_pile.append(data.hand[i])
	data.hand = retained
	if data.stats.inner == "guiyuan" and data.qi > 0 and not data.guiyuan_gain_used:
		data.qi -= 1
		data.guiyuan_gain_used = true
		_gain_momentum(1, "guiyuan")
	for i in range(data.enemies.size()):
		var enemy: Dictionary = data.enemies[i]
		if enemy.hp <= 0: continue
		enemy.block = 0
		var intent: Dictionary = enemy.intent
		data.last_events.append({"kind": "intent", "enemy": i, "label": intent.label})
		enemy.block = int(intent.block)
		for hit in range(int(intent.hits)):
			if enemy.hp <= 0: break
			_hurt_player(i, int(intent.damage), true)
			if _settle(): return _success("本場勝出。" if data.phase == "won" else "本場落敗；可用相同配置與種子重試。")
		enemy.intent_index += 1
	if int(data.turn) >= MAX_TURNS:
		data.phase = "lost"
		_clear_terminal_resources()
		return _success("切磋過久，先認輸歇息。")
	data.turn += 1
	data.phase = "player"
	data.block = 0
	data.qi = 3
	data.momentum_gained = 0
	data.first_attack_used = false
	data.first_block_used = false
	data.last_paid_type = ""
	data.shouzhong_triggered = false
	data.xingyun_gain_used = false
	data.xingyun_draw_used = false
	data.guiyuan_gain_used = false
	data.retaliation = 0
	data.retaliation_used = false
	data.medicine_used_this_turn = false
	for enemy in data.enemies: enemy.counter_used = false
	var due: Array = data.delayed.duplicate(true)
	data.delayed.clear()
	for effect in due:
		if int(effect.due_turn) <= int(data.turn):
			if _valid_target(int(effect.target)): _damage_enemy(int(effect.target), int(effect.amount), "delayed")
		else: data.delayed.append(effect)
	if _settle(): return _success("伏針發作，本場勝出。")
	_draw(maxi(0, 5 - data.hand.size()))
	_refresh_intents()
	return _success("第 %d 回合：保留牌在內，手牌已補至五張。" % data.turn)

func status() -> Dictionary:
	if data.is_empty(): return {"ready": false, "resolved": false}
	var result := data.duplicate(true)
	result.ready = true
	result.resolved = data.phase in ["won", "lost"]
	result.won = data.phase == "won"
	result.max_qi = 3
	result.energy = data.qi
	result.max_energy = 3
	result.max_momentum = 3
	result.momentum_gain_limit = 2
	result.medicine_left = maxi(0, int(data.stats.medicine) - int(data.medicine_used))
	result.medicine = result.medicine_left
	result.draw_count = data.draw_pile.size()
	result.discard_count = data.discard_pile.size()
	result.exhaust_count = data.exhaust_pile.size()
	result.attributes = data.stats.attributes.duplicate(true)
	result.upgraded_cards = data.stats.upgraded_cards.duplicate()
	result.refinements = data.stats.refinements.duplicate(true)
	result.weapon = data.stats.weapon
	result.inner = data.stats.inner
	result.mulligan_limit = _mulligan_limit()
	result.can_play = _can_play()
	result.can_end_turn = _can_play()
	result.can_resolve_choice = data.phase == "choice"
	result.choice_max = int(data.pending_choice.get("max_count", 0))
	result.can_use_medicine = _can_play() and data.medicine_used == 0 and result.medicine_left > 0 and data.hp < data.max_hp and data.qi >= 1
	return result

func snapshot() -> Dictionary:
	return data.duplicate(true)

func report() -> Dictionary:
	if data.is_empty(): return {}
	return {"medicine_used": data.medicine_used, "hits": data.hits, "damage_taken": data.damage_taken,
		"turns": data.turn, "mode": data.mode, "won": data.phase == "won", "seed": data.seed,
		"cards_played": data.cards_played, "hp_left": data.hp, "momentum_spent": data.momentum_spent,
		"momentum_generated": data.momentum_generated, "boosts_used": data.boosts_used, "retains_used": data.retains_used}

func _card(id: String, empowered: bool = false) -> Dictionary:
	return Cards.card(id, str(data.stats.refinements.get(id, "")), empowered)

func _can_play() -> bool:
	return not data.is_empty() and data.phase == "player"

func _valid_target(index: int) -> bool:
	return index >= 0 and index < data.enemies.size() and data.enemies[index].hp > 0

func _mulligan_limit() -> int:
	return mini(5, 1 + int(data.stats.attributes.resolve) / 3)

func _living_count() -> int:
	var count := 0
	for enemy in data.enemies:
		if enemy.hp > 0: count += 1
	return count

func _gain_momentum(amount: int, source: String) -> void:
	var actual := mini(maxi(0, amount), mini(3 - int(data.momentum), 2 - int(data.momentum_gained)))
	if actual <= 0: return
	data.momentum += actual
	data.momentum_gained += actual
	data.momentum_generated += actual
	data.last_events.append({"kind": "momentum", "amount": actual, "source": source})

func _add_block(amount: int, source: String) -> void:
	data.block += amount
	data.last_events.append({"kind": "block", "amount": amount, "source": source})

func _draw(amount: int) -> void:
	var count := 0
	for i in range(amount):
		if data.draw_pile.is_empty():
			if data.discard_pile.is_empty(): break
			data.draw_pile = data.discard_pile.duplicate()
			data.discard_pile.clear()
			_shuffle(data.draw_pile)
			data.last_events.append({"kind": "shuffle"})
		data.hand.append(data.draw_pile.pop_back())
		count += 1
	if count > 0: data.last_events.append({"kind": "draw", "count": count})

func _shuffle(pile: Array) -> void:
	for i in range(pile.size() - 1, 0, -1):
		data.rng_state = (int(data.rng_state) * 1103515245 + 12345) % 2147483648
		var j: int = int(data.rng_state) % (i + 1)
		var saved: Variant = pile[i]
		pile[i] = pile[j]
		pile[j] = saved

func _damage_enemy(index: int, amount: int, source: String = "attack") -> void:
	var enemy: Dictionary = data.enemies[index]
	var prevented := mini(int(enemy.block), amount)
	enemy.block -= prevented
	amount -= prevented
	var hp_loss := mini(int(enemy.hp), amount)
	enemy.hp -= hp_loss
	data.hits += 1
	data.last_events.append({"kind": "hit", "target": index, "amount": amount, "blocked": prevented, "hp_loss": hp_loss, "source": source})
	if enemy.hp == 0: enemy.intent = _intent(enemy, str(data.mode))

func _hurt_player(index: int, amount: int, enemy_turn: bool) -> void:
	var prevented := mini(int(data.block), amount)
	data.block -= prevented
	var remaining := amount - prevented
	var hp_loss := mini(int(data.hp), remaining)
	data.hp -= hp_loss
	data.damage_taken += hp_loss
	data.last_events.append({"kind": "hurt", "enemy": index, "amount": remaining, "hp_loss": hp_loss, "blocked": prevented, "source": "enemy" if enemy_turn else "counter"})
	if not enemy_turn or data.hp <= 0 or prevented == 0: return
	if data.stats.inner == "shouzhong" and not data.shouzhong_triggered:
		data.shouzhong_triggered = true
		_gain_momentum(1, "shouzhong")
	if data.retaliation > 0 and not data.retaliation_used and _valid_target(index):
		data.retaliation_used = true
		_damage_enemy(index, int(data.retaliation), "retaliation")

func _settle() -> bool:
	if data.hp <= 0: data.phase = "lost"
	elif _living_count() == 0: data.phase = "won"
	else: return false
	_clear_terminal_resources()
	return true

func _clear_terminal_resources() -> void:
	data.momentum = 0
	data.delayed.clear()

func _refresh_intents() -> void:
	for enemy in data.enemies:
		if enemy.archetype == "boss" and enemy.hp * 2 <= enemy.max_hp: enemy.stage = 2
		enemy.intent = _intent(enemy, str(data.mode))

func _success(message: String) -> Dictionary:
	data.log.append(message)
	if data.log.size() > 32: data.log.pop_front()
	return {"ok": true, "message": message, "events": data.last_events.duplicate(true)}

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message, "events": []}

static func _selected_indices(indices: Array, size: int, maximum: int) -> Dictionary:
	if indices.size() > maximum: return _failure("超過可選張數。")
	var selected: Array[int] = []
	for index in indices:
		if not _integer(index, 0, size - 1) or int(index) in selected: return _failure("選牌位置無效或重複。")
		selected.append(int(index))
	selected.sort()
	selected.reverse()
	return {"ok": true, "indices": selected}

static func _make_enemies(mode: String, aid: int, variant: String = "") -> Array:
	var specs: Array
	match mode:
		"practice": specs = [["flurry", 28]]
		"spar": specs = [["flurry", 44]]
		"grove": specs = [["flurry", 24], ["armored", 22]]
		"ridge": specs = [["charging", 28], ["counter", 26]]
		"exam": specs = [["boss", 96 - aid * 6]]
		"flurry": specs = [["flurry", 44]]
		"armored": specs = [["armored", 48]]
		"charging": specs = [["charging", 48]]
		_: specs = [["counter", 46]]
	if variant in TRIAL_MODES and mode in ["practice", "spar", "grove", "ridge"]: specs[0][0] = variant
	var names := {"flurry": "連擊教習", "armored": "重甲教習", "charging": "蓄勢教習", "counter": "反制教習", "boss": "考核教頭"}
	var kinds := {"flurry": "bandit", "armored": "lancer", "charging": "lancer", "counter": "bandit", "boss": "examiner"}
	var result: Array = []
	for i in range(specs.size()):
		var archetype: String = specs[i][0]
		result.append({"id": i, "kind": kinds[archetype], "archetype": archetype, "name": names[archetype],
			"hp": specs[i][1], "max_hp": specs[i][1], "block": 0, "weak": 0, "vulnerable": 0,
			"intent_index": i, "stage": 1, "counter_used": false, "intent": {}})
	return result

static func _intent(enemy: Dictionary, mode: String) -> Dictionary:
	if enemy.hp <= 0: return {"kind": "defeated", "label": "已退場", "damage": 0, "display_damage": 0, "hits": 0, "block": 0, "counter_damage": 0}
	var damage := 0
	var hits := 0
	var block := 0
	var counter := 0
	var label := ""
	var turn: int = int(enemy.intent_index)
	match str(enemy.archetype):
		"flurry":
			match turn % 3:
				0: damage = 3; hits = 2 if mode == "practice" else 3; label = "連環短打"
				1: damage = 5; hits = 1; label = "探步一擊"
				2: damage = 3 if mode == "practice" else 4; hits = 2 if mode == "practice" else 3; label = "疾風連擊"
		"armored":
			match turn % 4:
				0: block = 8; label = "厚甲守勢"
				1: damage = 10; hits = 1; label = "沉肩撞擊"
				2: block = 12; label = "重整護甲"
				3: damage = 12; hits = 1; label = "重甲突進"
		"charging":
			match turn % 3:
				0: block = 3; label = "蓄勢提氣"
				1: damage = 18; hits = 1; label = "聚力重擊"
				2: damage = 5; hits = 1; label = "收招試探"
		"counter":
			match turn % 4:
				0: counter = 5; block = 3; label = "待敵露隙"
				1: damage = 7; hits = 1; label = "回身出手"
				2: counter = 7; label = "以靜制動"
				3: damage = 10; hits = 1; label = "趁隙追擊"
		_:
			match turn % 4:
				0: damage = 3; hits = 3; label = "連環三試"
				1: block = 8; counter = 5; label = "守中問招"
				2: block = 3; label = "歸元蓄勢"
				3: damage = 16; hits = 1; label = "破勢重劍"
			if enemy.stage == 2:
				if hits > 0: damage += 2
				if block > 0: block += 2
				label = "二式 · " + label
	var parts: Array[String] = []
	if hits > 0: parts.append("%d%s傷害" % [damage, "×%d" % hits if hits > 1 else ""])
	if counter > 0: parts.append("本回合反制 %d（一次）" % counter)
	if block > 0: parts.append("結束時 +%d 防護" % block)
	return {"kind": "counter" if counter > 0 else ("guard" if hits == 0 else "attack"),
		"label": label + " · " + "；".join(parts), "damage": damage, "display_damage": damage, "hits": hits, "block": block, "counter_damage": counter}

static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= low and float(value) <= high

static func _validate_stats(stats: Dictionary) -> Dictionary:
	if not stats.get("attributes") is Dictionary: return _failure("缺少六項人物屬性。")
	var total := 0
	for key in ATTRIBUTES:
		if not _integer(stats.attributes.get(key), 2, 8): return _failure("人物屬性必須介於二至八。")
		total += int(stats.attributes[key])
	if total != 30: return _failure("六項人物屬性總和必須為三十。")
	var weapon: Variant = stats.get("weapon", "sword")
	var inner: Variant = stats.get("inner", "guiyuan")
	if not weapon is String or weapon not in Cards.WEAPONS: return _failure("兵器資料無效。")
	if not inner is String or inner not in Cards.INNERS: return _failure("內功資料無效。")
	var deck_check := Cards.validate_deck(stats.get("deck"), Cards.CARDS.keys(), weapon)
	if not deck_check.ok: return deck_check
	if stats.get("origin") not in ["herbalist", "courier", "performer"]: return _failure("出身資料無效。")
	if not _integer(stats.get("medicine", 0), 0, 999) or not _integer(stats.get("seed", 1), 0, 2147483647): return _failure("藥物或隨機種子資料無效。")
	if not _integer(stats.get("exam_aid", 0), 0, 3): return _failure("考核支援資料無效。")
	if stats.get("encounter_variant", "") not in ["", "flurry", "armored", "charging", "counter"]: return _failure("遭遇變體無效。")
	var refinements: Variant = stats.get("refinements", {})
	if not refinements is Dictionary or refinements.size() > 3: return _failure("精修分支資料無效。")
	for id in refinements:
		if id not in Cards.REFINABLE or refinements[id] not in ["stable", "specialist"]: return _failure("精修分支資料無效。")
	var upgraded: Variant = stats.get("upgraded_cards", refinements.keys())
	if not upgraded is Array or upgraded.size() > 3: return _failure("精修解鎖資料無效。")
	var seen: Array = []
	for id in upgraded:
		if not id is String or id not in Cards.REFINABLE or id in seen: return _failure("精修招式無效或重複。")
		seen.append(id)
	for id in refinements:
		if id not in upgraded: return _failure("尚未解鎖這項精修。")
	return {"ok": true, "message": "戰鬥資料可用。"}

static func _fixed_stats(stats: Dictionary) -> Dictionary:
	var attrs: Dictionary = {}
	for key in ATTRIBUTES: attrs[key] = int(stats.attributes[key])
	var refinements: Dictionary = stats.get("refinements", {}).duplicate(true)
	return {"attributes": attrs, "deck": stats.deck.duplicate(), "refinements": refinements,
		"weapon": str(stats.get("weapon", "sword")), "inner": str(stats.get("inner", "guiyuan")),
		"upgraded_cards": stats.get("upgraded_cards", refinements.keys()).duplicate(),
		"medicine": int(stats.get("medicine", 0)), "origin": str(stats.origin), "seed": int(stats.get("seed", 1)),
		"exam_aid": int(stats.get("exam_aid", 0)), "encounter_variant": str(stats.get("encounter_variant", ""))}

static func validate_snapshot(saved: Variant, mode: String = "", stats: Dictionary = {}) -> Dictionary:
	if not saved is Dictionary or saved.is_empty(): return _failure("戰鬥快照遺失。")
	if not _json_safe(saved): return _failure("戰鬥快照含有不可儲存的資料。")
	# JSON parses whole numbers as floats. Normalize a defensive copy before
	# membership checks; do not mutate a caller's checkpoint while validating.
	saved = _normalise_json(saved)
	if saved.get("version") != VERSION or saved.get("mode") not in MODES or (not mode.is_empty() and saved.mode != mode): return _failure("戰鬥快照版本或場次不符。")
	if not saved.get("stats") is Dictionary: return _failure("戰鬥快照缺少固定人物資料。")
	var checked := _validate_stats(saved.stats)
	if not checked.ok: return checked
	var fixed := _fixed_stats(saved.stats)
	if not stats.is_empty():
		checked = _validate_stats(stats)
		if not checked.ok: return checked
		if not _same(fixed, _fixed_stats(stats)): return _failure("戰鬥快照不屬於這次鎖定的配招、內功或種子。")
	var max_hp: int = 52 + int(fixed.attributes.constitution) * 3
	for key in ["seed", "rng_state"]:
		if not _integer(saved.get(key), 0, 2147483647): return _failure("隨機狀態損壞。")
	if saved.seed != fixed.seed or saved.get("max_hp") != max_hp: return _failure("人物上限或種子已改動。")
	var ranges := {"turn": [1, MAX_TURNS], "hp": [0, max_hp], "block": [0, 500], "qi": [0, 20],
		"momentum": [0, 3], "momentum_gained": [0, 2], "momentum_generated": [0, MAX_TURNS * 2], "momentum_spent": [0, MAX_TURNS * 2],
		"medicine_used": [0, mini(1, int(fixed.medicine))], "retaliation": [0, 6],
		"hits": [0, 10000], "damage_taken": [0, 100000], "cards_played": [0, 10000],
		"boosts_used": [0, 10000], "retains_used": [0, MAX_TURNS], "next_effect_id": [1, 10001]}
	for key in ranges:
		if not _integer(saved.get(key), int(ranges[key][0]), int(ranges[key][1])): return _failure("戰鬥數值損壞：" + key)
	for key in ["medicine_used_this_turn", "mulligan_used", "first_attack_used", "first_block_used", "shouzhong_triggered", "xingyun_gain_used", "xingyun_draw_used", "guiyuan_gain_used", "retaliation_used"]:
		if not saved.get(key) is bool: return _failure("戰鬥旗標損壞：" + key)
	if saved.medicine_used_this_turn and saved.medicine_used == 0: return _failure("用藥旗標與庫存不符。")
	if saved.get("last_paid_type") not in ["", "attack", "guard", "change"]: return _failure("接招紀錄無效。")
	if saved.boosts_used > saved.cards_played or saved.retains_used > saved.turn: return _failure("出牌或留牌紀錄不符。")
	if saved.momentum_generated < saved.momentum_gained or saved.momentum_spent > saved.momentum_generated: return _failure("產勢與耗勢紀錄不符。")
	if saved.get("phase") not in ["mulligan", "player", "choice", "won", "lost"]: return _failure("戰鬥階段損壞。")
	if saved.phase not in ["won", "lost"] and saved.momentum != saved.momentum_generated - saved.momentum_spent: return _failure("勢不守恆。")
	if saved.phase in ["won", "lost"] and saved.momentum != 0: return _failure("戰鬥已結束卻仍保留勢。")
	var actual: Dictionary = {}
	var expected: Dictionary = {}
	for id in fixed.deck: expected[id] = int(expected.get(id, 0)) + 1
	for pile in ["hand", "draw_pile", "discard_pile", "exhaust_pile", "in_play"]:
		if not saved.get(pile) is Array or saved[pile].size() > (1 if pile == "in_play" else 10): return _failure("牌堆資料損壞。")
		for id in saved[pile]:
			if not id is String or not Cards.has(id): return _failure("牌堆含未知招式。")
			if pile == "exhaust_pile" and not Cards.card(id).get("exhaust", false): return _failure("不可除外的招式被移入除外堆。")
			actual[id] = int(actual.get(id, 0)) + 1
	if actual != expected: return _failure("牌堆不守恆，不能繼續此快照。")
	if not saved.get("pending_choice") is Dictionary: return _failure("待選牌資料無效。")
	if saved.phase == "choice":
		var choice: Dictionary = saved.pending_choice
		if saved.in_play.size() != 1 or choice.get("kind") != "cycle" or choice.get("card_id") != saved.in_play[0] or not choice.get("empowered") is bool:
			return _failure("待施展的換牌招式不符。")
		var c := Cards.card(str(choice.card_id), str(fixed.refinements.get(choice.card_id, "")), bool(choice.empowered))
		if c.is_empty() or int(c.get("cycle_limit", 0)) <= 0: return _failure("這項招式不能換牌。")
		for key in ["max_count", "paid_qi", "paid_momentum"]:
			if not _integer(choice.get(key), 0, 3): return _failure("換牌費用或數量無效。")
		if choice.max_count != c.cycle_limit or choice.paid_qi != c.cost or choice.paid_momentum != c.momentum_cost or choice.get("type") != c.type:
			return _failure("待選牌的費用或招路已變更。")
		if not _integer(choice.get("target"), 0, 2) or saved.cards_played == 0 or not saved.first_block_used: return _failure("待選牌的目標或結算旗標無效。")
	elif not saved.pending_choice.is_empty() or not saved.in_play.is_empty(): return _failure("沒有待選牌卻殘留施展中的招式。")
	var foes := _make_enemies(str(saved.mode), int(fixed.exam_aid), str(fixed.encounter_variant))
	if not saved.get("enemies") is Array or saved.enemies.size() != foes.size(): return _failure("對手資料損壞。")
	var alive := 0
	for i in range(foes.size()):
		var enemy: Variant = saved.enemies[i]
		if not enemy is Dictionary: return _failure("對手資料損壞。")
		for key in ["id", "kind", "archetype", "name", "max_hp"]:
			if enemy.get(key) != foes[i][key]: return _failure("對手身分或氣血上限不符。")
		for key in ["hp", "block", "weak", "vulnerable", "intent_index", "stage"]:
			var maximum: int = int(enemy.max_hp) if key == "hp" else (MAX_TURNS + 2 if key == "intent_index" else 200)
			if not _integer(enemy.get(key), 0, maximum): return _failure("對手狀態損壞。")
		if not enemy.get("counter_used") is bool or enemy.stage not in [1, 2] or (enemy.archetype != "boss" and enemy.stage != 1): return _failure("對手架勢旗標損壞。")
		if enemy.weak != 0 or enemy.vulnerable != 0: return _failure("本驗證牌池沒有這項狀態來源。")
		if enemy.stage == 2 and enemy.hp * 2 > enemy.max_hp: return _failure("頭目階段與氣血不符。")
		if enemy.hp > 0: alive += 1
		# Derive using the latched stage, not current HP: damage never changes a
		# publicly promised intention midway through the player's turn.
		if not _same(enemy.get("intent"), _intent(enemy, str(saved.mode))): return _failure("對手意圖與回合架勢不符。")
	if saved.phase == "choice" and saved.pending_choice.target >= foes.size(): return _failure("待選牌目標超出對手數量。")
	if not saved.get("delayed") is Array or saved.delayed.size() > 50: return _failure("延遲招式資料無效。")
	var effect_ids: Array = []
	for effect in saved.delayed:
		if not effect is Dictionary or effect.get("source") != "hidden_needle" or "hidden_needle" not in fixed.deck or not effect.get("empowered") is bool:
			return _failure("伏針來源無效。")
		if not _integer(effect.get("id"), 1, int(saved.next_effect_id) - 1) or effect.id in effect_ids: return _failure("延遲招式編號重複或無效。")
		effect_ids.append(effect.id)
		if not _integer(effect.get("target"), 0, foes.size() - 1) or effect.get("due_turn") != saved.turn + 1: return _failure("伏針目標或時機無效。")
		var c := Cards.card("hidden_needle", "", bool(effect.empowered))
		if effect.get("amount") != c.delayed_damage: return _failure("伏針傷害已改動。")
	if saved.next_effect_id - 1 > saved.cards_played or saved.delayed.size() > saved.cards_played: return _failure("伏針次數與出牌紀錄不符。")
	if saved.phase == "won" and (alive != 0 or saved.hp <= 0): return _failure("勝負結果不符。")
	if saved.phase in ["player", "mulligan", "choice"] and (alive == 0 or saved.hp <= 0): return _failure("未結算的勝負狀態無效。")
	if saved.phase == "lost" and saved.hp > 0 and saved.turn != MAX_TURNS: return _failure("落敗結果不符。")
	if saved.phase in ["won", "lost"] and not saved.delayed.is_empty(): return _failure("終局仍有待發招式。")
	if saved.phase == "mulligan" and (saved.turn != 1 or saved.mulligan_used or saved.cards_played != 0 or saved.medicine_used != 0 or saved.hand.size() != 5 or saved.momentum != 0): return _failure("換牌階段無效。")
	if saved.phase != "mulligan" and not saved.mulligan_used: return _failure("尚未確認起手。")
	if not saved.get("log") is Array or saved.log.size() > 32 or not saved.get("last_events") is Array or saved.last_events.size() > 128: return _failure("戰鬥紀錄損壞。")
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
		if value.size() > 128: return false
		for item in value:
			if not _json_safe(item, depth + 1): return false
		return true
	if value is Dictionary:
		if value.size() > 100: return false
		for key in value:
			if not (key is String or key is StringName) or not _json_safe(value[key], depth + 1): return false
		return true
	return false
