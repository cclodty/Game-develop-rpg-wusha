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
const TRIAL_ENEMIES = {
	"flurry": {"name": "連擊 · 快刀客", "description": "連續多段攻擊。觀察防護與一次反擊的時機。"},
	"armored": {"name": "重甲 · 守關人", "description": "厚重防護與反攻。試試拆防、保留和集中出手。"},
	"charging": {"name": "蓄勢 · 蓄勁者", "description": "準備後重擊。決定搶攻，或留下足夠防護。"},
	"counter": {"name": "反制 · 拆招客", "description": "直接攻牌會招致反制。可用伏針、變招和等待。"},
}

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
var _weapon_draft = "sword"
var _inner_draft = "guiyuan"
var _deck_scroll: ScrollContainer
var _lab_enemy = "flurry"
var _lab_seed_value = 1729
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
		if _overlay_kind == "deck":
			_close_deck()
		elif _overlay_kind == "attributes":
			_render_deck_editor()
		elif _overlay_kind in ["pause", "map", "journal", "npc", "confirm", "planner", "help", "trial_result"]:
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
	# Small controls must fit their declared rows instead of inheriting 24 px padding.
	if extent.y < 53:
		for style_key in ["normal", "hover", "pressed", "disabled"]:
			var compact_style = node.get_theme_stylebox(style_key) as StyleBoxFlat
			compact_style.content_margin_top = maxf(2.0, (extent.y - 29.0) / 2.0)
			compact_style.content_margin_bottom = compact_style.content_margin_top
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
	var lab_panel = _panel(_hud, Vector2(805, 420), Vector2(555, 342), Color(0.97, 0.95, 0.89, 0.97))
	_label(lab_panel, "武學試招", Vector2(28, 20), Vector2(500, 48), 32, JADE, true)
	_label(lab_panel, "三門內功 · 十二招式 · 四類對手\n直接比較牌組，自由配招與切換練法。", Vector2(28, 82), Vector2(500, 77), 21)
	_button(lab_panel, "lab_new", "開始新的試招", Vector2(28, 180), Vector2(500, 56), _new_lab, true)
	var lab_continue = _button(lab_panel, "lab_continue", "接續上次試招", Vector2(28, 249), Vector2(500, 53), _continue_lab)
	lab_continue.disabled = not FileAccess.file_exists(Run.LAB_SAVE_PATH) and not FileAccess.file_exists(Run.LAB_SAVE_PATH + ".bak")
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


func _is_lab() -> bool:
	return str(run.data.get("mode", "journey")) == "lab"


func _new_lab() -> void:
	run.new_lab("shouzhong")
	_lab_enemy = "flurry"
	_lab_seed_value = 1729
	_screen = "game"
	if not _muted and not _music.playing: _music.play()
	_show_lab_hub()
	_save()


func _continue_lab() -> void:
	var result: Dictionary = run.load_game(Run.LAB_SAVE_PATH)
	if not result.get("ok", false):
		_toast(str(result.get("message", "試招存檔未能讀取。")), true)
		return
	_screen = "game"
	if not _muted and not _music.playing: _music.play()
	_recover_screen()
	if bool(result.get("recovered", false)): _toast(str(result.message))


