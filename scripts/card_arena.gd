class_name WeiyuanCardArena
extends Node2D
## Fixed-position card encounter. All rules, RNG and rewards live in CardBattle.

signal finished(won: bool, report: Dictionary)
signal status_changed(value: Dictionary)
signal changed

const Battle = preload("res://scripts/card_battle.gd")
const Cards = preload("res://scripts/card_catalog.gd")
const Art = preload("res://scripts/art.gd")
const UI = preload("res://scripts/card_ui.gd")
const SIZE = Vector2(1080, 640)
const PAGE_SIZE = 5
const HERO_FOOT = Vector2(166, 250)
const CLIP_TIME = 0.28

var battle = Battle.new()
var mode: String = "practice"
var stats: Dictionary = {}
var action_buttons: Dictionary = {}
var restore_error: String = ""
var selected_card: int = -1
var selected_target: int = 0
var mulligan_selection: Array = []
var retained_index: int = -1
var cycle_selection: Array = []
var last_report: Dictionary = {}

var _configured: bool = false
var _input_enabled: bool = true
var _result_emitted: bool = false
var _generation: int = 0
var _page: int = 0
var _panel: String = ""
var _pile_tab: String = "draw"
var _message: String = ""
var _ui: Control
var _sound: AudioStreamPlayer
var _visual_age: float = 0.0
var _visual_kind: String = ""
var _visual_target: int = 0
var _finish_remaining: float = 0.0
var _cached_status: Dictionary = {}


func _ready() -> void:
	_sound = AudioStreamPlayer.new()
	_sound.volume_db = -23.0
	if ResourceLoader.exists("res://assets/audio/tap.wav"):
		_sound.stream = load("res://assets/audio/tap.wav")
	add_child(_sound)
	_refresh()


func configure(encounter_mode: String, hero_stats: Dictionary, restore: Dictionary = {}) -> Dictionary:
	_generation += 1
	mode = encounter_mode
	stats = hero_stats.duplicate(true)
	_configured = false
	_result_emitted = false
	_visual_age = 0.0
	_finish_remaining = 0.0
	restore_error = ""
	last_report.clear()
	selected_card = -1
	selected_target = 0
	mulligan_selection.clear()
	retained_index = -1
	cycle_selection.clear()
	_page = 0
	_panel = ""
	_pile_tab = "draw"
	_message = ""
	var model_restore: Dictionary = restore.duplicate(true)
	var saved_view: Variant = model_restore.get("_view", {})
	model_restore.erase("_view")
	if not restore.is_empty() and model_restore.is_empty():
		restore_error = "戰鬥快照只有介面資料，缺少原來的回合。"
		_refresh()
		status_changed.emit(status())
		return {"ok": false, "message": restore_error}
	var result: Dictionary = battle.configure(encounter_mode, hero_stats, model_restore)
	if not bool(result.get("ok", false)):
		restore_error = str(result.get("message", "無法還原這場對決。"))
		_refresh()
		status_changed.emit(status())
		return result
	_configured = true
	if saved_view is Dictionary:
		_restore_view(saved_view)
	_refresh()
	status_changed.emit(status())
	if bool(_cached_status.get("resolved", false)):
		call_deferred("_emit_result", _generation)
	return result


func set_input_enabled(value: bool) -> void:
	_input_enabled = value
	if is_instance_valid(_sound):
		_sound.stream_paused = not value
	_refresh()


func snapshot() -> Dictionary:
	if not _configured:
		return {}
	var result: Dictionary = battle.snapshot()
	result["_view"] = view_state()
	return result


func status() -> Dictionary:
	if not _configured:
		return {"ready": false, "resolved": false, "error": restore_error, "restore_error": restore_error, "phase": "error"}
	var result: Dictionary = battle.status()
	result["ready"] = _input_enabled and _panel.is_empty() and not bool(result.get("resolved", false))
	result["restore_error"] = restore_error
	result["selected_card"] = selected_card
	result["selected_target"] = selected_target
	result["retained_index"] = retained_index
	result["cycle_selection"] = cycle_selection.duplicate()
	return result


func report() -> Dictionary:
	return battle.report() if _configured else {}


func view_state() -> Dictionary:
	return {"selected_card": selected_card, "selected_target": selected_target, "mulligan_selection": mulligan_selection.duplicate(), "retained_index": retained_index, "cycle_selection": cycle_selection.duplicate(), "page": _page, "panel": _panel, "pile_tab": _pile_tab}


