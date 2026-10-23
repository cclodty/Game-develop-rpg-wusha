extends Control
## Presentation and orchestration. All schedule/reward changes live in WeiyuanRun.

const Run = preload("res://scripts/run_state.gd")
const Data = preload("res://scripts/game_data.gd")
const World = preload("res://scripts/world.gd")
const Arena = preload("res://scripts/card_arena.gd")
const Cards = preload("res://scripts/card_catalog.gd")
const Creation = preload("res://scripts/character_creation.gd")
const CreationJourney = preload("res://scripts/creation_journey.gd")
const Art = preload("res://scripts/art.gd")
const AnimationPreview = preload("res://scenes/animation_preview.tscn")
const SANS = preload("res://assets/fonts/JianghuSans.otf")
const SERIF = preload("res://assets/fonts/JianghuSerif.otf")
const PAPER = Color("f6f0df")
const INK = Color("243e39")
const MUTED = Color("66746b")
const JADE = Color("315d51")
const GOLD = Color("b58b4d")
const RED = Color("a34c3d")
const FIELD_OFFSET = Vector2(28, 136)
const STORY_PATH = "res://story/first_week.dialogue"

var run = Run.new()
var world: Node2D
var arena: Node2D
var story_line: DialogueLine
var action_buttons: Dictionary = {}
var current_location = "wangxi"
var selected_origin = "herbalist"
var name_entry: LineEdit
var animation_preview: Control
var creation_journey: Control
var _deck_draft: Array = []
var _deck_scroll: ScrollContainer
var _combat_restore_failed = false
var _backdrop: Control
var _world_layer: Node2D
var _hud: Control
var _overlay: Control
var _toasts: Control
var _overlay_kind = ""
var _story_resource: DialogueResource
var _story_revision = ""
var _story_request = 0
var _arena_request = 0
var _story_busy = false
var _save_timer = 0.0
var _toast_timer = 0.0
var _combat_status: Label
var _combat_hp: ProgressBar
var _combat_stamina: ProgressBar
var _music: AudioStreamPlayer
var _muted = false
var _screen = "title"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = Theme.new()
	theme.default_font = SANS
	theme.default_font_size = 20
	_backdrop = _layer("Backdrop")
	_world_layer = Node2D.new()
	_world_layer.name = "Playfield"
	var field_clip = Control.new()
	field_clip.position = FIELD_OFFSET
	field_clip.size = Vector2(1080, 640)
	field_clip.clip_contents = true
	field_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(field_clip)
	_world_layer.position = -FIELD_OFFSET
	field_clip.add_child(_world_layer)
	_hud = _layer("Interface")
	_overlay = _layer("Overlay")
	_toasts = _layer("Toasts")
	_music = AudioStreamPlayer.new()
	_music.stream = preload("res://assets/audio/river_ambience.wav")
	_music.volume_db = -23
	_music.finished.connect(func():
		if not _muted: _music.play())
	add_child(_music)
	if ResourceLoader.exists(STORY_PATH):
		_story_resource = load(STORY_PATH) as DialogueResource
		_story_revision = _story_resource.raw_text.sha256_text() if _story_resource else ""
	_show_title()


func _exit_tree() -> void:
	_muted = true
	if is_instance_valid(_music):
		_music.stop()
		_music.stream = null
	if _story_resource:
		# Dialogue Manager 3.x caches its resource in parsed line dictionaries.
		for value in _story_resource.lines.values():
			if value is Dictionary: value.erase("resource")


func _process(delta: float) -> void:
	_toast_timer -= delta
	if _toast_timer <= 0.0 and _toasts.get_child_count() > 0:
		_clear(_toasts)
	if _screen != "game": return
	_save_timer += delta
	if _save_timer >= 4.0:
		_save_timer = 0.0
		_save(false)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo: return
	if _overlay_kind == "prologue":
		if event.ctrl_pressed and event.keycode == KEY_S:
			_save(true)
			get_viewport().set_input_as_handled()
		return
	if _overlay_kind == "animation_preview":
		if event.keycode == KEY_ESCAPE:
			_close_overlay()
			get_viewport().set_input_as_handled()
		return
	if event.ctrl_pressed and event.keycode == KEY_S:
		if _screen == "game": _save(true)
		get_viewport().set_input_as_handled()
		return
	if _overlay_kind == "dialogue":
		if _story_busy: return
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			if story_line and story_line.responses.is_empty(): _advance_dialogue()
			get_viewport().set_input_as_handled()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_4:
			_respond_dialogue(int(event.keycode - KEY_1))
			get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ESCAPE and _screen == "game":
		get_viewport().set_input_as_handled()
		if _overlay_kind in ["pause", "map", "journal", "npc", "confirm", "planner", "deck", "help"]:
			_close_overlay()
		elif _overlay_kind.is_empty():
			_show_pause()


func _layer(node_name: String) -> Control:
	var layer = Control.new()
	layer.name = node_name
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	return layer


func _clear(parent: Node) -> void:
	for key in action_buttons.keys():
		var button = action_buttons[key]
		if not is_instance_valid(button) or parent.is_ancestor_of(button):
			action_buttons.erase(key)
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _style(fill: Color, border: Color, radius: int = 15, width: int = 1) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style


func _panel(parent: Node, pos: Vector2, extent: Vector2, color: Color = PAPER, edge: Color = Color("d4c8a9")) -> Panel:
	var node = Panel.new()
	node.position = pos
	node.size = extent
	node.add_theme_stylebox_override("panel", _style(color, edge))
	parent.add_child(node)
	return node


func _label(parent: Node, text: String, pos: Vector2, extent: Vector2, font_size: int = 20, color: Color = INK, serif: bool = false) -> Label:
	var node = Label.new()
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.text = text
	node.position = pos
	node.size = extent
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.add_theme_font_override("font", SERIF if serif else SANS)
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node


func _button(parent: Node, key: String, text: String, pos: Vector2, extent: Vector2, callback: Callable, primary: bool = false) -> Button:
	var node = Button.new()
	node.position = pos
	node.size = extent
	node.text = text
	node.focus_mode = Control.FOCUS_NONE
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.add_theme_font_size_override("font_size", 19)
	node.add_theme_color_override("font_color", PAPER if primary else INK)
	node.add_theme_color_override("font_hover_color", PAPER if primary else INK)
	node.add_theme_color_override("font_pressed_color", PAPER if primary else INK)
	node.add_theme_color_override("font_disabled_color", Color("8c9389"))
	node.add_theme_stylebox_override("normal", _style(JADE if primary else Color("fffbef"), JADE if primary else Color("d4c8a9"), 10))
	node.add_theme_stylebox_override("hover", _style(Color("427563") if primary else Color("e7eeda"), GOLD, 10, 2))
	node.add_theme_stylebox_override("pressed", _style(Color("24473f") if primary else Color("d7e2c9"), GOLD, 10))
	node.add_theme_stylebox_override("disabled", _style(Color("e4e1d5"), Color("d3d0c6"), 10))
	node.pressed.connect(callback)
	parent.add_child(node)
	if not key.is_empty(): action_buttons[key] = node
	return node


func _picture(parent: Node, texture: Texture2D, pos: Vector2, extent: Vector2, cover: bool = false) -> TextureRect:
	var node = TextureRect.new()
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.texture = texture
	node.position = pos
	node.size = extent
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if cover else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node


func _shade(parent: Node, alpha: float = 0.55) -> ColorRect:
	var shade = ColorRect.new()
	shade.color = Color(0.06, 0.12, 0.11, alpha)
	shade.size = Vector2(1440, 900)
	parent.add_child(shade)
	return shade


func _close_overlay() -> void:
	_story_request += 1
	_story_busy = false
	story_line = null
	_clear(_overlay)
	animation_preview = null
	creation_journey = null
	_overlay_kind = ""
	_enable_playfield(true)