func _show_lab_hub() -> void:
	_close_overlay()
	_discard_field()
	_clear(_hud)
	_clear(_backdrop)
	_picture(_backdrop, Art.title_background(), Vector2.ZERO, Vector2(1440, 900), true)
	_shade(_backdrop, 0.25).mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel = _panel(_hud, Vector2(40, 35), Vector2(1360, 830))
	_label(panel, "武學試招 · 找到自己的打法", Vector2(30, 20), Vector2(1060, 55), 36, JADE, true)
	_label(panel, "試招可自由使用十二張牌與三門內功；所有能力固定為 5，不影響七日旅程。", Vector2(30, 86), Vector2(1260, 40), 20, MUTED)
	_button(panel, "lab_exit", "存檔回卷首", Vector2(1130, 24), Vector2(200, 48), _save_exit)
	var preset_ids = ["shouzhong", "xingyun", "guiyuan"]
	for i in range(preset_ids.size()):
		var id: String = preset_ids[i]
		var preset: Dictionary = Cards.PRESETS[id]
		var card = _panel(panel, Vector2(30 + i * 440, 140), Vector2(420, 227), Color("fffbef"))
		_picture(card, Art.portrait(["shen", "lu", "herbalist"][i]), Vector2(10, 40), Vector2(105, 126))
		_label(card, str(preset.name), Vector2(126, 15), Vector2(276, 40), 27, JADE, true)
		_label(card, str(preset.description), Vector2(126, 65), Vector2(276, 110), 17)
		_button(card, "preset_" + id, "套用基準牌組", Vector2(16, 174), Vector2(388, 39), _apply_lab_preset.bind(id))
	_label(panel, "選一位對手", Vector2(30, 385), Vector2(600, 35), 23, JADE)
	var enemy_ids: Array = TRIAL_ENEMIES.keys()
	for i in range(enemy_ids.size()):
		var id: String = enemy_ids[i]
		var info: Dictionary = TRIAL_ENEMIES[id]
		var card = _panel(panel, Vector2(30 + i * 330, 432), Vector2(310, 157), Color("eaf0e0") if _lab_enemy == id else Color("fffbef"))
		_label(card, str(info.name), Vector2(14, 10), Vector2(282, 33), 21, JADE, true)
		_label(card, str(info.description), Vector2(14, 49), Vector2(282, 60), 17)
		_button(card, "enemy_" + id, "已選對手" if _lab_enemy == id else "選擇對手", Vector2(14, 111), Vector2(282, 34), _select_lab_enemy.bind(id), _lab_enemy == id)
	var inner: Dictionary = Cards.INNERS.get(str(run.data.get("inner", "guiyuan")), {})
	var weapon: Dictionary = Cards.WEAPONS.get(str(run.data.get("weapon", "sword")), {})
	_label(panel, "目前配置：%s · %s · 十張招式" % [str(weapon.get("name", "")), str(inner.get("name", ""))], Vector2(30, 614), Vector2(790, 38), 23, JADE)
	_label(panel, "套用基準會清除試招練法；也可自由配招，再挑同一對手比較。\n每場有一份回復藥；消耗一真氣，每場最多使用一次。", Vector2(30, 659), Vector2(850, 65), 18, MUTED)
	_label(panel, "起手種子", Vector2(950, 618), Vector2(150, 30), 19)
	var seed_input = SpinBox.new()
	seed_input.position = Vector2(1100, 612)
	seed_input.size = Vector2(220, 45)
	seed_input.min_value = 1
	seed_input.max_value = 2147483646
	seed_input.step = 1
	seed_input.value = _lab_seed_value
	seed_input.add_theme_font_size_override("font_size", 20)
	panel.add_child(seed_input)
	seed_input.value_changed.connect(func(value): _lab_seed_value = int(value))
	_label(panel, "相同種子可重現起手；\n同一次重試不更換種子。", Vector2(950, 669), Vector2(370, 57), 17, MUTED)
	_button(panel, "deck", "自由配招與精修", Vector2(30, 750), Vector2(350, 55), _show_deck)
	_button(panel, "help", "查看交手規則", Vector2(405, 750), Vector2(310, 55), _show_help)
	_button(panel, "trial_start", "進場試招", Vector2(980, 750), Vector2(350, 55), _begin_trial, true)


func _apply_lab_preset(id: String) -> void:
	var result: Dictionary = run.apply_lab_preset(id)
	if result.ok:
		_show_lab_hub()
		_save()
	_toast(result.message, not result.ok)


func _select_lab_enemy(id: String) -> void:
	_lab_enemy = id
	_show_lab_hub()


func _begin_trial() -> void:
	var result: Dictionary = run.begin_trial(_lab_enemy, _lab_seed_value)
	if not result.ok:
		_toast(result.message, true)
		return
	_start_arena()