func _restore_view(value: Dictionary) -> void:
	var current: Dictionary = battle.status()
	var hand: Array = current.get("hand", [])
	selected_card = clampi(_view_integer(value.get("selected_card"), -1), -1, hand.size() - 1)
	selected_target = clampi(_view_integer(value.get("selected_target"), 0), 0, maxi(0, current.get("enemies", []).size() - 1))
	_page = clampi(_view_integer(value.get("page"), 0), 0, maxi(0, (hand.size() - 1) / PAGE_SIZE))
	_panel = str(value.get("panel", "")) if value.get("panel", "") in ["", "deck", "rules"] else ""
	_pile_tab = str(value.get("pile_tab", "draw")) if value.get("pile_tab", "draw") in ["draw", "discard", "exhaust", "hand"] else "draw"
	retained_index = clampi(_view_integer(value.get("retained_index"), -1), -1, hand.size() - 1) if current.get("phase", "") in ["player", "choice"] else -1
	if value.get("cycle_selection", []) is Array and current.get("phase", "") == "choice":
		var maximum: int = int(current.get("pending_choice", {}).get("max_count", 0))
		for raw in value.cycle_selection:
			if (raw is int or raw is float) and is_finite(float(raw)) and float(raw) == float(int(raw)) and int(raw) >= 0 and int(raw) < hand.size() and int(raw) not in cycle_selection and cycle_selection.size() < maximum:
				cycle_selection.append(int(raw))
	if value.get("mulligan_selection", []) is Array and current.get("phase", "") == "mulligan":
		for raw in value.get("mulligan_selection", []):
			if (raw is int or raw is float) and int(raw) >= 0 and int(raw) < hand.size() and int(raw) not in mulligan_selection and mulligan_selection.size() < int(current.get("mulligan_limit", 0)):
				mulligan_selection.append(int(raw))


func _view_integer(value: Variant, fallback: int) -> int:
	return int(value) if (value is int or value is float) and is_finite(float(value)) else fallback


func select_card(index: int) -> bool:
	if not _can_act(): return false
	var current: Dictionary = battle.status()
	var hand: Array = current.get("hand", [])
	if index < 0 or index >= hand.size(): return false
	if current.phase == "mulligan":
		if index in mulligan_selection:
			mulligan_selection.erase(index)
		elif mulligan_selection.size() < int(current.get("mulligan_limit", 0)):
			mulligan_selection.append(index)
		else:
			_message = "已選滿可換張數；再點已選牌可取消。"
			_refresh()
			return false
	elif current.phase == "choice":
		if index in cycle_selection:
			cycle_selection.erase(index)
		elif cycle_selection.size() < int(current.get("pending_choice", {}).get("max_count", 0)):
			cycle_selection.append(index)
		else:
			_message = "已選滿可換出的張數；再點已選牌可取消。"
			_refresh()
			return false
	elif current.phase == "player":
		selected_card = -1 if selected_card == index else index
		_message = "選擇普通施展或運勁；點對手可更換目標。" if selected_card >= 0 else ""
	else:
		return false
	_notify_view()
	return true


func select_target(index: int) -> bool:
	if not _can_act() or battle.status().get("phase", "") != "player": return false
	if index not in _living_targets(battle.status()): return false
	selected_target = index
	_notify_view()
	return true


func play_selected(empowered: bool = false) -> bool:
	if not _can_act() or battle.status().get("phase", "") != "player": return false
	var current: Dictionary = battle.status()
	if selected_card < 0 or selected_card >= current.get("hand", []).size(): return false
	return _play(selected_card, selected_target, empowered)


func toggle_retain(index: int) -> bool:
	if not _can_act() or battle.status().get("phase", "") != "player": return false
	if index < 0 or index >= battle.status().get("hand", []).size(): return false
	retained_index = -1 if retained_index == index else index
	_message = "下回合會補至五張；留下這張，就少抽一張新牌。" if retained_index >= 0 else "已取消留牌。"
	_notify_view()
	return true


func _retain_selected() -> void:
	if selected_card >= 0: toggle_retain(selected_card)


func confirm_cycle(indices: Array = []) -> bool:
	if not _can_act() or battle.status().get("phase", "") != "choice": return false
	var chosen: Array = indices.duplicate()
	var result: Dictionary = battle.resolve_choice(chosen)
	if bool(result.get("ok", false)):
		if retained_index in chosen:
			retained_index = -1
		elif retained_index >= 0:
			var earlier = 0
			for index in chosen:
				if int(index) < retained_index: earlier += 1
			retained_index -= earlier
	return _apply(result, "draw")


func _confirm_cycle_selection() -> void:
	confirm_cycle(cycle_selection)


func confirm_mulligan() -> bool:
	if not _can_act() or battle.status().get("phase", "") != "mulligan":
		return false
	return _apply(battle.mulligan(mulligan_selection.duplicate()), "draw")