func _modal(kind: String, extent: Vector2, title: String, subtitle: String = "") -> Panel:
	_close_overlay()
	_clear(_toasts)
	_overlay_kind = kind
	_enable_playfield(false)
	_shade(_overlay)
	var panel = _panel(_overlay, (Vector2(1440, 900) - extent) / 2.0, extent)
	_label(panel, title, Vector2(30, 21), Vector2(extent.x - 60, 50), 32, INK, true)
	if not subtitle.is_empty():
		_label(panel, subtitle, Vector2(30, 77), Vector2(extent.x - 60, 58), 18, MUTED)
	return panel


func _enable_playfield(enabled: bool) -> void:
	if is_instance_valid(world): world.set_input_enabled(enabled)
	if is_instance_valid(arena): arena.set_input_enabled(enabled)


func _discard_field() -> void:
	_arena_request += 1
	for child in _world_layer.get_children():
		_world_layer.remove_child(child)
		child.queue_free()
	world = null
	arena = null
	_combat_status = null
	_combat_hp = null
	_combat_stamina = null


func _show_title() -> void:
	_screen = "title"
	_combat_restore_failed = false
	_close_overlay()
	_discard_field()
	_clear(_hud)
	_clear(_backdrop)
	_picture(_backdrop, Art.title_background(), Vector2.ZERO, Vector2(1440, 900), true)
	_shade(_backdrop, 0.17).mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel = _panel(_hud, Vector2(76, 96), Vector2(610, 708), Color(0.97, 0.95, 0.89, 0.97))
	_label(panel, "原創武俠 · 七日養成 · 卡牌對決", Vector2(42, 42), Vector2(510, 36), 19, GOLD)
	_label(panel, "江湖未遠", Vector2(38, 100), Vector2(530, 100), 72, JADE, true)
	_label(panel, "入 山 之 前", Vector2(44, 212), Vector2(510, 44), 26, RED, true)
	_label(panel, "從行囊裡的一件小事，到劍坪上的一招一式。\n你怎樣選擇，便怎樣走進江湖。", Vector2(44, 284), Vector2(520, 102), 22)
	_button(panel, "new_game", "啟程 · 抵達之前", Vector2(44, 424), Vector2(520, 64), _show_creation, true)
	var continue_button = _button(panel, "continue", "接著上次的旅程", Vector2(44, 506), Vector2(520, 60), _continue_game)
	continue_button.disabled = not FileAccess.file_exists(Run.SAVE_PATH) and not FileAccess.file_exists(Run.SAVE_PATH + ".bak")
	_button(panel, "help", "初行手札 · 怎樣遊玩", Vector2(44, 590), Vector2(520, 48), _show_help)
	_label(panel, "情境建角 · 自由配招 · 七日的人情與奇遇\n鍵盤滑鼠遊玩　／　自動存檔", Vector2(44, 650), Vector2(520, 47), 16, MUTED)
	_label(_hud, "望溪鎮的晨霧散了。你的故事，從今天開始。", Vector2(780, 820), Vector2(610, 40), 19, PAPER, true)
	_button(_hud, "sound", "聲音：關" if _muted else "聲音：開", Vector2(1260, 28), Vector2(150, 44), _toggle_music)


func _show_animation_preview() -> void:
	_close_overlay()
	_overlay_kind = "animation_preview"
	_enable_playfield(false)
	animation_preview = AnimationPreview.instantiate()
	_overlay.add_child(animation_preview)
	animation_preview.closed.connect(_close_overlay)
	action_buttons.merge(animation_preview.action_buttons)


func _show_creation() -> void:
	var panel = _modal("creation", Vector2(1210, 750), "你從何處來", "三種起點，各有一點長處。門派與武功由你接下來的選擇決定。")
	_label(panel, "江湖稱呼", Vector2(34, 133), Vector2(140, 44), 20)
	name_entry = LineEdit.new()
	name_entry.position = Vector2(178, 130)
	name_entry.size = Vector2(360, 50)
	name_entry.max_length = 12
	name_entry.placeholder_text = "給自己取個名字"
	name_entry.text = "小行"
	name_entry.add_theme_font_size_override("font_size", 22)
	name_entry.add_theme_color_override("font_color", INK)
	name_entry.add_theme_color_override("caret_color", JADE)
	name_entry.add_theme_color_override("font_selected_color", PAPER)
	name_entry.add_theme_color_override("selection_color", JADE)
	name_entry.add_theme_stylebox_override("normal", _style(Color("fffcf2"), GOLD, 8))
	panel.add_child(name_entry)
	var origins = ["herbalist", "courier", "performer"]
	for i in range(origins.size()):
		var origin = origins[i]
		var info: Dictionary = Data.ORIGINS[origin]
		var card = _panel(panel, Vector2(34 + i * 385, 210), Vector2(370, 402), Color("eee9d7"))
		_picture(card, Art.portrait(origin), Vector2(80, 14), Vector2(210, 218))
		_label(card, str(info.get("name", origin)), Vector2(22, 238), Vector2(330, 40), 25, JADE, true)
		_label(card, str(info.get("description", "")), Vector2(22, 284), Vector2(326, 65), 18)
		_button(card, "origin_" + origin, "選擇這個出身", Vector2(22, 350), Vector2(326, 40), func(): _select_origin(origin))
	_button(panel, "creation_back", "回到卷首", Vector2(34, 655), Vector2(190, 56), _close_overlay)
	_label(panel, "", Vector2(34, 618), Vector2(1140, 32), 17, JADE).name = "OriginPerk"
	_button(panel, "create", "收拾行囊，踏上旅程", Vector2(810, 655), Vector2(368, 56), _create_game, true)
	_select_origin(selected_origin)


func _select_origin(origin: String) -> void:
	selected_origin = origin
	var perk = _overlay.find_child("OriginPerk", true, false)
	if perk: perk.text = "出身便利：" + str(Data.ORIGINS[origin].perk)
	for id in ["herbalist", "courier", "performer"]:
		if action_buttons.has("origin_" + id):
			action_buttons["origin_" + id].text = "已選擇" if id == origin else "選擇這個出身"


func _create_game() -> void:
	var hero = name_entry.text.strip_edges() if is_instance_valid(name_entry) else "小行"
	if hero.is_empty(): hero = "小行"
	run.start_creation(hero, selected_origin)
	_screen = "game"
	if not _muted and not _music.playing: _music.play()
	_show_creation_journey()
	_save()


func _show_creation_journey() -> void:
	_close_overlay()
	_discard_field()
	_clear(_hud)
	_clear(_backdrop)
	_overlay_kind = "prologue"
	creation_journey = CreationJourney.new()
	_overlay.add_child(creation_journey)
	creation_journey.configure(run)
	creation_journey.changed.connect(func(): _save())
	creation_journey.confirmed.connect(_creation_confirmed)
	creation_journey.closed.connect(_save_exit)


func _creation_confirmed() -> void:
	_show_world("wangxi")
	_play_dialogue("arrival_morning", "intro_done")
	_save()


func _continue_game() -> void:
	var result: Dictionary = run.load_game()
	if not result.get("ok", false):
		_toast(str(result.get("message", "存檔未能讀取。")), true)
		return
	_screen = "game"
	if not _muted and not _music.playing: _music.play()
	_recover_screen()
	if bool(result.get("recovered", false)):
		_toast(str(result.message))