func _show_trial_result(report: Dictionary) -> void:
	var panel = _modal("trial_result", Vector2(850, 590), "這一場，已看見招式的配合", "試招成果只記在這裡，不發放七日旅程的武學、資源或人物信任。")
	_label(panel, "%s · %s" % [Cards.INNERS[str(run.data.inner)].name, TRIAL_ENEMIES.get(str(report.get("mode", _lab_enemy)), {}).get("name", "試招")], Vector2(35, 150), Vector2(780, 43), 26, JADE)
	_label(panel, "歷時 %d 回合　施展 %d 張牌\n承受 %d 傷害　剩餘氣血 %d\n消耗 %d 勢　運勁 %d 次　留牌 %d 次" % [int(report.get("turns", 0)), int(report.get("cards_played", 0)), int(report.get("damage_taken", 0)), int(report.get("hp_left", 0)), int(report.get("momentum_spent", 0)), int(report.get("boosts_used", 0)), int(report.get("retains_used", 0))], Vector2(35, 220), Vector2(780, 140), 24)
	_label(panel, "回想一次花勢或留牌的決定。換一門內功或幾張招式，再向同一對手試招。", Vector2(35, 391), Vector2(780, 70), 21, MUTED)
	_button(panel, "trial_again", "回到試招準備", Vector2(35, 495), Vector2(365, 58), _close_overlay, true)
	_button(panel, "trial_deck", "調整配招", Vector2(450, 495), Vector2(365, 58), _show_deck)