func skip_mulligan() -> bool:
	if not _can_act():
		return false
	return _apply(battle.skip_mulligan(), "draw")


func end_turn() -> bool:
	if not _can_act():
		return false
	if battle.status().get("phase", "") != "player": return false
	var result: Dictionary = battle.end_turn(retained_index)
	if bool(result.get("ok", false)): retained_index = -1
	return _apply(result, "enemy")


func use_medicine() -> bool:
	if not _can_act():
		return false
	return _apply(battle.use_medicine(), "heal")


func cancel_selection() -> void:
	if not _can_act():
		return
	selected_card = -1
	_message = ""
	_notify_view()


func open_panel(kind: String) -> bool:
	if not _configured or not _input_enabled or kind not in ["deck", "rules"]:
		return false
	_panel = kind
	_notify_view()
	return true


func close_panel() -> bool:
	if not _input_enabled or _panel.is_empty():
		return false
	_panel = ""
	_notify_view()
	return true


func _set_pile(kind: String) -> void:
	if not _input_enabled or _panel != "deck":
		return
	_pile_tab = kind
	_notify_view()


func _change_page(direction: int) -> void:
	if not _can_act():
		return
	var count: int = battle.status().get("hand", []).size()
	_page = clampi(_page + direction, 0, maxi(0, (count - 1) / PAGE_SIZE))
	_notify_view()


func _play(index: int, target: int, empowered: bool = false) -> bool:
	_visual_target = target
	var current: Dictionary = battle.status()
	var card: Dictionary = _card(str(current.hand[index]), current, empowered)
	if card.is_empty(): return false
	var result: Dictionary = battle.play_card(index, target, empowered)
	if bool(result.get("ok", false)):
		if retained_index == index:
			retained_index = -1
		elif retained_index > index:
			retained_index -= 1
	return _apply(result, "attack" if card.type == "attack" else "skill")


func _apply(result: Dictionary, effect: String) -> bool:
	_message = str(result.get("message", ""))
	if not bool(result.get("ok", false)):
		_refresh()
		return false
	selected_card = -1
	mulligan_selection.clear()
	cycle_selection.clear()
	_visual_kind = effect
	_visual_age = CLIP_TIME
	if is_instance_valid(_sound) and _sound.stream != null:
		_sound.play()
	_refresh()
	if bool(_cached_status.get("resolved", false)):
		last_report = battle.report()
		_finish_remaining = CLIP_TIME
	status_changed.emit(status())
	changed.emit()
	return true


func _notify_view() -> void:
	_refresh()
	status_changed.emit(status())
	changed.emit()


func _can_act() -> bool:
	return _configured and _input_enabled and _panel.is_empty() and not bool(battle.status().get("resolved", false))


func _process(delta: float) -> void:
	advance_presentation(delta)


func advance_presentation(delta: float) -> void:
	if not _configured or not _input_enabled or not _panel.is_empty() or delta <= 0.0:
		return
	_visual_age = maxf(0.0, _visual_age - delta)
	_finish_remaining = maxf(0.0, _finish_remaining - delta)
	if _visual_age > 0.0 or _visual_kind != "":
		queue_redraw()
		if _visual_age == 0.0:
			_visual_kind = ""
	if bool(_cached_status.get("resolved", false)) and not _result_emitted and _finish_remaining <= 0.0:
		_emit_result(_generation)


func _emit_result(generation: int) -> void:
	if generation != _generation or not _configured or not _input_enabled or not _panel.is_empty() or _result_emitted or not bool(battle.status().get("resolved", false)):
		return
	_result_emitted = true
	last_report = battle.report()
	finished.emit(bool(battle.status().get("won", false)), last_report.duplicate(true))


func _card(id: String, current: Dictionary, empowered: bool = false) -> Dictionary:
	var refinements: Dictionary = current.get("refinements", current.get("stats", {}).get("refinements", stats.get("refinements", {})))
	var card: Dictionary = Cards.card(id, str(refinements.get(id, "")), empowered)
	if card.is_empty(): return card
	var art_ids = {"sword": "shen", "palm": "tao", "dart": "lu", "footwork": "courier"}
	card["art_id"] = art_ids.get(str(card.get("discipline", "basic")), str(stats.get("origin", "courier")))
	return card


func _preview(index: int, empowered: bool = false) -> Dictionary:
	var current: Dictionary = battle.status()
	var living: Array = _living_targets(current)
	var target: int = selected_target if selected_target in living else (int(living[0]) if not living.is_empty() else 0)
	return battle.preview_card(index, target, empowered)


