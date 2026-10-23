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
const HERO_FOOT = Vector2(178, 292)
const CLIP_TIME = 0.28

var battle = Battle.new()
var mode: String = "practice"
var stats: Dictionary = {}
var action_buttons: Dictionary = {}
var restore_error: String = ""
var selected_card: int = -1
var selected_target: int = 0
var mulligan_selection: Array = []
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
	return result


func report() -> Dictionary:
	return battle.report() if _configured else {}


func view_state() -> Dictionary:
	return {"selected_card": selected_card, "selected_target": selected_target, "mulligan_selection": mulligan_selection.duplicate(), "page": _page, "panel": _panel, "pile_tab": _pile_tab}


func _restore_view(value: Dictionary) -> void:
	var current: Dictionary = battle.status()
	var hand: Array = current.get("hand", [])
	selected_card = clampi(_view_integer(value.get("selected_card"), -1), -1, hand.size() - 1)
	selected_target = clampi(_view_integer(value.get("selected_target"), 0), 0, maxi(0, current.get("enemies", []).size() - 1))
	_page = clampi(_view_integer(value.get("page"), 0), 0, maxi(0, (hand.size() - 1) / PAGE_SIZE))
	_panel = str(value.get("panel", "")) if value.get("panel", "") in ["", "deck", "rules"] else ""
	_pile_tab = str(value.get("pile_tab", "draw")) if value.get("pile_tab", "draw") in ["draw", "discard", "exhaust", "hand"] else "draw"
	if value.get("mulligan_selection", []) is Array and current.get("phase", "") == "mulligan":
		for raw in value.get("mulligan_selection", []):
			if (raw is int or raw is float) and int(raw) >= 0 and int(raw) < hand.size() and int(raw) not in mulligan_selection and mulligan_selection.size() < int(current.get("mulligan_limit", 0)):
				mulligan_selection.append(int(raw))


func _view_integer(value: Variant, fallback: int) -> int:
	return int(value) if (value is int or value is float) and is_finite(float(value)) else fallback


func select_card(index: int) -> bool:
	if not _can_act():
		return false
	var current: Dictionary = battle.status()
	var hand: Array = current.get("hand", [])
	if index < 0 or index >= hand.size():
		return false
	if current.phase == "mulligan":
		if index in mulligan_selection:
			mulligan_selection.erase(index)
		elif mulligan_selection.size() < int(current.get("mulligan_limit", 0)):
			mulligan_selection.append(index)
		else:
			_message = "已選滿可換張數；再點一次已選牌可取消。"
			_refresh()
			return false
		_notify_view()
		return true
	if current.phase != "player":
		return false
	var card: Dictionary = _card(str(hand[index]), current)
	if int(card.get("cost", 0)) > int(current.get("qi", 0)):
		_message = "真氣不足，先打出調息或結束回合。"
		_refresh()
		return false
	if selected_card == index:
		selected_card = -1
		_notify_view()
		return true
	if card.get("target", "self") != "enemy":
		return _play(index, selected_target)
	var living: Array = _living_targets(current)
	if living.size() == 1:
		return _play(index, int(living[0]))
	selected_card = index
	_message = "已選「%s」，點選一位對手施展。" % card.get("name", "招式")
	_notify_view()
	return true


func select_target(index: int) -> bool:
	if not _can_act():
		return false
	var current: Dictionary = battle.status()
	if index not in _living_targets(current):
		return false
	selected_target = index
	if selected_card >= 0 and current.get("phase", "") == "player":
		return _play(selected_card, index)
	_notify_view()
	return true


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
	return _apply(battle.end_turn(), "enemy")


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


func _play(index: int, target: int) -> bool:
	_visual_target = target
	var current: Dictionary = battle.status()
	var card: Dictionary = _card(str(current.hand[index]), current)
	return _apply(battle.play_card(index, target), "attack" if card.type == "attack" else "skill")


