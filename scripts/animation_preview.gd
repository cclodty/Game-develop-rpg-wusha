extends Control
## A real-time atlas viewer: every displayed pose is a separate drawn frame.

signal closed

const Bank = preload("res://scripts/animation_bank.gd")
const Data = preload("res://scripts/game_data.gd")
const FONT = preload("res://assets/fonts/JianghuSans.otf")
const SERIF = preload("res://assets/fonts/JianghuSerif.otf")
const PAPER = Color("f6f0df")
const INK = Color("243e39")
const JADE = Color("315d51")
const GOLD = Color("b58b4d")
const STRIP_COLUMNS = 6
const POSE_AREA = Rect2(365, 207, 688, 320)
const ACTORS = ["courier", "herbalist", "performer", "bandit", "lancer", "examiner", "shen", "lu", "tao", "zhou", "xiao", "lin"]
const CLIPS = ["idle", "walk", "attack", "dodge", "hurt", "defeat"]
const CLIP_NAMES = {"idle": "待機", "walk": "行走", "attack": "出招", "dodge": "閃避", "hurt": "受擊", "defeat": "倒地"}
const ACTOR_NAMES = {"courier": "驛站主角", "herbalist": "藥鋪主角", "performer": "戲班主角", "bandit": "短刀客", "lancer": "長兵客", "examiner": "考核教頭"}
var action_buttons: Dictionary = {}
var current_actor = "courier"
var current_clip = "walk"
var frame_index = 0
var playing = true
var elapsed = 0.0
var mirrored = false
var playback_rate = 1.0
var _caption: Label
var _actor_title: Label
var _note: Label
var _thumbs: Array[TextureRect] = []
var _previous_frame = -1
var _standalone = false


func _ready() -> void:
	_standalone = get_tree().current_scene == self
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Theme.new()
	theme.default_font = FONT
	theme.default_font_size = 19
	var background = ColorRect.new()
	background.color = Color("e4e8d9")
	background.size = Vector2(1440, 900)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	# Canvas is drawn behind the controls and above the opaque backdrop.
	var canvas = Control.new()
	canvas.name = "PoseCanvas"
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.size = Vector2(1440, 900)
	canvas.draw.connect(_draw_pose.bind(canvas))
	add_child(canvas)
	_label(self, "江湖身影 · 逐格動畫", Vector2(32, 21), Vector2(1000, 50), 34, true)
	_label(self, "選一位角色，看看每一步、每一劍如何連起來。可暫停並逐格檢視。", Vector2(34, 78), Vector2(1120, 30), 18)
	_button(self, "preview_back", "返回遊戲", Vector2(1230, 35), Vector2(178, 48), _close)
	var people = _panel(Vector2(32, 126), Vector2(300, 734))
	_label(people, "角色", Vector2(20, 21), Vector2(250, 40), 27, true)
	for i in range(ACTORS.size()):
		var id: String = ACTORS[i]
		_button(people, "actor_" + id, _actor_name(id), Vector2(16 + (i % 2) * 139, 82 + (i / 2) * 65), Vector2(130, 53), select_actor.bind(id))
	_actor_title = _label(people, "", Vector2(20, 505), Vector2(260, 45), 25, true)
	_note = _label(people, "", Vector2(20, 565), Vector2(260, 135), 19)
	var actions = _panel(Vector2(1084, 126), Vector2(324, 734))
	_label(actions, "動作", Vector2(20, 21), Vector2(280, 40), 27, true)
	for i in range(CLIPS.size()):
		var clip: String = CLIPS[i]
		_button(actions, "clip_" + clip, CLIP_NAMES[clip], Vector2(20, 82 + i * 65), Vector2(284, 53), select_clip.bind(clip))
	_button(actions, "preview_flip", "朝向：右", Vector2(20, 505), Vector2(284, 52), _flip)
	_button(actions, "preview_speed", "播放：原速", Vector2(20, 573), Vector2(284, 52), _speed)
	_label(actions, "空白鍵：播放／暫停\n方向鍵：前後一格\nEsc：返回", Vector2(20, 645), Vector2(284, 75), 17)
	_caption = _label(self, "", Vector2(365, 147), Vector2(688, 45), 23, true)
	_button(self, "preview_previous", "上一格", Vector2(365, 546), Vector2(190, 46), step_frame.bind(-1))
	_button(self, "preview_pause", "暫停", Vector2(575, 546), Vector2(268, 46), toggle_playing, true)
	_button(self, "preview_step", "下一格", Vector2(863, 546), Vector2(190, 46), step_frame.bind(1))
	var strip = _panel(Vector2(365, 612), Vector2(688, 248))
	for i in range(Bank.FRAME_COUNT):
		var column: int = i % STRIP_COLUMNS
		var row: int = i / STRIP_COLUMNS
		var thumb = TextureRect.new()
		thumb.position = Vector2(14 + column * 112, 8 + row * 120)
		thumb.size = Vector2(100, 74)
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strip.add_child(thumb)
		_thumbs.append(thumb)
		_button(strip, "frame_%d" % i, str(i + 1), Vector2(14 + column * 112, 84 + row * 120), Vector2(100, 30), select_frame.bind(i))
	_refresh_controls()