func _hand_card(index: int, current: Dictionary) -> Dictionary:
	var card: Dictionary = _card(str(current.hand[index]), current)
	card["retained"] = index == retained_index
	if current.get("phase", "") == "choice":
		card["selection_label"] = "準備換出" if index in cycle_selection else "點選換出"
	if current.get("phase", "") != "player": return card
	var preview: Dictionary = _preview(index)
	card["preview_tooltip"] = "\n\n普通施展預覽\n" + str(preview.get("description", preview.get("message", "")))
	if int(card.get("boost_cost", 0)) > 0:
		var boosted: Dictionary = _preview(index, true)
		card.preview_tooltip += "\n\n運勁預覽\n" + str(boosted.get("description", boosted.get("message", "")))
	return card


func _living_targets(current: Dictionary) -> Array:
	var result: Array = []
	var enemies: Array = current.get("enemies", [])
	for index in range(enemies.size()):
		if int(enemies[index].get("hp", 0)) > 0:
			result.append(index)
	return result


func _enemy_foot(index: int, count: int) -> Vector2:
	return Vector2(790 if count == 1 else (610 + index * 230 if count == 2 else 530 + index * 180), 250)


func _refresh() -> void:
	if not is_inside_tree(): return
	if is_instance_valid(_ui):
		remove_child(_ui)
		_ui.queue_free()
	action_buttons.clear()
	_ui = Control.new()
	_ui.size = SIZE
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)
	_cached_status = battle.status() if _configured else {}
	if not _configured:
		UI.label(_ui, "對決暫時無法開啟", Vector2(38, 36), Vector2(1000, 60), 30, UI.INK, true)
		UI.label(_ui, restore_error if not restore_error.is_empty() else "正在準備對決。", Vector2(38, 122), Vector2(1000, 200), 21)
		queue_redraw()
		return
	var current: Dictionary = _cached_status
	var phase: String = str(current.get("phase", "mulligan"))
	var names = {"practice": "竹影試招", "spar": "同門對練", "grove": "青篁遇敵", "ridge": "古道交鋒", "exam": "入山考核", "flurry": "連擊試戰", "armored": "重甲試戰", "charging": "蓄勢試戰", "counter": "反制試戰"}
	UI.label(_ui, names.get(mode, "江湖對決"), Vector2(22, 9), Vector2(290, 40), 27, UI.INK, true)
	var inner: String = str(current.get("inner", current.get("stats", {}).get("inner", stats.get("inner", "guiyuan"))))
	var weapon: String = str(current.get("weapon", current.get("stats", {}).get("weapon", stats.get("weapon", "sword"))))
	var inner_button: Button = _button("inner", "%s · %s" % [Cards.INNERS.get(inner, {}).get("name", inner), Cards.WEAPONS.get(weapon, {}).get("name", weapon)], Vector2(320, 10), Vector2(400, 35), open_panel.bind("rules"), true, false, true)
	inner_button.tooltip_text = str(Cards.INNERS.get(inner, {}).get("description", ""))
	var title: String = "起手調整" if phase == "mulligan" else ("勝負已定" if current.get("resolved", false) else ("換招選擇" if phase == "choice" else "第 %d 回合" % int(current.get("turn", 1))))
	UI.label(_ui, title, Vector2(820, 16), Vector2(230, 31), 21, UI.JADE)
	_build_fighters(current)
	_build_preview(current)
	UI.label(_ui, "真氣 %d　勢 %d / 3" % [int(current.get("qi", 0)), int(current.get("momentum", 0))], Vector2(20, 265), Vector2(300, 34), 22, UI.JADE, true)
	var gained: Label = UI.label(_ui, "本輪蓄勢 %d / 2" % int(current.get("momentum_gained", 0)), Vector2(325, 269), Vector2(190, 27), 16, UI.MUTED)
	gained.name = "MomentumBudget"
	var hint: String = _message if not _message.is_empty() else "先看意圖，選牌後決定普通或運勁。"
	if phase == "mulligan": hint = "點選要換的牌：%d / %d 張" % [mulligan_selection.size(), current.get("mulligan_limit", 0)]
	if phase == "choice": hint = "可換出 %d 張：已選 %d；也可略過。" % [int(current.get("pending_choice", {}).get("max_count", 0)), cycle_selection.size()]
	var hint_label = UI.label(_ui, hint, Vector2(520, 268), Vector2(490, 31), 15, UI.MUTED)
	hint_label.clip_text = true
	hint_label.tooltip_text = hint
	var hand: Array = current.get("hand", [])
	_page = clampi(_page, 0, maxi(0, (hand.size() - 1) / PAGE_SIZE))
	if hand.size() > PAGE_SIZE:
		_button("hand_previous", "<", Vector2(1009, 266), Vector2(25, 32), _change_page.bind(-1), _page > 0)
		_button("hand_next", ">", Vector2(1037, 266), Vector2(25, 32), _change_page.bind(1), (_page + 1) * PAGE_SIZE < hand.size())
	for slot in range(PAGE_SIZE):
		var index: int = _page * PAGE_SIZE + slot
		if index >= hand.size(): continue
		var card: Dictionary = _hand_card(index, current)
		var selected: bool = index in mulligan_selection if phase == "mulligan" else (index in cycle_selection if phase == "choice" else index == selected_card)
		var button: Button = UI.card_button(_ui, card, Vector2(18 + slot * 210, 308), Vector2(202, 196), select_card.bind(index), selected)
		button.name = "card_%d" % index
		action_buttons[button.name] = button
		button.disabled = not _can_act()
		if button.disabled: button.modulate = Color(0.86, 0.88, 0.83)
	_build_actions(current)
	_button("deck", "牌堆 · %d" % current.get("draw_count", 0), Vector2(18, 591), Vector2(145, 38), open_panel.bind("deck"), true, false, true)
	_button("rules", "規則／內功", Vector2(175, 591), Vector2(145, 38), open_panel.bind("rules"), true, false, true)
	if phase == "mulligan":
		_button("mulligan_skip", "保留起手牌", Vector2(660, 591), Vector2(190, 38), skip_mulligan)
		_button("mulligan_confirm", "換牌並開戰", Vector2(865, 591), Vector2(195, 38), confirm_mulligan, not mulligan_selection.is_empty(), true)
	else:
		_button("medicine", "用藥 · 1真氣" if int(current.get("medicine_used", 0)) == 0 else "本場已用藥", Vector2(660, 591), Vector2(190, 38), use_medicine, phase == "player" and bool(current.get("can_use_medicine", false)))
		_button("end_turn", "結束回合", Vector2(865, 591), Vector2(195, 38), end_turn, phase == "player" and bool(current.get("can_end_turn", true)), true)
		if hand.size() > PAGE_SIZE:
			UI.label(_ui, "手牌第 %d / %d 頁" % [_page + 1, ceili(hand.size() / 5.0)], Vector2(340, 599), Vector2(300, 27), 15, UI.MUTED)
	if not _panel.is_empty(): _build_panel(current)
	queue_redraw()