func _recover_screen() -> void:
	if str(run.data.get("phase", "")) == "prologue":
		_show_creation_journey()
		return
	var pending: Dictionary = run.data.get("pending", {})
	var saved_dialogue: Dictionary = run.data.get("dialogue", {}).duplicate(true)
	if not pending.is_empty():
		var stage = str(pending.get("stage", "story"))
		if stage in ["combat", "defeat"]:
			_start_arena(pending.get("combat", {}), stage == "defeat")
		elif stage in ["explore", "task"]:
			_show_activity_world()
		else:
			_show_world("wangxi")
	elif str(run.data.get("phase", "")) == "ending" or not str(run.data.get("school", "")).is_empty():
		_show_world("wangxi")
		_show_ending()
	elif not run.data.get("exam_result", {}).is_empty():
		_show_world("wangxi")
		_show_exam_results()
	else:
		_show_world("wangxi")
	if not saved_dialogue.is_empty():
		var cursor = str(saved_dialogue.get("cursor", "")) if str(saved_dialogue.get("revision", "")) == _story_revision else ""
		_play_dialogue(str(saved_dialogue.get("title", "")), str(saved_dialogue.get("after", "")), cursor, str(saved_dialogue.get("return_npc", "")))
	elif not pending.is_empty() and str(pending.get("stage", "story")) == "story":
		var id = str(pending.get("id", ""))
		_play_dialogue("exam_intro" if id == "exam" else "activity_" + id, "begin_exam_combat" if id == "exam" else "activity_briefed")
	elif not pending.is_empty() and str(pending.get("stage", "")) == "debrief":
		_finish_activity_success(pending.get("report", {}))
	elif str(run.data.get("phase", "")) == "intro" and saved_dialogue.is_empty():
		_play_dialogue("arrival_morning", "intro_done")


func _show_world(location: String, position_override: Vector2 = Vector2(-1, -1)) -> void:
	_close_overlay()
	_discard_field()
	_clear(_backdrop)
	current_location = location
	var base = ColorRect.new()
	base.color = Color("e5e7d4")
	base.size = Vector2(1440, 900)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.add_child(base)
	_panel(_backdrop, Vector2(20, 128), Vector2(1096, 656), PAPER, GOLD).mouse_filter = Control.MOUSE_FILTER_IGNORE
	world = World.new()
	world.position = FIELD_OFFSET
	_world_layer.add_child(world)
	var point = position_override
	if point.x < 0.0 and location == "wangxi":
		var stored = run.data.get("world_position", [540, 550])
		point = Vector2(float(stored[0]), float(stored[1]))
	world.configure(location, str(run.data.get("origin", "herbalist")), point)
	world.npc_requested.connect(_on_npc)
	world.hotspot_requested.connect(_on_hotspot)
	world.exit_requested.connect(func(_destination):
		if run.data.get("pending", {}).is_empty(): _show_map()
		else: _confirm_retreat())
	_refresh_hud()


func _refresh_hud() -> void:
	_clear(_hud)
	_combat_status = null
	_combat_hp = null
	_combat_stamina = null
	var top = _panel(_hud, Vector2(20, 18), Vector2(1400, 94))
	_label(top, "江湖未遠", Vector2(20, 13), Vector2(230, 47), 34, JADE, true)
	_label(top, "入山之前", Vector2(22, 60), Vector2(250, 25), 16, GOLD)
	_label(top, "第 %d 日 · %s" % [run.day(), run.period()], Vector2(286, 14), Vector2(300, 44), 27, JADE, true)
	_label(top, "選拔準備尚餘 %d 個時段" % run.remaining() if run.remaining() > 0 else "第八日 · 入門選拔", Vector2(288, 60), Vector2(340, 25), 17, RED)
	var origin_name = str(Data.ORIGINS.get(run.data.get("origin", ""), {}).get("name", "旅人"))
	_label(top, str(run.data.get("hero_name", "小行")) + " · " + origin_name, Vector2(680, 17), Vector2(410, 32), 21)
	_label(top, "盤纏 %d　藥 %d　武學 %d　見識 %d" % [run.data.get("money", 0), run.data.get("medicine", 0), run.data.get("training", 0), run.data.get("insight", 0)], Vector2(680, 58), Vector2(530, 29), 18, MUTED)
	_button(top, "pause", "暫停／存檔", Vector2(1220, 24), Vector2(160, 47), _show_pause)
	var side = _panel(_hud, Vector2(1132, 128), Vector2(288, 656))
	if is_instance_valid(arena):
		_label(side, "一招一式", Vector2(22, 22), Vector2(245, 44), 26, JADE, true)
		_combat_hp = _bar(side, Vector2(22, 86), Vector2(244, 24), RED)
		_combat_stamina = _bar(side, Vector2(22, 126), Vector2(244, 17), JADE)
		_combat_status = _label(side, "", Vector2(22, 164), Vector2(245, 254), 18)
		_label(side, "先看敵方意圖，再選招。\n每回合 3 真氣、抽 5 張。\n防護於下回合開始清除。\n思考與看牌都不耗時。", Vector2(22, 421), Vector2(245, 150), 18, MUTED)
		_button(side, "retreat", "認輸" if _pending_id() == "exam" else "撤退", Vector2(22, 585), Vector2(244, 48), _confirm_retreat)
		_on_arena_status(arena.status())
	else:
		_label(side, "今日手札", Vector2(22, 22), Vector2(244, 44), 27, JADE, true)
		var pending: Dictionary = run.data.get("pending", {})
		if not pending.is_empty():
			var info: Dictionary = Data.ACTIVITIES.get(pending.get("id", ""), {})
			_label(side, str(info.get("name", "入門選拔")), Vector2(22, 82), Vector2(244, 64), 23, INK, true)
			_label(side, "本次行程已扣除時段。\n走動、交談與戰鬥不另計時。", Vector2(22, 158), Vector2(244, 83), 18, MUTED)
			var visited: Array = pending.get("visited", [])
			_label(side, "調查進度　%d / %d\n\n靠近金色標記，按 F 互動。" % [visited.size(), _objectives_for_activity(_pending_id()).size()], Vector2(22, 266), Vector2(244, 150), 20)
			if not str(pending.get("fortune_hint", "")).is_empty():
				_label(side, str(pending.fortune_hint), Vector2(22, 420), Vector2(244, 138), 17, JADE)
			_button(side, "retreat", "放棄本次行程", Vector2(22, 574), Vector2(244, 48), _confirm_retreat)
		else:
			_label(side, "選一位引路人，\n開始自己的七日。" if run.remaining() > 0 else "鐘聲已響。\n帶著這七日的所得，赴約。", Vector2(22, 84), Vector2(244, 86), 22, INK, true)
			_label(side, "練功精修招式，\n見聞與承諾帶來新的牌路。\n\n交談與配招不消耗時段。", Vector2(22, 180), Vector2(244, 126), 18, MUTED)
			_button(side, "deck", "角色與配招", Vector2(22, 306), Vector2(244, 46), _show_deck)
			if run.ready_for_exam():
				_button(side, "exam", "赴入門選拔", Vector2(22, 366), Vector2(244, 58), _confirm_exam, true)
			else:
				_button(side, "guide", "去找照嶺師傅", Vector2(22, 366), Vector2(244, 58), _guide_to_shen, true)
			_button(side, "map", "江湖輿圖", Vector2(22, 440), Vector2(244, 48), _show_map)
			_button(side, "planner", "七日行程與門派", Vector2(22, 501), Vector2(244, 48), _show_planner)
			_button(side, "journal", "紀事與人物", Vector2(22, 562), Vector2(244, 48), _show_journal)
	var foot = _panel(_hud, Vector2(20, 804), Vector2(1400, 74), Color("edf0e1"))
	_label(foot, "WASD／方向鍵 移動　·　點地面行走　·　F 互動　·　Esc 暫停　·　Ctrl+S 存檔" if not is_instance_valid(arena) else "點手牌選招式，點敵人選目標。　看清意圖、安排牌序，再結束回合。", Vector2(24, 20), Vector2(1200, 37), 18, MUTED)
	_button(foot, "sound", "聲音：關" if _muted else "聲音：開", Vector2(1240, 14), Vector2(140, 44), _toggle_music)


func _bar(parent: Node, pos: Vector2, extent: Vector2, color: Color) -> ProgressBar:
	var bar = ProgressBar.new()
	bar.position = pos
	bar.size = extent
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", _style(Color("dedccd"), Color.TRANSPARENT, 6, 0))
	bar.add_theme_stylebox_override("fill", _style(color, Color.TRANSPARENT, 6, 0))
	parent.add_child(bar)
	return bar