func _recover_screen() -> void:
	if _is_lab():
		var lab_pending: Dictionary = run.data.get("pending", {})
		if lab_pending.is_empty():
			_show_lab_hub()
		else:
			_lab_enemy = str(lab_pending.get("battle_mode", "flurry"))
			_lab_seed_value = int(lab_pending.get("seed", 1729))
			_start_arena(lab_pending.get("combat", {}), lab_pending.get("stage", "") == "defeat")
		return
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
	if _is_lab():
		_show_lab_hub()
		return
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
	if _is_lab() and not is_instance_valid(arena):
		_show_lab_hub()
		return
	_clear(_hud)
	_combat_status = null
	_combat_hp = null
	_combat_stamina = null
	var top = _panel(_hud, Vector2(20, 18), Vector2(1400, 94))
	_label(top, "江湖未遠", Vector2(20, 13), Vector2(230, 47), 34, JADE, true)
	_label(top, "入山之前", Vector2(22, 60), Vector2(250, 25), 16, GOLD)
	_label(top, "武學試招" if _is_lab() else "第 %d 日 · %s" % [run.day(), run.period()], Vector2(286, 14), Vector2(300, 44), 27, JADE, true)
	_label(top, "獨立試招 · 不影響七日旅程" if _is_lab() else ("選拔準備尚餘 %d 個時段" % run.remaining() if run.remaining() > 0 else "第八日 · 入門選拔"), Vector2(288, 60), Vector2(340, 25), 17, RED)
	var origin_name = str(Data.ORIGINS.get(run.data.get("origin", ""), {}).get("name", "旅人"))
	if _is_lab(): origin_name = "能力各 5"
	_label(top, str(run.data.get("hero_name", "小行")) + " · " + origin_name, Vector2(680, 17), Vector2(410, 32), 21)
	_label(top, "主修 %s　·　兵器 %s" % [Cards.INNERS[str(run.data.inner)].name, Cards.WEAPONS[str(run.data.weapon)].name] if _is_lab() else "盤纏 %d　藥 %d　武學 %d　見識 %d" % [run.data.get("money", 0), run.data.get("medicine", 0), run.data.get("training", 0), run.data.get("insight", 0)], Vector2(680, 58), Vector2(530, 29), 18, MUTED)
	_button(top, "pause", "暫停／存檔", Vector2(1220, 24), Vector2(160, 47), _show_pause)
	var side = _panel(_hud, Vector2(1132, 128), Vector2(288, 656))
	if is_instance_valid(arena):
		_label(side, "一招一式", Vector2(22, 22), Vector2(245, 44), 26, JADE, true)
		_combat_hp = _bar(side, Vector2(22, 86), Vector2(244, 24), RED)
		_combat_stamina = _bar(side, Vector2(22, 126), Vector2(244, 17), JADE)
		_combat_status = _label(side, "", Vector2(22, 164), Vector2(245, 254), 18)
		_label(side, "點牌後選普通或運勁。\n回合末可留一張，補至五張。\n勢跨回合，每輪最多得二。\n用藥耗一真氣，每場一次。", Vector2(22, 421), Vector2(245, 150), 17, MUTED)
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
	_label(foot, "WASD／方向鍵 移動　·　點地面行走　·　F 互動　·　Esc 暫停　·　Ctrl+S 存檔" if not is_instance_valid(arena) else "先選招式與目標，再按普通／運勁。　留住一張牌，為下一回合準備。", Vector2(24, 20), Vector2(1200, 37), 18, MUTED)
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
	var panel = _modal("confirm", Vector2(890, 700), str(activity.name), "安排前，看看這一程要付出什麼，以及本輪能遇到的機會。")
	_label(panel, activity.description, Vector2(35, 142), Vector2(820, 78), 23)
	_label(panel, "消耗 %d 個時段%s　｜　剩餘 %d → %d" % [int(activity.cost), "、%d 文" % int(activity.get("fee", 0)) if activity.get("fee", 0) else "", run.remaining(), maxi(0, run.remaining() - int(activity.cost))], Vector2(35, 235), Vector2(820, 45), 23, JADE)
	_label(panel, activity.reward_text, Vector2(35, 292), Vector2(820, 98), 20)
	var preview: Dictionary = run.activity_preview(id)
	_label(panel, str(preview.get("text", "")), Vector2(35, 400), Vector2(820, 134), 19, JADE)
	_label(panel, "外出包含來回、探索與戰鬥。重試不重扣時段，也不重抽本輪機會。", Vector2(35, 551), Vector2(820, 47), 17, MUTED)
	_button(panel, "cancel", "再想想", Vector2(35, 618), Vector2(250, 52), _show_planner)
	var button = _button(panel, "confirm_activity", "確定安排", Vector2(565, 618), Vector2(290, 52), _begin_activity.bind(id), true)
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
	var mode = str(run.data.pending.get("battle_mode", ""))
	if mode.is_empty(): mode = "exam" if _pending_id() == "exam" else str(Data.ACTIVITIES[_pending_id()].get("battle", "practice"))
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
	_combat_status.text = "氣血 %d／%d\n防護 %d　真氣 %d\n勢 %d / 3　本輪已得 %d / 2\n第 %d 回合\n\n%s · %s\n回復藥 %d　%s" % [int(status.get("hp", 0)), int(status.get("max_hp", 100)), int(status.get("block", 0)), int(status.get("energy", 0)), int(status.get("momentum", 0)), int(status.get("momentum_gained", 0)), int(status.get("turn", 1)), str(Cards.INNERS[str(run.data.inner)].name), str(Cards.WEAPONS[str(run.data.weapon)].name), int(status.get("medicine_left", 0)), "本場已用" if int(status.get("medicine_used", 0)) > 0 else "本場可用一次"]


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
	elif _is_lab():
		var result: Dictionary = run.complete_activity("success", report)
		if result.ok:
			_show_lab_hub()
			_save()
			_show_trial_result(report)
		else: _toast(result.message, true)
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
	_label(panel, "重試保留相同的起手種子，恢復本場開始的氣血與回復藥。\n\n也可回試招準備，換內功、調整牌組，或改挑另一種對手。" if _is_lab() else "重試會恢復本場開始時的氣血與回復藥，不再消耗行程。\n\n也可以就此收劍；選拔認輸後，師傅仍會參考這七日做過的事。", Vector2(35, 153), Vector2(710, 160), 23)
	_button(panel, "retry", "再試一次 · 不耗時", Vector2(35, 355), Vector2(335, 60), _retry_combat, true)
	_button(panel, "retreat", "回試招準備" if _is_lab() else ("拱手認輸" if _pending_id() == "exam" else "撤退回鎮"), Vector2(410, 355), Vector2(335, 60), _retreat_now)


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
	_label(panel, "回到試招準備後可以修改牌組；這次試招不影響正式旅程的時間與物資。" if _is_lab() else ("選拔認輸會直接評定去向，已完成的修習與委託仍然有效。" if _pending_id() == "exam" else "已投入的時段不會退回。退出後，本次尚未完成的獎勵將不會發放；用過的藥也會計入。"), Vector2(35, 105), Vector2(710, 150), 24)
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
	if _is_lab(): _show_lab_hub()
	elif was_exam: _show_exam_results()
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
	_label(panel, "城鎮：WASD／方向鍵，或點地面行走；F 互動。\n戰鬥：點選牌與目標，再按普通施展或運勁。\n每回合 3 真氣，可留一張牌，補至 5 張。\n勢跨回合保留，上限 3，每輪最多獲得 2。\n\nCtrl+S：存檔　　Esc：暫停／返回\n閱讀對話時，Enter 繼續，數字鍵選擇回應。", Vector2(35, 145), Vector2(730, 284), 22)
	_button(panel, "resume", "繼續這一程", Vector2(35, 480), Vector2(350, 60), _close_overlay, true)
	_button(panel, "save_exit", "存檔回卷首", Vector2(415, 480), Vector2(350, 60), _save_exit)