func _build_actions(current: Dictionary) -> void:
	var phase: String = str(current.get("phase", ""))
	if phase == "mulligan":
		UI.label(_ui, "這次換牌機會只在開場出現；點選後按「換牌並開戰」。", Vector2(22, 520), Vector2(1030, 48), 19, UI.JADE)
		return
	if phase == "choice":
		UI.label(_ui, "掠影步已支付費用並獲得防護；選擇換出的牌後，才完成這次施展。", Vector2(22, 510), Vector2(1030, 28), 16, UI.JADE)
		_button("cycle_confirm", "換出所選 %d 張" % cycle_selection.size(), Vector2(18, 544), Vector2(310, 36), _confirm_cycle_selection, not cycle_selection.is_empty(), true)
		_button("cycle_skip", "不換牌，完成施展", Vector2(334, 544), Vector2(310, 36), confirm_cycle.bind([]))
		UI.label(_ui, "此步也可暫停保存。", Vector2(665, 549), Vector2(380, 29), 16, UI.MUTED)
		return
	if bool(current.get("resolved", false)):
		UI.label(_ui, "這場交手已結束。", Vector2(22, 525), Vector2(1000, 50), 24, UI.JADE)
		return
	var hand: Array = current.get("hand", [])
	var selected: bool = selected_card >= 0 and selected_card < hand.size()
	var card: Dictionary = _card(str(hand[selected_card]), current) if selected else {}
	var target_name = "自己"
	if selected and card.get("target", "self") == "enemy":
		var living: Array = _living_targets(current)
		if selected_target not in living and not living.is_empty(): selected_target = int(living[0])
		if selected_target >= 0 and selected_target < current.get("enemies", []).size(): target_name = str(current.enemies[selected_target].get("name", "對手"))
	UI.label(_ui, "%s → %s" % [str(card.name), target_name] if selected else "點選手牌查看效果；按施展按鈕才會出招。", Vector2(22, 509), Vector2(620, 26), 16, UI.JADE)
	var retained_name = str(_card(str(hand[retained_index]), current).name) if retained_index >= 0 and retained_index < hand.size() else "未選"
	UI.label(_ui, "留牌：" + retained_name, Vector2(665, 509), Vector2(390, 26), 15, UI.MUTED)
	var normal: Dictionary = _preview(selected_card) if selected else {}
	var boost: Dictionary = _preview(selected_card, true) if selected and int(card.get("boost_cost", 0)) > 0 else {}
	var normal_text = "普通施展 · %d 真氣" % int(card.get("cost", 0)) if selected else "普通施展 · 先選牌"
	var boost_text = "運勁 · %d 真氣＋%d 勢" % [int(card.get("cost", 0)), int(card.get("boost_cost", 0))] if selected and int(card.get("boost_cost", 0)) > 0 else "此招沒有運勁版本"
	var normal_button = _button("play_normal", normal_text, Vector2(18, 539), Vector2(310, 41), play_selected.bind(false), selected and bool(normal.get("can_play", normal.get("ok", false))), true)
	var boost_button = _button("play_boost", boost_text, Vector2(334, 539), Vector2(310, 41), play_selected.bind(true), not boost.is_empty() and bool(boost.get("can_play", boost.get("ok", false))), true)
	normal_button.tooltip_text = str(normal.get("description", normal.get("message", "")))
	boost_button.tooltip_text = str(boost.get("description", boost.get("message", "")))
	_button("retain_selected", "取消這張留牌" if selected and retained_index == selected_card else "留到下回合", Vector2(660, 539), Vector2(190, 41), _retain_selected, selected)
	_button("selection_cancel", "取消選牌", Vector2(865, 539), Vector2(195, 41), cancel_selection, selected)