func _toggle_music() -> void:
	_muted = not _muted
	AudioServer.set_bus_mute(0, _muted)
	if _muted: _music.stop()
	elif not _music.playing: _music.play()
	if action_buttons.has("sound"): action_buttons.sound.text = "聲音：關" if _muted else "聲音：開"


func _toast(message: String, error: bool = false) -> void:
	_clear(_toasts)
	_toast_timer = 4.6
	var box = _panel(_toasts, Vector2(244, 20), Vector2(950, 72), Color("a34c3d") if error else JADE, GOLD)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label(box, message, Vector2(20, 12), Vector2(910, 54), 18, PAPER)


func _save(show_message: bool = false) -> bool:
	if _combat_restore_failed: return false
	if run.data.is_empty(): return false
	if is_instance_valid(world):
		var point: Vector2 = world.get_player_position()
		if current_location == "wangxi": run.data["world_position"] = [point.x, point.y]
		if not run.data.get("pending", {}).is_empty():
			var target_location = str(Data.ACTIVITIES.get(_pending_id(), {}).get("location", "wangxi"))
			if current_location == target_location: run.data.pending["world_position"] = [point.x, point.y]
	if is_instance_valid(arena) and not run.data.get("pending", {}).is_empty():
		run.data.pending["combat"] = arena.snapshot()
	var result: Dictionary = run.save_game()
	if not result.get("ok", false):
		_toast(str(result.get("message", "未能儲存，請先保留視窗。")), true)
		return false
	if show_message: _toast("已存下這一程。下次可從卷首繼續。")
	return true


func _save_exit() -> void:
	if _save(false): _show_title()


func _guide_to_shen() -> void:
	if is_instance_valid(world): world.navigate_to_npc("shen")


func _play_dialogue(title: String, after: String, cursor: String = "", return_npc: String = "") -> void:
	if _story_resource == null or not _story_resource.titles.has(title):
		_toast("這一段對話未能載入，請重新開啟遊戲。", true)
		return
	_close_overlay()
	_overlay_kind = "dialogue"
	_enable_playfield(false)
	run.data.dialogue = {"title": title, "cursor": cursor, "revision": _story_revision, "after": after, "return_npc": return_npc}
	_fetch_dialogue(cursor if not cursor.is_empty() else title)


func _fetch_dialogue(cursor: String) -> void:
	if _story_busy: return
	_story_busy = true
	_story_request += 1
	var request = _story_request
	var next: DialogueLine = await _story_resource.get_next_dialogue_line(cursor, [run.story_context()], DMConstants.MutationBehaviour.Skip)
	if request != _story_request or not is_inside_tree(): return
	_story_busy = false
	if next == null:
		_dialogue_ended()
		return
	story_line = next
	run.data.dialogue.cursor = next.id
	_present_dialogue()
	_save()


func _present_dialogue() -> void:
	_clear(_overlay)
	_overlay_kind = "dialogue"
	_enable_playfield(false)
	_shade(_overlay, 0.3)
	var panel = _panel(_overlay, Vector2(100, 390), Vector2(1240, 470))
	var portrait = str(run.data.origin)
	for tag in story_line.tags:
		if str(tag).begins_with("portrait="): portrait = str(tag).trim_prefix("portrait=")
	if portrait == "hero": portrait = str(run.data.origin)
	_picture(panel, Art.portrait(portrait), Vector2(24, 48), Vector2(245, 344))
	var speaker = str(run.data.hero_name) if story_line.character == "你" else story_line.character
	_label(panel, speaker if not speaker.is_empty() else "望溪紀事", Vector2(295, 25), Vector2(820, 44), 29, JADE, true)
	_label(panel, story_line.text, Vector2(295, 88), Vector2(890, 150), 25)
	if story_line.responses.is_empty():
		_button(panel, "dialogue_next", "繼續  ›", Vector2(985, 361), Vector2(205, 58), _advance_dialogue, true)
		_label(panel, "Enter／空白鍵繼續　·　閱讀不耗時", Vector2(295, 382), Vector2(650, 36), 17, MUTED)
	else:
		for i in range(story_line.responses.size()):
			var response = story_line.responses[i]
			var button = _button(panel, "dialogue_response_%d" % i, "%d　%s" % [i + 1, response.text], Vector2(295, 239 + i * 47), Vector2(895, 42), _respond_dialogue.bind(i), i == story_line.responses.size() - 1)
			button.disabled = not response.is_allowed
	_button(_overlay, "save_exit", "存檔回卷首", Vector2(1180, 38), Vector2(200, 48), _save_exit)


func _advance_dialogue() -> void:
	if _story_busy or story_line == null or not story_line.responses.is_empty(): return
	_fetch_dialogue(story_line.next_id)


func _respond_dialogue(index: int) -> void:
	if _story_busy or story_line == null or index < 0 or index >= story_line.responses.size(): return
	var response = story_line.responses[index]
	if response.is_allowed: _fetch_dialogue(response.next_id)


func _dialogue_ended() -> void:
	var bookmark: Dictionary = run.data.get("dialogue", {}).duplicate(true)
	run.data.dialogue = {}
	_close_overlay()
	match str(bookmark.get("after", "")):
		"intro_done":
			run.data.phase = "town"
			_refresh_hud()
			_toast("七日已開始。點人物交談，或用「七日行程」安排活動。")
		"npc": _show_npc(str(bookmark.get("return_npc", "shen")))
		"activity_briefed": _activity_briefed()
		"settle_activity": _settle_activity()
		"begin_exam_combat": _start_arena()
		"ending_done": _show_ending()
	_save()


func _on_npc(id: String) -> void:
	if not run.data.pending.is_empty():
		_toast("先完成金色標記的活動目標，再安排新的事情。")
		return
	_play_dialogue("npc_" + id, "npc", "", id)


func _show_npc(id: String) -> void:
	var npc: Dictionary = Data.NPCS[id]
	var panel = _modal("npc", Vector2(1110, 720), str(npc.name), "%s　·　信任 %d　·　普通交談不耗時" % [npc.role, int(run.data.favor[id])])
	_picture(panel, Art.portrait(id), Vector2(15, 148), Vector2(300, 380))
	_label(panel, npc.description, Vector2(30, 535), Vector2(270, 80), 20, MUTED)
	var ids = Data.activities_for(id)
	for i in range(ids.size()):
		_activity_card(panel, str(ids[i]), Vector2(335, 137 + i * 120), Vector2(740, 108))
	if id == "tao":
		_button(panel, "buy_medicine", "買回復藥 · 12 文 · 不耗時", Vector2(335, 620), Vector2(430, 52), _buy_medicine)
	_button(panel, "close", "回到鎮上", Vector2(845, 638), Vector2(230, 50), _close_overlay)


func _activity_card(parent: Node, id: String, pos: Vector2, extent: Vector2) -> void:
	var activity: Dictionary = Data.ACTIVITIES[id]
	var status: Dictionary = run.activity_status(id)
	var card = _panel(parent, pos, extent, Color("faf7eb"))
	_label(card, "%s  ·  %d 時段" % [activity.name, int(activity.cost)], Vector2(16, 10), Vector2(extent.x - 168, 34), 22)
	_label(card, str(activity.reward_text) if status.ok else str(status.message), Vector2(16, 48), Vector2(extent.x - 165, extent.y - 50), 16, MUTED)
	var button = _button(card, "activity_" + id, "安排", Vector2(extent.x - 132, 25), Vector2(112, 52), _confirm_activity.bind(id), true)
	button.disabled = not status.ok


func _buy_medicine() -> void:
	var result: Dictionary = run.buy_medicine()
	_refresh_hud()
	_show_npc("tao")
	_toast(result.message, not result.ok)
	_save()