func _apply(result: Dictionary, effect: String) -> bool:
	_message = str(result.get("message", ""))
	if not bool(result.get("ok", false)):
		_refresh()
		return false
	selected_card = -1
	mulligan_selection.clear()
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


func _card(id: String, current: Dictionary) -> Dictionary:
	var card: Dictionary = Cards.card(id, id in current.get("upgraded_cards", []))
	var art_ids = {"zhaoling": "shen", "duyun": "lu", "event": "lin"}
	var event_ids = {"bridge_oath": "zhou", "letter_focus": "zhou", "old_ballad": "xiao", "mountain_echo": "lin", "herb_poultice": "tao", "stage_flourish": "xiao"}
	card["art_id"] = event_ids.get(id, art_ids.get(str(card.get("group", "basic")), str(stats.get("origin", "courier"))))
	return card


func _hand_card(index: int, current: Dictionary) -> Dictionary:
	var card: Dictionary = _card(str(current.hand[index]), current)
	var living: Array = _living_targets(current)
	var target: int = selected_target if selected_target in living else (int(living[0]) if not living.is_empty() else 0)
	var preview: Dictionary = battle.preview_card(index, target)
	if not bool(preview.get("ok", false)):
		return card
	var lines: PackedStringArray = UI.compact_description(card).split("\n")
	if card.has("damage") and not preview.get("damage", []).is_empty():
		var totals: Dictionary = {}
		var hits: Array[String] = []
		for hit in preview.damage:
			var total: int = int(hit.amount) + int(hit.blocked)
			totals[int(hit.target)] = int(totals.get(int(hit.target), 0)) + total
			hits.append(str(total))
		if card.get("all", false):
			hits.clear()
			for victim in totals: hits.append(str(totals[victim]))
		lines[0] = "本次 %s 傷害" % ("／" if card.get("all", false) else "＋").join(hits)
	for line in range(lines.size()):
		if lines[line].begins_with("獲得 "):
			lines[line] = "本次獲得 %d 防護" % int(preview.get("block", card.get("block", 0)))
		elif lines[line].ends_with(" 氣血"):
			lines[line] = "本次回復 %d 氣血" % int(preview.get("heal", card.get("heal", 0)))
	card["face_description"] = "\n".join(lines)
	card["preview_tooltip"] = "\n\n當前預覽（已計入屬性與狀態）\n" + str(preview.get("description", ""))
	return card


func _living_targets(current: Dictionary) -> Array:
	var result: Array = []
	var enemies: Array = current.get("enemies", [])
	for index in range(enemies.size()):
		if int(enemies[index].get("hp", 0)) > 0:
			result.append(index)
	return result


func _enemy_foot(index: int, count: int) -> Vector2:
	return Vector2(715 if count == 1 else (610 + index * 230 if count == 2 else 530 + index * 180), 292)