func _button(id: String, text: String, position: Vector2, size: Vector2, callback: Callable, enabled: bool = true, primary: bool = false, utility: bool = false, parent: Node = null) -> Button:
	var value: Button = UI.button(_ui if parent == null else parent, text, position, size, callback, primary)
	value.name = id
	value.disabled = not _input_enabled or not enabled or (not _panel.is_empty() and parent == null) or (not utility and bool(_cached_status.get("resolved", false)))
	action_buttons[id] = value
	return value


func _build_fighters(current: Dictionary) -> void:
	UI.label(_ui, str(stats.get("name", "無名少俠")), Vector2(28, 59), Vector2(330, 31), 22, UI.JADE, true)
	UI.label(_ui, "氣血 %d / %d　防護 %d" % [current.get("hp", 0), current.get("max_hp", 0), current.get("block", 0)], Vector2(28, 95), Vector2(380, 27), 17)
	var retaliation: int = int(current.get("retaliation", current.get("retaliation_damage", 0)))
	if retaliation > 0:
		var counter_label = UI.label(_ui, "待發反擊\n%d 傷害" % retaliation, Vector2(25, 153), Vector2(86, 54), 15, UI.JADE)
		counter_label.name = "RetaliationReady"
	var delayed: Array = current.get("delayed_effects", current.get("delayed", []))
	if not delayed.is_empty():
		var delayed_label = UI.label(_ui, "伏針待發\n%d 次" % delayed.size(), Vector2(25, 208), Vector2(86, 45), 14, UI.MUTED)
		delayed_label.name = "DelayedReady"
	var enemies: Array = current.get("enemies", [])
	for index in range(enemies.size()):
		var enemy: Dictionary = enemies[index]
		var foot: Vector2 = _enemy_foot(index, enemies.size())
		# Give a lone boss's longer phase/retaliation intent enough width above its pose.
		var target_width: float = 280 if enemies.size() == 1 else 210
		var button: Button = _button("target_%d" % index, "", Vector2(foot.x - target_width / 2.0, 57), Vector2(target_width, 199), select_target.bind(index), int(enemy.get("hp", 0)) > 0 and current.get("phase", "") == "player")
		button.add_theme_stylebox_override("normal", UI.style(Color(1, 1, 1, 0.01), UI.GOLD if selected_target == index else Color(1, 1, 1, 0), 2 if selected_card >= 0 and selected_target == index else 0))
		button.add_theme_stylebox_override("disabled", UI.style(Color(1, 1, 1, 0)))
		button.add_theme_stylebox_override("hover", UI.style(Color(0.87, 0.93, 0.82, 0.16), UI.GOLD, 2))
		var name_label = UI.label(button, str(enemy.get("name", "對手")), Vector2(3, 0), Vector2(target_width - 6, 28), 19, UI.INK, true)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var hp_label = UI.label(button, "%d / %d　護 %d" % [enemy.get("hp", 0), enemy.get("max_hp", 0), enemy.get("block", 0)], Vector2(3, 29), Vector2(target_width - 6, 24), 15)
		hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var intent: Dictionary = enemy.get("intent", {})
		var intent_text: String = str(intent.get("label", "觀察局勢")) if int(enemy.get("hp", 0)) > 0 else "已退場"
		var intent_label = UI.label(button, intent_text, Vector2(3, 53), Vector2(target_width - 6, 49), 15, Color("9a5548"))
		intent_label.name = "EnemyIntent"
		intent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.tooltip_text = intent_text