func _confirm_activity(id: String) -> void:
	var activity: Dictionary = Data.ACTIVITIES[id]
	var status: Dictionary = run.activity_status(id)
	var panel = _modal("confirm", Vector2(830, 560), str(activity.name), "安排前，看看這一程要付出什麼。")
	_label(panel, activity.description, Vector2(35, 145), Vector2(760, 90), 24)
	_label(panel, "消耗 %d 個時段%s　｜　剩餘 %d → %d" % [int(activity.cost), "、%d 文" % int(activity.get("fee", 0)) if activity.get("fee", 0) else "", run.remaining(), maxi(0, run.remaining() - int(activity.cost))], Vector2(35, 253), Vector2(760, 45), 23, JADE)
	_label(panel, activity.reward_text, Vector2(35, 310), Vector2(760, 90), 21)
	_label(panel, "外出包含來回、探索與戰鬥。重試不重扣時段；退出不退還已投入時間。", Vector2(35, 402), Vector2(760, 56), 17, MUTED)
	_button(panel, "cancel", "再想想", Vector2(35, 474), Vector2(220, 52), _show_planner)
	var button = _button(panel, "confirm_activity", "確定安排", Vector2(535, 474), Vector2(260, 52), _begin_activity.bind(id), true)
	button.disabled = not status.ok


func _begin_activity(id: String) -> void:
	var result: Dictionary = run.begin_activity(id)
	if not result.ok:
		_toast(result.message, true)
		return
	run.data.pending.stage = "story"
	_save()
	_refresh_hud()
	_play_dialogue("activity_" + id, "activity_briefed")


func _activity_briefed() -> void:
	if run.data.pending.is_empty(): return
	var activity: Dictionary = Data.ACTIVITIES[_pending_id()]
	match str(activity.kind):
		"story", "rest": _settle_activity()
		"battle": _start_arena()
		"task", "explore":
			run.data.pending.stage = activity.kind
			_show_activity_world()
	_save()


func _objectives_for_activity(id: String) -> Array:
	var activity: Dictionary = Data.ACTIVITIES.get(id, {})
	if activity.get("kind", "") not in ["task", "explore"]: return []
	if activity.get("kind", "") == "task":
		var labels = {
			"courier_work": ["送出第一封信", "送信並聽回覆"], "stage_work": ["備好戲臺道具", "招呼觀眾開演"],
			"bridge_repair": ["領取修橋木料", "補板並試走"], "missing_letter": ["查問信上的舊稱", "確認真正收信人"],
		}.get(id, ["尋訪線索", "完成約定"])
		return [{"id": "first", "label": labels[0], "position": Vector2(390, 245)}, {"id": "second", "label": labels[1], "position": Vector2(700, 455)}]
	var points = [Vector2(340, 310), Vector2(710, 225), Vector2(655, 480)] if activity.get("location", "") == "grove" else [Vector2(350, 280), Vector2(770, 225), Vector2(540, 440)]
	var labels = {
		"herb_errand": ["辨認溪邊藥草", "找回失落藥籃", "清出安全回程"],
		"grove_survey": ["觀察石上水痕", "核對舊路竹刻", "察看岔路動靜"],
		"ridge_tracks": ["辨認轉身足跡", "觀察迎風石階", "越過攔路之人"],
		"escort_promise": ["檢查藥箱束繩", "確認驛道標記", "護住最後一程"],
	}.get(id, ["查看線索", "走訪舊路", "處理路上阻礙"])
	return [{"id": "first", "label": labels[0], "position": points[0]}, {"id": "second", "label": labels[1], "position": points[1]}, {"id": "danger", "label": labels[2], "position": points[2]}]


func _show_activity_world() -> void:
	if run.data.pending.is_empty(): return
	# Reconcile a checkpoint taken between interacting and changing scenes.
	if "danger" in run.data.pending.get("visited", []) and not run.data.pending.get("battle_won", false):
		_start_arena(run.data.pending.get("combat", {}))
		return
	if _activity_objectives_done():
		_finish_activity_success(run.data.pending.get("report", {}))
		return
	var activity: Dictionary = Data.ACTIVITIES[_pending_id()]
	var default_position = {"grove": [730, 530], "ridge": [620, 475]}.get(activity.get("location", "wangxi"), [540, 550])
	var position_data = run.data.pending.get("world_position", default_position)
	_show_world(str(activity.get("location", "wangxi")), Vector2(float(position_data[0]), float(position_data[1])))
	var remaining_objectives: Array = []
	for objective in _objectives_for_activity(_pending_id()):
		if objective.id not in run.data.pending.visited: remaining_objectives.append(objective)
	world.set_objectives(remaining_objectives)
	_refresh_hud()


func _on_hotspot(id: String) -> void:
	if run.data.pending.is_empty() or id in run.data.pending.visited: return
	var valid = false
	for objective in _objectives_for_activity(_pending_id()):
		if objective.id == id: valid = true
	if not valid: return
	run.data.pending.visited.append(id)
	if id == "danger" and not run.data.pending.get("battle_won", false):
		run.data.pending.stage = "combat"
	elif _activity_objectives_done():
		run.data.pending.stage = "debrief"
	_save()
	if id == "danger" and not run.data.pending.get("battle_won", false):
		_start_arena()
		return
	if _activity_objectives_done():
		_finish_activity_success(run.data.pending.get("report", {}))
	else:
		_show_activity_world()
		_toast("已記下一處線索。繼續走向金色標記。")


func _activity_objectives_done() -> bool:
	if run.data.pending.is_empty(): return false
	return run.data.pending.visited.size() >= _objectives_for_activity(_pending_id()).size() and (Data.ACTIVITIES[_pending_id()].kind == "task" or run.data.pending.get("battle_won", false))


func _start_arena(restore: Dictionary = {}, show_defeat: bool = false) -> void:
	if run.data.pending.is_empty(): return
	_combat_restore_failed = false
	_close_overlay()
	_discard_field()
	_clear(_backdrop)
	_panel(_backdrop, Vector2.ZERO, Vector2(1440, 900), Color("e2e5d7"), Color.TRANSPARENT).mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel(_backdrop, Vector2(20, 128), Vector2(1096, 656), Color("a9b69a")).mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mode = "exam" if _pending_id() == "exam" else str(Data.ACTIVITIES[_pending_id()].get("battle", "practice"))
	var stats: Dictionary = run.battle_stats()
	stats["name"] = str(run.data.hero_name)
	arena = Arena.new()
	arena.position = FIELD_OFFSET
	_world_layer.add_child(arena)
	var configured: Dictionary = arena.configure(mode, stats, restore)
	if not configured.get("ok", false):
		_combat_restore_failed = true
		_refresh_hud()
		var error_panel = _modal("restore_error", Vector2(800, 380), "這場切磋暫時未能接續", "原存檔已保留，尚未扣時或結算獎勵。")
		_label(error_panel, str(configured.get("message", "戰鬥進度未能還原。")), Vector2(35, 150), Vector2(730, 110), 21)
		_button(error_panel, "restore_back", "返回卷首，保留存檔", Vector2(35, 290), Vector2(730, 55), _show_title, true)
		return
	var request = _arena_request
	var token = int(run.data.pending.token)
	arena.finished.connect(func(won: bool, report: Dictionary): _combat_finished(won, report, request, token))
	arena.status_changed.connect(_on_arena_status)
	arena.changed.connect(func(): _save())
	run.data.pending.stage = "defeat" if show_defeat else "combat"
	_refresh_hud()
	if show_defeat: _show_defeat()
	_save()


func _on_arena_status(status: Dictionary) -> void:
	if not is_instance_valid(_combat_status) or not is_instance_valid(_combat_hp): return
	_combat_hp.max_value = float(status.get("max_hp", 100))
	_combat_hp.value = float(status.get("hp", 0))
	_combat_stamina.max_value = maxi(3, int(status.get("energy", 0)))
	_combat_stamina.value = float(status.get("energy", 0))
	_combat_status.text = "氣血 %d／%d\n防護 %d　真氣 %d\n第 %d 回合\n\n回復藥 %d\n\n鎮上可免費配招；\n本次行程使用出發時的牌組。" % [int(status.get("hp", 0)), int(status.get("max_hp", 100)), int(status.get("block", 0)), int(status.get("energy", 0)), int(status.get("turn", 1)), int(status.get("medicine", 0))]