func _refresh() -> void:
	if not is_inside_tree():
		return
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
	var names = {"practice": "竹影試招", "spar": "同門對練", "grove": "青篁遇敵", "ridge": "古道交鋒", "exam": "入山考核"}
	UI.label(_ui, names.get(mode, "江湖對決"), Vector2(22, 12), Vector2(340, 42), 30, UI.INK, true)
	var title: String = "起手調整" if phase == "mulligan" else ("勝負已定" if current.get("resolved", false) else "第 %d 回合 · 你的回合" % int(current.get("turn", 1)))
	UI.label(_ui, title, Vector2(530, 18), Vector2(520, 32), 21, UI.JADE)
	_build_fighters(current)
	UI.label(_ui, "真氣  %d" % int(current.get("qi", 0)), Vector2(22, 324), Vector2(200, 36), 25, UI.JADE, true)
	var hint: String = "看清敵人意圖，再安排這回合的招式。"
	if phase == "mulligan":
		hint = "點選要更換的牌：已選 %d / %d 張" % [mulligan_selection.size(), current.get("mulligan_limit", 0)]
	elif not _message.is_empty():
		hint = _message
	UI.label(_ui, hint, Vector2(238, 321), Vector2(566, 40), 16, UI.MUTED)
	var hand: Array = current.get("hand", [])
	_page = clampi(_page, 0, maxi(0, (hand.size() - 1) / PAGE_SIZE))
	if hand.size() > PAGE_SIZE:
		_button("hand_previous", "‹", Vector2(826, 323), Vector2(42, 35), _change_page.bind(-1), _page > 0)
		UI.label(_ui, "%d / %d 張" % [mini((_page + 1) * PAGE_SIZE, hand.size()), hand.size()], Vector2(878, 328), Vector2(130, 26), 16)
		_button("hand_next", "›", Vector2(1014, 323), Vector2(42, 35), _change_page.bind(1), (_page + 1) * PAGE_SIZE < hand.size())
	for slot in range(PAGE_SIZE):
		var index: int = _page * PAGE_SIZE + slot
		if index >= hand.size():
			continue
		var card: Dictionary = _hand_card(index, current)
		var selected: bool = index in mulligan_selection if phase == "mulligan" else index == selected_card
		var button: Button = UI.card_button(_ui, card, Vector2(18 + slot * 210, 368), Vector2(202, 205), select_card.bind(index), selected)
		button.name = "card_%d" % index
		action_buttons[button.name] = button
		button.disabled = not _input_enabled or not _panel.is_empty() or bool(current.get("resolved", false)) or (phase == "player" and int(card.cost) > int(current.get("qi", 0)))
		if button.disabled:
			button.modulate = Color(0.86, 0.88, 0.83)
	_button("deck", "牌堆 · %d 張" % current.get("draw_count", 0), Vector2(18, 591), Vector2(154, 38), open_panel.bind("deck"), true, false, true)
	_button("rules", "對決規則", Vector2(184, 591), Vector2(126, 38), open_panel.bind("rules"), true, false, true)
	if selected_card >= 0:
		_button("selection_cancel", "取消選牌", Vector2(324, 591), Vector2(134, 38), cancel_selection)
	if phase == "mulligan":
		_button("mulligan_skip", "保留起手牌", Vector2(667, 591), Vector2(176, 38), skip_mulligan)
		_button("mulligan_confirm", "換牌並開戰", Vector2(855, 591), Vector2(206, 38), confirm_mulligan, not mulligan_selection.is_empty(), true)
	else:
		_button("medicine", "用藥 · 餘 %d" % current.get("medicine_left", 0), Vector2(667, 591), Vector2(176, 38), use_medicine, bool(current.get("can_use_medicine", false)))
		_button("end_turn", "結束回合", Vector2(855, 591), Vector2(206, 38), end_turn, bool(current.get("can_end_turn", phase == "player")), true)
	if not _panel.is_empty():
		_build_panel(current)
	queue_redraw()


func _button(id: String, text: String, position: Vector2, size: Vector2, callback: Callable, enabled: bool = true, primary: bool = false, utility: bool = false, parent: Node = null) -> Button:
	var value: Button = UI.button(_ui if parent == null else parent, text, position, size, callback, primary)
	value.name = id
	value.disabled = not _input_enabled or not enabled or (not _panel.is_empty() and parent == null) or (not utility and bool(_cached_status.get("resolved", false)))
	action_buttons[id] = value
	return value