func _build_preview(current: Dictionary) -> void:
	if current.get("phase", "") != "player" or selected_card < 0 or selected_card >= current.get("hand", []).size(): return
	var card: Dictionary = _card(str(current.hand[selected_card]), current)
	var pane = Panel.new()
	pane.name = "EffectPreview"
	pane.position = Vector2(282, 65)
	pane.size = Vector2(228, 189)
	pane.add_theme_stylebox_override("panel", UI.style(Color("f8f1e5"), Color("d3c8a7")))
	_ui.add_child(pane)
	UI.label(pane, "實際效果預覽", Vector2(11, 5), Vector2(206, 25), 15, UI.JADE)
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(11, 33)
	scroll.size = Vector2(206, 146)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pane.add_child(scroll)
	var normal: Dictionary = _preview(selected_card)
	var text = "普通施展\n" + str(normal.get("description", normal.get("message", "")))
	if int(card.get("boost_cost", 0)) > 0:
		var boost: Dictionary = _preview(selected_card, true)
		text += "\n\n運勁 %d 勢\n" % int(card.boost_cost) + str(boost.get("description", boost.get("message", "")))
	var label = Label.new()
	label.name = "ModelPreview"
	label.add_theme_font_override("font", UI.FONT)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", UI.INK)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(185, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = text
	scroll.add_child(label)


func _build_panel(current: Dictionary) -> void:
	var veil = ColorRect.new()
	veil.size = SIZE
	veil.color = Color(0.13, 0.22, 0.18, 0.38)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	_ui.add_child(veil)
	var panel = Panel.new()
	panel.position = Vector2(86, 38)
	panel.size = Vector2(908, 568)
	panel.add_theme_stylebox_override("panel", UI.style(UI.PAPER, UI.GOLD, 2))
	_ui.add_child(panel)
	UI.label(panel, "對決規則" if _panel == "rules" else "牌堆一覽", Vector2(24, 18), Vector2(650, 44), 28, UI.JADE, true)
	_button("panel_close", "返回對決", Vector2(724, 20), Vector2(156, 42), close_panel, true, false, true, panel)
	if _panel == "rules":
		var inner: String = str(stats.get("inner", "guiyuan"))
		var rules = "【%s】\n%s\n\n每回合恢復 3 真氣，手牌補至 5 張。點牌選取，再選普通施展或運勁；懸停施展按鈕可看實際預覽。\n\n勢跨回合保留，上限 3；每輪最多獲得 2。運勁額外支付牌面指定的勢，先付款，再結算招式及內功回報。\n\n可留 1 張牌到下回合，佔五張手牌的一格。剩餘手牌棄掉，牌堆空時洗入棄牌；本場除外不再抽回。\n\n防護下回合開始清除；反擊每敵方回合最多一次。伏針下回合開始結算，目標死亡便取消。\n\n用藥消耗 1 真氣，每場最多一次，回復 20 氣血。閱讀與思考不推動回合。" % [Cards.INNERS.get(inner, {}).get("name", inner), Cards.INNERS.get(inner, {}).get("description", "")]
		var rule_scroll = ScrollContainer.new()
		rule_scroll.position = Vector2(28, 84)
		rule_scroll.size = Vector2(852, 458)
		rule_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		panel.add_child(rule_scroll)
		var rule_text = Label.new()
		rule_text.add_theme_font_override("font", UI.FONT)
		rule_text.add_theme_font_size_override("font_size", 18)
		rule_text.add_theme_color_override("font_color", UI.INK)
		rule_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rule_text.custom_minimum_size = Vector2(820, 0)
		rule_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rule_text.text = rules
		rule_scroll.add_child(rule_text)
		return
	var tabs = [["draw", "牌堆", current.get("draw_count", 0)], ["discard", "棄牌", current.get("discard_count", 0)], ["exhaust", "除外", current.get("exhaust_count", 0)], ["hand", "手牌", current.get("hand", []).size()]]
	for index in range(tabs.size()):
		var tab: Array = tabs[index]
		_button("pile_" + str(tab[0]), "%s · %d" % [tab[1], tab[2]], Vector2(26 + index * 218, 80), Vector2(204, 40), _set_pile.bind(str(tab[0])), true, _pile_tab == tab[0], true, panel)
	UI.label(panel, "依招式整理；不顯示抽牌順序。", Vector2(30, 134), Vector2(830, 28), 16, UI.MUTED)
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(26, 174)
	scroll.size = Vector2(854, 365)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	var counts: Dictionary = {}
	for id in _pile_cards(_pile_tab):
		counts[str(id)] = int(counts.get(str(id), 0)) + 1
	if counts.is_empty():
		var empty = Label.new()
		empty.text = "這裡暫時沒有牌。"
		empty.add_theme_font_override("font", UI.FONT)
		empty.add_theme_font_size_override("font_size", 19)
		empty.add_theme_color_override("font_color", UI.MUTED)
		list.add_child(empty)
	for id in counts:
		var card: Dictionary = _card(id, current)
		var entry = Label.new()
		entry.text = "%s × %d　｜　%d 真氣\n%s%s" % [card.get("name", id), counts[id], card.get("cost", 0), card.get("normal_description", card.get("description", "")), "\n運勁 %d 勢：%s" % [int(card.get("boost_cost", 0)), card.get("boost_description", "")] if int(card.get("boost_cost", 0)) > 0 else ""]
		entry.add_theme_font_override("font", UI.FONT)
		entry.add_theme_font_size_override("font_size", 18)
		entry.add_theme_color_override("font_color", UI.INK)
		entry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		entry.custom_minimum_size = Vector2(810, 68)
		list.add_child(entry)