func _combat_finished(won: bool, report: Dictionary, request: int, token: int) -> void:
	if request != _arena_request or run.data.pending.is_empty() or int(run.data.pending.token) != token: return
	report = report.duplicate(true)
	report.pending_token = token
	run.data.pending.report = report
	_save()
	if not won:
		run.data.pending.stage = "defeat"
		_show_defeat()
		_save()
	elif _pending_id() == "exam":
		var result: Dictionary = run.complete_exam(true, report)
		if result.ok:
			_discard_field()
			_show_exam_results()
			_save()
	elif Data.ACTIVITIES[_pending_id()].kind == "explore":
		run.data.pending.battle_won = true
		run.data.pending.stage = "explore"
		_discard_field()
		run.data.pending.combat = {}
		if _activity_objectives_done(): _finish_activity_success(report)
		else: _show_activity_world()
		_save()
	else: _finish_activity_success(report)


func _show_defeat() -> void:
	var panel = _modal("defeat", Vector2(780, 455), "勝負還不是故事的結尾", "先看敵方意圖。敵人蓄勢時可進攻；攻勢將至時，記得留真氣防守。")
	_label(panel, "重試會恢復本場開始時的氣血與回復藥，不再消耗行程。\n\n也可以就此收劍；選拔認輸後，師傅仍會參考這七日做過的事。", Vector2(35, 153), Vector2(710, 160), 23)
	_button(panel, "retry", "再試一次 · 不耗時", Vector2(35, 355), Vector2(335, 60), _retry_combat, true)
	_button(panel, "retreat", "拱手認輸" if _pending_id() == "exam" else "撤退回鎮", Vector2(410, 355), Vector2(335, 60), _retreat_now)


func _retry_combat() -> void:
	var result: Dictionary = run.retry_activity()
	if result.ok:
		run.data.pending.erase("report")
		_start_arena()
	else: _toast(result.message, true)


func _finish_activity_success(report: Dictionary = {}) -> void:
	if run.data.pending.is_empty(): return
	var id = _pending_id()
	run.data.pending.stage = "debrief"
	run.data.pending.report = report.duplicate(true)
	run.data.pending.report.pending_token = int(run.data.pending.token)
	_discard_field()
	run.data.pending.combat = {}
	_show_world("wangxi")
	if _story_resource.titles.has("complete_" + id): _play_dialogue("complete_" + id, "settle_activity")
	else: _settle_activity()
	_save()


func _settle_activity() -> void:
	if run.data.pending.is_empty(): return
	var detail: Dictionary = run.data.pending.get("report", {}).duplicate(true)
	detail.pending_token = int(run.data.pending.token)
	var result: Dictionary = run.complete_activity("success", detail)
	if result.ok:
		_show_world("wangxi")
		_save()
	_toast(result.message, not result.ok)


func _confirm_retreat() -> void:
	if run.data.pending.is_empty(): return
	var panel = _modal("retreat", Vector2(780, 390), "現在收劍？" if _pending_id() == "exam" else "結束這次行程？")
	_label(panel, "選拔認輸會直接評定去向，已完成的修習與委託仍然有效。" if _pending_id() == "exam" else "已投入的時段不會退回。退出後，本次尚未完成的獎勵將不會發放；用過的藥也會計入。", Vector2(35, 105), Vector2(710, 150), 24)
	_button(panel, "cancel", "繼續這一程", Vector2(35, 292), Vector2(325, 55), _close_overlay, true)
	_button(panel, "retreat", "確定認輸" if _pending_id() == "exam" else "確定撤退", Vector2(420, 292), Vector2(325, 55), _retreat_now)


func _retreat_now() -> void:
	if run.data.pending.is_empty(): return
	var was_exam = _pending_id() == "exam"
	var detail: Dictionary = run.data.pending.get("report", {}).duplicate(true)
	if is_instance_valid(arena): detail.medicine_used = int(arena.snapshot().get("medicine_used", detail.get("medicine_used", 0)))
	detail.pending_token = int(run.data.pending.token)
	var result: Dictionary = run.retreat_activity(detail)
	if not result.ok:
		_toast(result.message, true)
		return
	_discard_field()
	if was_exam: _show_exam_results()
	else: _show_world("wangxi")
	_save()
	_toast(result.message)


func _pending_id() -> String:
	return str(run.data.get("pending", {}).get("id", ""))


func _show_planner() -> void:
	var panel = _modal("planner", Vector2(1250, 800), "七日行程", "走路、交談、閱讀不耗時。每次安排先付出時段，完成後才取得成果。")
	for day_index in range(7):
		var day_box = _panel(panel, Vector2(30 + day_index * 171, 136), Vector2(160, 85), Color("e7ecda"))
		_label(day_box, "第 %d 日" % (day_index + 1), Vector2(12, 8), Vector2(136, 28), 19, JADE)
		var periods: Array = []
		for period_index in range(3): periods.append("●" if day_index * 3 + period_index < int(run.data.spent) else "○")
		_label(day_box, "  ".join(periods), Vector2(12, 41), Vector2(136, 30), 21)
	var scroll = _scroll(panel, Vector2(30, 240), Vector2(765, 460))
	for id in Data.ACTIVITIES:
		var row = Control.new()
		row.custom_minimum_size = Vector2(735, 114)
		scroll.add_child(row)
		_activity_card(row, str(id), Vector2.ZERO, Vector2(735, 106))
	_label(panel, "入門看的是這七日", Vector2(830, 244), Vector2(380, 42), 25, JADE, true)
	var requirements = run.exam_requirements()
	_label(panel, "照嶺門\n" + str(requirements.zhaoling) + "\n\n渡雲社\n" + str(requirements.duyun), Vector2(830, 300), Vector2(380, 287), 20)
	_label(panel, "目前武學 %d · 見識 %d\n沈師傅信任 %d · 陸行雲信任 %d" % [run.data.training, run.data.insight, run.data.favor.shen, run.data.favor.lu], Vector2(830, 596), Vector2(380, 80), 20, JADE)
	_button(panel, "close", "回到鎮上", Vector2(30, 726), Vector2(250, 48), _close_overlay)
	_button(panel, "exam", "參加入門選拔" if run.ready_for_exam() else "結束準備，等候選拔…", Vector2(830, 710), Vector2(380, 58), _confirm_exam, run.ready_for_exam())


func _scroll(parent: Node, pos: Vector2, extent: Vector2) -> VBoxContainer:
	var scroll = ScrollContainer.new()
	scroll.position = pos
	scroll.size = extent
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var stack = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 9)
	scroll.add_child(stack)
	return stack


func _show_map() -> void:
	if not run.data.pending.is_empty():
		_confirm_retreat()
		return
	var panel = _modal("map", Vector2(1240, 710), "望溪輿圖", "鎮內自由走動；外出請選擇有明確目的與成本的行程。")
	var places = [["wangxi", "望溪鎮", "六位故人，一段新的緣分。", "自由走動 · 不耗時"], ["grove", "青篁溪谷", "竹影、水痕與落在半途的藥籃。", "尋藥／訪路 · 各 2 時段"], ["ridge", "望風古道", "風很急，承諾要一步一步走完。", "尋跡／護送 · 各 3 時段"]]
	for i in range(3):
		var place: Array = places[i]
		var card = _panel(panel, Vector2(30 + i * 400, 140), Vector2(380, 450), Color("f9f7ea"))
		_picture(card, Art.location(place[0]), Vector2(12, 12), Vector2(356, 210), true)
		_label(card, place[1], Vector2(22, 239), Vector2(335, 42), 27, JADE, true)
		_label(card, place[2] + "\n" + place[3], Vector2(22, 292), Vector2(335, 89), 18, MUTED)
		if i == 0: _button(card, "map_town", "回鎮上走走", Vector2(22, 385), Vector2(336, 48), _show_world.bind("wangxi"), true)
		else: _button(card, "map_" + place[0], "查看可安排的行程", Vector2(22, 385), Vector2(336, 48), _show_location_activities.bind(str(place[0])), true)
	_button(panel, "close", "收起輿圖", Vector2(930, 625), Vector2(280, 50), _close_overlay)