func _build_fighters(current: Dictionary) -> void:
	UI.label(_ui, str(stats.get("name", "無名少俠")), Vector2(28, 74), Vector2(330, 32), 23, UI.JADE, true)
	UI.label(_ui, "氣血 %d / %d    防護 %d" % [current.get("hp", 0), current.get("max_hp", 0), current.get("block", 0)], Vector2(28, 110), Vector2(370, 30), 18)
	var enemies: Array = current.get("enemies", [])
	for index in range(enemies.size()):
		var enemy: Dictionary = enemies[index]
		var foot: Vector2 = _enemy_foot(index, enemies.size())
		var button: Button = _button("target_%d" % index, "", Vector2(foot.x - 82, 68), Vector2(166, 250), select_target.bind(index), int(enemy.get("hp", 0)) > 0)
		button.add_theme_stylebox_override("normal", UI.style(Color(1, 1, 1, 0.01), UI.GOLD if selected_target == index else Color(1, 1, 1, 0), 2 if selected_card >= 0 and selected_target == index else 0))
		button.add_theme_stylebox_override("disabled", UI.style(Color(1, 1, 1, 0)))
		button.add_theme_stylebox_override("hover", UI.style(Color(0.87, 0.93, 0.82, 0.16), UI.GOLD, 2))
		var name_label = UI.label(button, str(enemy.get("name", "對手")), Vector2(5, 0), Vector2(156, 28), 20, UI.INK, true)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var hp_label = UI.label(button, "%d / %d　護 %d" % [enemy.get("hp", 0), enemy.get("max_hp", 0), enemy.get("block", 0)], Vector2(3, 31), Vector2(160, 25), 15)
		hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var intent: Dictionary = enemy.get("intent", {})
		var intent_text: String = str(intent.get("label", "觀察局勢")) if int(enemy.get("hp", 0)) > 0 else "已退場"
		var intent_label = UI.label(button, intent_text, Vector2(5, 61), Vector2(156, 54), 16, Color("9a5548"))
		intent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var conditions: Array[String] = []
		if int(enemy.get("weak", 0)) > 0:
			conditions.append("虛弱 %d" % enemy.weak)
		if int(enemy.get("vulnerable", 0)) > 0:
			conditions.append("破綻 %d" % enemy.vulnerable)
		var condition_label = UI.label(button, " · ".join(conditions), Vector2(2, 229), Vector2(162, 21), 13, UI.JADE)
		condition_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


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
		var rules = "一回合，從容想好再出招。\n\n每回合回復 3 真氣，抽取 5 張牌。點牌可施展招式；有多位對手時，先選牌再選目標。牌上的數字是消耗的真氣。\n\n防護先抵擋傷害。虛弱讓攻擊傷害減少四分之一；破綻讓受到的傷害增加一半。仔細查看敵人頭上的下一步意圖，再決定攻守。\n\n按「結束回合」才會輪到敵人行動。未使用手牌進入棄牌堆；牌堆用盡時，棄牌會重新洗入。標示「本場除外」的牌不再洗回。\n\n起手換牌只有一次；藥品每回合最多使用一次，不耗真氣。查看牌堆、閱讀規則或暫停，都不會推進回合。"
		UI.label(panel, rules, Vector2(28, 88), Vector2(852, 450), 19)
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
		entry.text = "%s × %d　｜　%d 真氣\n%s" % [card.get("name", id), counts[id], card.get("cost", 0), card.get("description", "")]
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
		draw_texture_rect(background, Rect2(0, 60, 1080, 257), false, Color(1, 1, 1, 0.25))
	draw_rect(Rect2(0, 317, 1080, 323), Color("eef0e2"))
	draw_line(Vector2(18, 317), Vector2(1062, 317), Color("c7ccb6"), 1)
	if not _configured:
		return
	var phase: float = _visual_age / CLIP_TIME
	var lunge: float = sin((1.0 - phase) * PI) * 18.0 if _visual_kind == "attack" and _visual_age > 0.0 else 0.0
	var hero_tint = Color("ffdbc7") if _visual_kind == "enemy" and _visual_age > 0.1 else Color.WHITE
	_draw_token(str(stats.get("origin", "courier")), HERO_FOOT + Vector2(lunge, 0), 145, hero_tint)
	var enemies: Array = _cached_status.get("enemies", [])
	for index in range(enemies.size()):
		var enemy: Dictionary = enemies[index]
		var tint = Color(0.52, 0.55, 0.5, 0.35) if int(enemy.get("hp", 0)) <= 0 else Color.WHITE
		if _visual_kind == "attack" and index == _visual_target and _visual_age > 0.08:
			tint = Color("ffe6ad")
		_draw_token(str(enemy.get("kind", "bandit")), _enemy_foot(index, enemies.size()), 112, tint)
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