func _pile_cards(kind: String) -> Array:
	var state: Dictionary = battle.snapshot()
	var value: Variant = state.get(kind + "_pile", state.get(kind, []))
	return value.duplicate() if value is Array else []


func _draw() -> void:
	draw_style_box(UI.style(Color("e8eadb"), Color("c7c9af")), Rect2(Vector2.ZERO, SIZE))
	var background: Texture2D = Art.location("grove" if mode == "grove" else ("ridge" if mode == "ridge" else "wangxi"))
	if background:
		draw_texture_rect(background, Rect2(0, 50, 1080, 208), false, Color(1, 1, 1, 0.25))
	draw_rect(Rect2(0, 258, 1080, 382), Color("eef0e2"))
	draw_line(Vector2(18, 258), Vector2(1062, 258), Color("c7ccb6"), 1)
	if not _configured:
		return
	var phase: float = _visual_age / CLIP_TIME
	var lunge: float = sin((1.0 - phase) * PI) * 18.0 if _visual_kind == "attack" and _visual_age > 0.0 else 0.0
	var hero_tint = Color("ffdbc7") if _visual_kind == "enemy" and _visual_age > 0.1 else Color.WHITE
	_draw_token(str(stats.get("origin", "courier")), HERO_FOOT + Vector2(lunge, 0), 124, hero_tint)
	var enemies: Array = _cached_status.get("enemies", [])
	for index in range(enemies.size()):
		var enemy: Dictionary = enemies[index]
		var tint = Color(0.52, 0.55, 0.5, 0.35) if int(enemy.get("hp", 0)) <= 0 else Color.WHITE
		if _visual_kind == "attack" and index == _visual_target and _visual_age > 0.08:
			tint = Color("ffe6ad")
		_draw_token(str(enemy.get("kind", "bandit")), _enemy_foot(index, enemies.size()), 91, tint)
	if _visual_age > 0.0 and _visual_kind == "attack" and not enemies.is_empty():
		var target: Vector2 = _enemy_foot(clampi(_visual_target, 0, enemies.size() - 1), enemies.size()) + Vector2(0, -45)
		var start: Vector2 = HERO_FOOT + Vector2(45, -50)
		var center: Vector2 = start.lerp(target, 1.0 - phase)
		draw_line(center - Vector2(35, -12), center + Vector2(35, -12), Color(0.92, 0.78, 0.44, phase), 4, true)
	if _visual_age > 0.0 and _visual_kind in ["heal", "skill"]:
		draw_arc(HERO_FOOT + Vector2(0, -45), 48 + (1 - phase) * 20, 0, TAU, 28, Color(0.35, 0.63, 0.47, phase), 3, true)


func _draw_token(id: String, foot: Vector2, height: float, tint: Color) -> void:
	var texture: Texture2D = Art.portrait(id)
	if texture == null:
		return
	draw_set_transform(foot, 0, Vector2(1, 0.22))
	draw_circle(Vector2.ZERO, 34, Color(0.13, 0.23, 0.18, 0.16 * tint.a))
	draw_set_transform(Vector2.ZERO)
	var width: float = texture.get_width() * height / texture.get_height()
	draw_texture_rect(texture, Rect2(foot - Vector2(width / 2.0, height), Vector2(width, height)), false, tint)