func _show_location_activities(location: String) -> void:
	var panel = _modal("map", Vector2(1050, 540), "青篁溪谷" if location == "grove" else "望風古道", "本次外出的來回、探索與交戰，共用下列時段成本。")
	var i = 0
	for id in Data.ACTIVITIES:
		if Data.ACTIVITIES[id].get("location", "") != location: continue
		_activity_card(panel, str(id), Vector2(30, 142 + i * 128), Vector2(990, 115))
		i += 1
	_button(panel, "close", "返回輿圖", Vector2(750, 453), Vector2(270, 50), _show_map)


func _show_journal() -> void:
	var panel = _modal("journal", Vector2(1230, 760), "這一程的紀事", "武功、人物關係和完成過的事情，都會帶到第八日。")
	var people = _scroll(panel, Vector2(30, 145), Vector2(385, 515))
	for id in Data.NPCS:
		var row = PanelContainer.new()
		row.add_theme_stylebox_override("panel", _style(Color("e8eddd"), Color("d4c8a9")))
		var label = Label.new()
		label.text = "%s　信任 %d\n%s" % [Data.NPCS[id].name, run.data.favor[id], Data.NPCS[id].role]
		label.add_theme_font_size_override("font_size", 20)
		label.add_theme_color_override("font_color", INK)
		row.add_child(label)
		people.add_child(row)
	var log_list = _scroll(panel, Vector2(450, 145), Vector2(750, 515))
	var skills: Array = []
	for id in run.data.learned_cards: skills.append(Cards.card(id, id in run.data.upgraded_cards).name)
	_journal_line(log_list, "已習招式：" + "、".join(skills), JADE)
	for i in range(run.data.journal.size() - 1, -1, -1):
		_journal_line(log_list, str(run.data.journal[i].get("text", "")), INK)
	_button(panel, "close", "繼續走走", Vector2(920, 685), Vector2(280, 48), _close_overlay)


func _journal_line(parent: Node, text: String, color: Color) -> void:
	var label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	label.custom_minimum_size = Vector2(710, 65)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)


func _show_pause() -> void:
	_save()
	var panel = _modal("pause", Vector2(800, 590), "歇一口氣", "閱讀、配招與思考不耗時；關閉後會接著目前的回合。")
	_label(panel, "WASD／方向鍵：移動\n滑鼠點地面：行走　　F：互動\n戰鬥：點選手牌與敵人，再確認出招\n每回合抽 5 張、3 真氣；敵方意圖會先顯示\n\nCtrl+S：存檔　　Esc：暫停／返回\n閱讀對話時，Enter 繼續，數字鍵選擇回應。", Vector2(35, 145), Vector2(730, 284), 23)
	_button(panel, "resume", "繼續這一程", Vector2(35, 480), Vector2(350, 60), _close_overlay, true)
	_button(panel, "save_exit", "存檔回卷首", Vector2(415, 480), Vector2(350, 60), _save_exit)


func _show_help() -> void:
	var panel = _modal("help", Vector2(1040, 710), "初行手札", "先認識自己，再慢慢學會怎樣出劍。")
	_label(panel, "一、抵達之前\n選擇出身，在六個小情境中作出回應。最後會看見能力來源，還能挪動兩點；序章不扣七日的時段。\n\n二、七日的人情與武學\n走動、交談與配招免費。正式活動先顯示時段及盤纏成本，完成後獲得成果。在「角色與配招」中配置十張牌、精修已學招式。\n\n三、一招一式的切磋\n先看敵方意圖。每回合抽五張、獲得三點真氣；用手牌進攻或防守，準備好才結束回合。防護於下回合開始清除。\n\n戰敗可重試，不重扣時段；第八日也可認輸，兩派仍會參考你做過的事情。", Vector2(35, 142), Vector2(970, 445), 23)
	_button(panel, "close", "記下了，繼續", Vector2(690, 620), Vector2(315, 55), _close_overlay, true)


func _show_deck() -> void:
	if not run.data.get("pending", {}).is_empty() or str(run.data.get("phase", "")) not in ["intro", "town"]:
		_toast("先完成這次行程，再回鎮上整理招式。")
		return
	_deck_draft = run.data.deck.duplicate()
	_render_deck_editor()


func _render_deck_editor(scroll_position: int = 0) -> void:
	var panel = _modal("deck", Vector2(1320, 840), "角色與配招", "固定十張，每種最多兩張。配招需按「套用」儲存；精修會立即消耗心得，同名招式一併提升。")
	_picture(panel, Art.portrait(str(run.data.origin)), Vector2(28, 140), Vector2(130, 145))
	_label(panel, str(run.data.hero_name), Vector2(170, 154), Vector2(156, 64), 18, JADE, true)
	_label(panel, str(Data.ORIGINS[str(run.data.origin)].name), Vector2(170, 232), Vector2(156, 42), 18, MUTED)
	var labels: Dictionary = Creation.LABELS
	var index = 0
	for id in labels:
		var value: int = int(run.data.attributes.get(id, 4))
		_label(panel, "%s %d" % [labels[id], value], Vector2(30, 285 + index * 62), Vector2(78, 37), 19, JADE)
		var effect: String = Creation.effect_text(id, value)
		if id == "aptitude" and bool(run.data.get("aptitude_discount_used", false)):
			effect = "首次折扣已使用；之後精修每招需 2 點心得。"
		if id == "fortune" and bool(run.data.get("fortune_hint_used", false)):
			effect = "已發現一次提前提示；仍可透過調查探索江湖。"
		_label(panel, effect, Vector2(112, 285 + index * 62), Vector2(214, 58), 15, MUTED)
		index += 1
	var summary: Dictionary = Creation.summary(run.data.creation)
	var motivation: Dictionary = summary.get("motivation", {})
	_label(panel, "出行心願\n" + str(motivation.get("label", motivation.get("text", "親自走一段江湖路。"))), Vector2(30, 660), Vector2(290, 72), 18)
	_label(panel, "練習心得：%d\n精修按招式生效，兩張一起提升。\n練功、對練可累積心得。" % int(run.data.get("mastery", 0)), Vector2(30, 746), Vector2(290, 80), 16, MUTED)
	var rows = _scroll(panel, Vector2(350, 140), Vector2(940, 550))
	_deck_scroll = rows.get_parent() as ScrollContainer
	var ordered_cards: Array = run.data.learned_cards.duplicate()
	for id in Cards.CARDS:
		if id not in ordered_cards: ordered_cards.append(id)
	for id in ordered_cards:
		var learned: bool = id in run.data.learned_cards
		var upgraded: bool = id in run.data.upgraded_cards
		var card: Dictionary = Cards.card(id, upgraded)
		var count: int = _deck_draft.count(id)
		var row = Control.new()
		row.custom_minimum_size = Vector2(910, 184)
		rows.add_child(row)
		var box = _panel(row, Vector2.ZERO, Vector2(910, 180), Color("fffbee") if learned else Color("e8e7da"))
		_label(box, str(card.name), Vector2(16, 10), Vector2(465, 35), 23, JADE if learned else MUTED, true)
		_label(box, "真氣 %d　%s" % [int(card.cost), {"attack": "攻擊", "skill": "招式", "power": "心法"}.get(str(card.type), str(card.type))], Vector2(548, 14), Vector2(345, 30), 17, MUTED)
		_label(box, str(card.description) if learned else "未習得 · " + str(card.get("source_label", "從人物與探索中學習")), Vector2(16, 50), Vector2(520, 120), 18, INK if learned else MUTED)
		var minus = _button(box, "deck_remove_" + id, "-", Vector2(550, 75), Vector2(46, 45), _change_deck.bind(id, -1))
		minus.disabled = count == 0
		_label(box, "%d / 2" % count, Vector2(604, 82), Vector2(62, 32), 20)
		var plus = _button(box, "deck_add_" + id, "+", Vector2(670, 75), Vector2(46, 45), _change_deck.bind(id, 1))
		plus.disabled = not learned or count >= 2 or _deck_draft.size() >= 10
		var upgrade: Dictionary = run.upgrade_status(id)
		var improve = _button(box, "upgrade_" + id, "已精修" if upgraded else "精修 · %d" % int(upgrade.get("cost", 2)), Vector2(740, 75), Vector2(154, 45), _upgrade_card.bind(id))
		improve.disabled = not bool(upgrade.get("ok", false))
		improve.tooltip_text = str(upgrade.get("message", "")) + ("\n精修後：" + str(Cards.card(id, true).description) if learned and not upgraded else "")
	var check: Dictionary = Cards.validate_deck(_deck_draft, run.data.learned_cards)
	_label(panel, "目前 %d / 10 張　%s" % [_deck_draft.size(), "可出發" if check.ok else "請補齊十張再套用"], Vector2(350, 708), Vector2(900, 36), 21, JADE if check.ok else RED)
	_button(panel, "deck_cancel", "返回，保留原牌組", Vector2(350, 765), Vector2(325, 48), _close_overlay)
	var save_button = _button(panel, "deck_save", "套用配招", Vector2(950, 765), Vector2(340, 48), _commit_deck, true)
	save_button.disabled = not bool(check.ok)
	_deck_scroll.set_deferred("scroll_vertical", scroll_position)