func _process(delta: float) -> void:
	if playing:
		elapsed += delta * playback_rate
		var duration = Bank.clip_duration(current_clip)
		var cycle = duration if current_clip in ["idle", "walk"] else duration + 0.7
		var phase = fmod(elapsed, cycle)
		frame_index = Bank.frame_index(current_clip, minf(1.0, phase / duration))
	if frame_index != _previous_frame:
		_previous_frame = frame_index
		_refresh_frame()
	get_node("PoseCanvas").queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo: return
	match event.keycode:
		KEY_SPACE: toggle_playing()
		KEY_LEFT: step_frame(-1)
		KEY_RIGHT: step_frame(1)
		KEY_ESCAPE:
			# Standalone scene changes detach this Control immediately.
			get_viewport().set_input_as_handled()
			_close()
			return
		_: return
	get_viewport().set_input_as_handled()


func _draw_pose(canvas: Control) -> void:
	var area = POSE_AREA
	canvas.draw_style_box(_style(Color("f8f5e9"), Color("c9ceb9")), area)
	for y in range(ceili(area.size.y / 50.0)):
		for x in range(13):
			if (x + y) % 2 == 0:
				canvas.draw_rect(Rect2(365 + x * 52, 207 + y * 50, minf(52, 688 - x * 52), minf(50, area.size.y - y * 50)), Color(0.23, 0.38, 0.29, 0.025))
	var ground = Vector2(709, 495)
	canvas.draw_line(Vector2(425, ground.y), Vector2(993, ground.y), Color("c0ccb4"), 2)
	canvas.draw_set_transform(ground + Vector2(0, 2), 0, Vector2(1, 0.22))
	canvas.draw_circle(Vector2.ZERO, 70, Color(0.16, 0.26, 0.20, 0.12))
	canvas.draw_set_transform(ground, 0, Vector2(-1 if mirrored else 1, 1))
	var texture = Bank.frame(current_actor, current_clip, (float(frame_index) + 0.01) / float(Bank.FRAME_COUNT))
	if texture:
		canvas.draw_texture_rect(texture, Bank.draw_rect(current_actor, 230), false)
	canvas.draw_set_transform(Vector2.ZERO)


func _actor_name(id: String) -> String:
	return str(ACTOR_NAMES.get(id, Data.NPCS.get(id, {}).get("name", id)))


func select_actor(id: String) -> void:
	if id not in ACTORS: return
	current_actor = id
	if id in Data.NPCS: current_clip = "idle"
	elapsed = 0.0
	frame_index = 0
	_refresh_controls()


func select_clip(clip: String) -> void:
	if clip not in CLIPS or (current_actor in Data.NPCS and clip != "idle"): return
	current_clip = clip
	elapsed = 0.0
	frame_index = 0
	_refresh_controls()


func toggle_playing() -> void:
	playing = not playing
	_refresh_frame()