func _show_help() -> void:
	var panel = _modal("help", Vector2(1040, 710), "初行手札", "先認識自己，再慢慢學會怎樣出劍。")
	_label(panel, "一、先認識自己的打法\n「武學試招」可直接比較三門內功與四類對手；「啟程」則透過六個情境建立主角，再安排七日的學武與探索。兩種進度分開保存。\n\n二、主兵器、內功與十張招式\n鎮上免費配招，同名最多兩張。劍招需要持劍；拳掌、暗器與身法可混搭。主修內功決定如何蓄勢與耗勢，精修可選不同練法。\n\n三、看清意圖，選擇普通或運勁\n每回合有三真氣，最多留一張手牌，下回合補至五張。勢上限三，每輪最多獲得二；普通出招不自動花勢。反擊與伏針按牌面時機結算。\n\n用藥耗一真氣、每場一次。戰敗可重試；讀檔不重抽奇遇，也不重發活動獎勵。", Vector2(35, 142), Vector2(970, 445), 21)
	_button(panel, "close", "記下了，繼續", Vector2(690, 620), Vector2(315, 55), _close_overlay, true)


func _show_deck() -> void:
	if not run.data.get("pending", {}).is_empty() or str(run.data.get("phase", "")) not in ["intro", "town"]:
		_toast("先完成這次行程，再回鎮上整理招式。")
		return
	_deck_draft = run.data.deck.duplicate()
	_weapon_draft = str(run.data.weapon)
	_inner_draft = str(run.data.inner)
	_render_deck_editor()