func _change_deck(id: String, amount: int) -> void:
	var scroll_position = _deck_scroll.scroll_vertical if is_instance_valid(_deck_scroll) else 0
	if amount < 0 and id in _deck_draft:
		_deck_draft.erase(id)
	elif amount > 0 and id in run.data.learned_cards and _deck_draft.count(id) < 2 and _deck_draft.size() < 10:
		_deck_draft.append(id)
	_render_deck_editor(scroll_position)


func _commit_deck() -> void:
	var result: Dictionary = run.set_deck(_deck_draft)
	if result.ok:
		_close_overlay()
		_save()
	_toast(result.message, not result.ok)


func _upgrade_card(id: String) -> void:
	var scroll_position = _deck_scroll.scroll_vertical if is_instance_valid(_deck_scroll) else 0
	var result: Dictionary = run.upgrade_card(id)
	if result.ok:
		_save()
		_render_deck_editor(scroll_position)
	_toast(result.message, not result.ok)


func _confirm_exam() -> void:
	var early = run.remaining() > 0
	var panel = _modal("confirm", Vector2(850, 495), "收拾行囊，等候選拔" if early else "第八日 · 入門選拔")
	_label(panel, "你還有 %d 個時段。確定後會略過所有剩餘準備時間，直接來到第八日。" % run.remaining() if early else "七日準備已經結束。教頭會看你的劍，兩位引路人也會聽你說完這七日做過的事情。", Vector2(35, 110), Vector2(780, 135), 25)
	_label(panel, "可以重試切磋，也可以拱手認輸。錄取參考修為、人情與探索；同時得到兩派邀請時，由你選擇去向。", Vector2(35, 266), Vector2(780, 100), 21, MUTED)
	_button(panel, "cancel", "再想一想", Vector2(35, 400), Vector2(300, 58), _show_planner)
	_button(panel, "exam_confirm", "略過 %d 時段並參加" % run.remaining() if early else "走上劍坪", Vector2(435, 400), Vector2(380, 58), _begin_exam, true)


func _begin_exam() -> void:
	if run.remaining() > 0:
		var prepare: Dictionary = run.prepare_exam_now()
		if not prepare.ok:
			_toast(prepare.message, true)
			return
	var result: Dictionary = run.begin_exam()
	if not result.ok:
		_toast(result.message, true)
		return
	_refresh_hud()
	_save()
	_play_dialogue("exam_intro", "begin_exam_combat")


func _show_exam_results() -> void:
	_close_overlay()
	_discard_field()
	_refresh_hud()
	var panel = _modal("results", Vector2(1220, 690), "山門前的答覆", "你完成了教頭切磋。選擇接下來的路。" if run.data.exam_result.get("won", false) else "你拱手收劍。這七日的行動，仍值得一個認真的答覆。")
	for i in range(3):
		var id = ["zhaoling", "duyun", "stay"][i]
		var eligible = id == "stay" or id in run.data.exam_result.get("eligible", [])
		var card = _panel(panel, Vector2(30 + i * 397, 150), Vector2(367, 435), Color("f9f7eb"))
		_picture(card, Art.portrait(["shen", "lu", "lin"][i]), Vector2(70, 10), Vector2(227, 216))
		_label(card, Data.SCHOOLS[id].name, Vector2(20, 228), Vector2(327, 44), 28, JADE, true)
		_label(card, Data.SCHOOLS[id].description if eligible else "這次尚未達到入門條件。你做過的事情仍會留在紀事裡。", Vector2(20, 283), Vector2(327, 79), 19)
		var button = _button(card, "school_" + id, "留在望溪" if id == "stay" else ("接受邀請" if eligible else "尚未獲邀"), Vector2(20, 366), Vector2(327, 48), _choose_school.bind(id), eligible)
		button.disabled = not eligible
	_label(panel, "武學 %d　·　見識 %d　·　完成 %d 件不同的事　·　每一種出身都能走向兩派。" % [run.data.training, run.data.insight, run.data.completed.size()], Vector2(30, 620), Vector2(1150, 40), 20, MUTED)


func _choose_school(id: String) -> void:
	var result: Dictionary = run.choose_school(id)
	if not result.ok:
		_toast(result.message, true)
		return
	run.data.dialogue = {"title": "ending_" + id, "cursor": "", "revision": _story_revision, "after": "ending_done", "return_npc": ""}
	_save()
	_play_dialogue("ending_" + id, "ending_done")


func _show_ending() -> void:
	_close_overlay()
	_discard_field()
	_clear(_hud)
	_clear(_backdrop)
	_picture(_backdrop, Art.title_background(), Vector2.ZERO, Vector2(1440, 900), true)
	_shade(_backdrop, 0.4).mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel = _panel(_hud, Vector2(235, 100), Vector2(970, 700))
	_label(panel, "江湖未遠", Vector2(45, 35), Vector2(880, 72), 48, JADE, true)
	_label(panel, "入山之前 · " + str(Data.SCHOOLS[str(run.data.school)].name), Vector2(45, 122), Vector2(880, 60), 30, INK, true)
	_label(panel, "%s，以%s的身分出發。\n七日之後，你已帶著自己的故事走到這裡。" % [run.data.hero_name, Data.ORIGINS[str(run.data.origin)].name], Vector2(45, 215), Vector2(880, 105), 25)
	_label(panel, "武學 %d　·　見識 %d　·　完成 %d 件不同的事\n習得招式 %d 種　·　精修 %d 種　·　盤纏 %d 文" % [run.data.training, run.data.insight, run.data.completed.size(), run.data.learned_cards.size(), run.data.upgraded_cards.size(), run.data.money], Vector2(45, 350), Vector2(880, 95), 23, JADE)
	_label(panel, "首篇到此完成。再走一回，可以換個出身、試另一條修習路線。\n後續構想：門派修業 → 自由遊歷 → 江湖大事（尚未製作）。", Vector2(45, 488), Vector2(880, 87), 20, MUTED)
	_button(panel, "new_game", "再啟一程", Vector2(45, 603), Vector2(420, 56), _show_creation, true)
	_button(panel, "title", "回到卷首", Vector2(505, 603), Vector2(420, 56), _show_title)