func select_frame(index: int) -> void:
	playing = false
	frame_index = clampi(index, 0, Bank.FRAME_COUNT - 1)
	elapsed = float(frame_index) / float(Bank.FRAME_COUNT) * Bank.clip_duration(current_clip)
	_refresh_frame()


func step_frame(offset: int) -> void:
	select_frame(posmod(frame_index + offset, Bank.FRAME_COUNT))


func _flip() -> void:
	mirrored = not mirrored
	action_buttons.preview_flip.text = "朝向：左" if mirrored else "朝向：右"


func _speed() -> void:
	playback_rate = 0.5 if playback_rate == 1.0 else 1.0
	action_buttons.preview_speed.text = "播放：半速" if playback_rate == 0.5 else "播放：原速"


func animation_state() -> Dictionary:
	return {"actor": current_actor, "clip": current_clip, "frame": frame_index, "playing": playing, "elapsed": elapsed, "mirrored": mirrored, "rate": playback_rate, "frame_count": Bank.FRAME_COUNT}


func _refresh_controls() -> void:
	_actor_title.text = _actor_name(current_actor)
	_note.text = "十二格日常動作。\n\n眨眼、翻頁、理袖與招呼，讓鎮上的人物有自己的生活節奏。" if current_actor in Data.NPCS else "六種動作，每組十二格。\n\n動作會重播；出招、受擊與倒地結束後稍停，再從第一格開始。"
	for id in ACTORS:
		action_buttons["actor_" + id].modulate = Color("d5e8c5") if id == current_actor else Color.WHITE
	for clip in CLIPS:
		action_buttons["clip_" + clip].disabled = current_actor in Data.NPCS and clip != "idle"
		action_buttons["clip_" + clip].modulate = Color("d5e8c5") if clip == current_clip else Color.WHITE
	for i in range(Bank.FRAME_COUNT): _thumbs[i].texture = Bank.frame(current_actor, current_clip, (float(i) + 0.01) / float(Bank.FRAME_COUNT))
	_refresh_frame()


func _refresh_frame() -> void:
	_caption.text = "%s · %s　　第 %d／%d 格" % [_actor_name(current_actor), CLIP_NAMES[current_clip], frame_index + 1, Bank.FRAME_COUNT]
	action_buttons.preview_pause.text = "暫停" if playing else "播放"
	for i in range(Bank.FRAME_COUNT): action_buttons["frame_%d" % i].modulate = Color("d5e8c5") if i == frame_index else Color.WHITE


func _close() -> void:
	if _standalone: get_tree().change_scene_to_file("res://scenes/main.tscn")
	else: closed.emit()


func _style(color: Color, edge: Color = Color("c9ceb9")) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	return style


func _panel(pos: Vector2, extent: Vector2) -> Panel:
	var panel = Panel.new()
	panel.position = pos
	panel.size = extent
	panel.add_theme_stylebox_override("panel", _style(PAPER))
	add_child(panel)
	return panel


func _label(parent: Node, text: String, pos: Vector2, extent: Vector2, font_size: int, serif = false) -> Label:
	var label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	label.position = pos
	label.size = extent
	label.add_theme_font_override("font", SERIF if serif else FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", INK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _button(parent: Node, key: String, text: String, pos: Vector2, extent: Vector2, callback: Callable, primary = false) -> Button:
	var button = Button.new()
	button.position = pos
	button.size = extent
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("normal", _style(JADE if primary else Color("fffbef")))
	button.add_theme_stylebox_override("hover", _style(Color("427563") if primary else Color("e7eeda"), GOLD))
	button.add_theme_stylebox_override("pressed", _style(Color("24473f") if primary else Color("d7e2c9"), GOLD))
	button.add_theme_stylebox_override("disabled", _style(Color("e3e4d8")))
	button.add_theme_color_override("font_color", PAPER if primary else INK)
	button.add_theme_color_override("font_hover_color", PAPER if primary else INK)
	button.add_theme_color_override("font_pressed_color", PAPER if primary else INK)
	button.add_theme_color_override("font_disabled_color", Color("92988b"))
	button.pressed.connect(callback)
	parent.add_child(button)
	action_buttons[key] = button
	return button