func _render_deck_editor(scroll_position: int = 0) -> void:
	var panel = _modal("deck", Vector2(1320, 840), "角色與配招", "兵器、內功與十張牌需按「套用」儲存。精修與練法切換會立即保存；同名兩張共用練法。")
	_picture(panel, Art.portrait(str(run.data.origin)), Vector2(28, 140), Vector2(120, 125))
	_label(panel, str(run.data.hero_name), Vector2(162, 155), Vector2(164, 60), 18, JADE, true)
	_label(panel, "試招 · 能力各 5" if _is_lab() else str(Data.ORIGINS[str(run.data.origin)].name), Vector2(162, 226), Vector2(164, 40), 17, MUTED)
	_label(panel, "主兵器", Vector2(30, 281), Vector2(290, 30), 20, JADE)
	var weapons: Array = Cards.WEAPONS.keys()
	for index in range(weapons.size()):
		var id: String = weapons[index]
		var choose = _button(panel, "weapon_" + id, str(Cards.WEAPONS[id].name), Vector2(30 + (index % 2) * 150, 319 + (index / 2) * 43), Vector2(140, 36), _choose_weapon.bind(id), id == _weapon_draft)
		choose.tooltip_text = str(Cards.WEAPONS[id].description)
	_label(panel, "主修內功", Vector2(30, 416), Vector2(290, 30), 20, JADE)
	var inners: Array = Cards.INNERS.keys()
	for index in range(inners.size()):
		var id: String = inners[index]
		var choose = _button(panel, "inner_" + id, str(Cards.INNERS[id].name), Vector2(30 + index * 98, 456), Vector2(94, 39), _choose_inner.bind(id), id == _inner_draft)
		choose.add_theme_font_size_override("font_size", 16)
		choose.disabled = id not in run.data.learned_inners
		choose.tooltip_text = str(Cards.INNERS[id].description) + "\n習得：" + str(Cards.INNERS[id].source_label)
	_label(panel, str(Cards.INNERS[_inner_draft].description), Vector2(30, 512), Vector2(296, 122), 16)
	var attributes: Array = Creation.ATTRIBUTE_KEYS
	for index in range(attributes.size()):
		var id: String = attributes[index]
		var value: int = int(run.data.attributes[id])
		_label(panel, "%s %d" % [Creation.LABELS[id], value], Vector2(30 + (index % 3) * 100, 647 + (index / 3) * 31), Vector2(96, 30), 18, JADE)
	_button(panel, "attributes", "能力用途與出行心願", Vector2(30, 719), Vector2(290, 39), _show_attributes)
	_label(panel, "試招已開放三種精修，可免費比較練法。" if _is_lab() else "練習心得：%d\n練功、對練取得心得，精修需 2 點。" % int(run.data.get("mastery", 0)), Vector2(30, 775), Vector2(290, 55), 16, MUTED)
	var rows = _scroll(panel, Vector2(350, 140), Vector2(940, 550))
	_deck_scroll = rows.get_parent() as ScrollContainer
	var ordered_cards: Array = run.data.learned_cards.duplicate()
	for id in Cards.CARDS:
		if id not in ordered_cards: ordered_cards.append(id)
	for id in ordered_cards:
		var learned: bool = id in run.data.learned_cards
		var unlocked: bool = id in run.data.upgraded_cards
		var branch: String = str(run.data.refinements.get(id, ""))
		var card: Dictionary = Cards.card(id, branch)
		var count: int = _deck_draft.count(id)
		var row = Control.new()
		row.custom_minimum_size = Vector2(910, 228)
		rows.add_child(row)
		var box = _panel(row, Vector2.ZERO, Vector2(910, 224), Color("fffbee") if learned else Color("e8e7da"))
		_label(box, str(card.name), Vector2(16, 10), Vector2(465, 35), 23, JADE if learned else MUTED, true)
		var weapon_text = "通用" if card.weapon == "any" else "需" + str(Cards.WEAPONS[card.weapon].name)
		_label(box, "真氣 %d　%s　%s" % [int(card.cost), str(Cards.TYPE_LABELS[card.type]), weapon_text], Vector2(548, 14), Vector2(345, 32), 17, MUTED)
		_label(box, str(card.description) if learned else "未習得 · " + str(card.get("source_label", "從人物與探索中學習")), Vector2(16, 55), Vector2(525, 164), 17, INK if learned else MUTED)
		var minus = _button(box, "deck_remove_" + id, "-", Vector2(566, 62), Vector2(46, 43), _change_deck.bind(id, -1))
		minus.disabled = count == 0
		_label(box, "%d / 2" % count, Vector2(629, 67), Vector2(70, 35), 20)
		var plus = _button(box, "deck_add_" + id, "+", Vector2(712, 62), Vector2(46, 43), _change_deck.bind(id, 1))
		plus.disabled = not learned or count >= 2 or _deck_draft.size() >= 10 or (card.weapon != "any" and card.weapon != _weapon_draft)
		plus.tooltip_text = "此招式需要" + str(Cards.WEAPONS.get(card.weapon, {}).get("name", "對應兵器")) if card.weapon != "any" and card.weapon != _weapon_draft else "加入十張出戰牌"
		if id in Cards.REFINABLE:
			var upgrade: Dictionary = run.upgrade_status(id)
			var improve = _button(box, "upgrade_" + id, "已解鎖精修，選擇練法" if unlocked else "精修 · %d 心得" % int(upgrade.get("cost", 2)), Vector2(566, 116), Vector2(326, 40), _upgrade_card.bind(id))
			improve.add_theme_font_size_override("font_size", 16)
			improve.disabled = not bool(upgrade.get("ok", false))
			improve.tooltip_text = str(upgrade.get("message", ""))
			var branches = ["", "stable", "specialist"] if _is_lab() else ["stable", "specialist"]
			var width = 102 if _is_lab() else 158
			for branch_index in range(branches.size()):
				var choice: String = branches[branch_index]
				var label = "原式" if choice.is_empty() else str(Cards.REFINEMENT_LABELS[choice])
				var change = _button(box, "refine_" + id + "_" + ("none" if choice.is_empty() else choice), label, Vector2(566 + branch_index * (width + 10), 171), Vector2(width, 39), _set_refinement.bind(id, choice), branch == choice)
				change.disabled = not unlocked
				change.add_theme_font_size_override("font_size", 16)
				change.tooltip_text = "用未精修數值試招" if choice.is_empty() else str(Cards.REFINEMENTS[id][choice].description)
	var check: Dictionary = Cards.validate_deck(_deck_draft, run.data.learned_cards, _weapon_draft)
	_label(panel, "目前 %d / 10 張　%s" % [_deck_draft.size(), "配置可用" if check.ok else str(check.message)], Vector2(350, 704), Vector2(930, 50), 19, JADE if check.ok else RED)
	_button(panel, "deck_cancel", "返回，保留原配置", Vector2(350, 765), Vector2(325, 48), _close_deck)
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
	var result: Dictionary = run.set_loadout(_deck_draft, _weapon_draft, _inner_draft)
	if result.ok:
		_close_deck()
		_save()
	_toast(result.message, not result.ok)


func _upgrade_card(id: String) -> void:
	var scroll_position = _deck_scroll.scroll_vertical if is_instance_valid(_deck_scroll) else 0
	var result: Dictionary = run.upgrade_card(id)
	if result.ok:
		_save()
		_render_deck_editor(scroll_position)
	_toast(result.message, not result.ok)


func _choose_weapon(id: String) -> void:
	_weapon_draft = id
	_render_deck_editor(_deck_scroll.scroll_vertical if is_instance_valid(_deck_scroll) else 0)


func _choose_inner(id: String) -> void:
	_inner_draft = id
	_render_deck_editor(_deck_scroll.scroll_vertical if is_instance_valid(_deck_scroll) else 0)


func _set_refinement(id: String, branch: String) -> void:
	var scroll_position = _deck_scroll.scroll_vertical if is_instance_valid(_deck_scroll) else 0
	var result: Dictionary = run.set_refinement(id, branch)
	if result.ok:
		_save()
		_render_deck_editor(scroll_position)
	_toast(result.message, not result.ok)


func _close_deck() -> void:
	if _is_lab(): _show_lab_hub()
	else: _close_overlay()


func _show_attributes() -> void:
	var info: Dictionary = Creation.summary(run.data.creation)
	var panel = _modal("attributes", Vector2(1240, 800), "能力與出行心願", "%s · %s" % [str(run.data.hero_name), str(info.motivation.label)])
	for index in range(Creation.ATTRIBUTE_KEYS.size()):
		var id: String = Creation.ATTRIBUTE_KEYS[index]
		var value: int = int(run.data.attributes[id])
		var card = _panel(panel, Vector2(30 + (index % 2) * 595, 145 + (index / 2) * 175), Vector2(575, 158), Color("fffbef"))
		_label(card, "%s %d" % [Creation.LABELS[id], value], Vector2(18, 10), Vector2(535, 45), 27, JADE, true)
		var description: String = Creation.effect_text(id, value)
		if id == "aptitude" and bool(run.data.get("aptitude_discount_used", false)): description += " 首次優惠已使用。"
		if id == "fortune" and bool(run.data.get("fortune_hint_used", false)): description += " 本輪提前提示已使用。"
		_label(card, description, Vector2(18, 66), Vector2(535, 80), 21)
	_label(panel, "能力提供便利。牌組與內功決定打法，反擊與伏針不重複獲得力道加成。", Vector2(30, 682), Vector2(1180, 38), 19, MUTED)
	_button(panel, "attributes_back", "回到配招", Vector2(870, 735), Vector2(340, 46), _render_deck_editor, true)


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
