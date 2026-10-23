class_name WeiyuanCreationJourney
extends Control
## A six-scene prologue. Every choice and page is held in the run's saved draft.

signal changed
signal confirmed
signal closed

const Creation = preload("res://scripts/character_creation.gd")
const Art = preload("res://scripts/art.gd")
const Data = preload("res://scripts/game_data.gd")
const FONT = preload("res://assets/fonts/JianghuSans.otf")
const SERIF = preload("res://assets/fonts/JianghuSerif.otf")
const PAPER = Color("f6f0df")
const INK = Color("243e39")
const JADE = Color("315d51")
const MUTED = Color("66746b")
const GOLD = Color("b58b4d")
var run: RefCounted
var action_buttons: Dictionary = {}
var _message = ""
var _confirming = false

func configure(state: RefCounted) -> void:
	run = state
	if is_inside_tree(): _render()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = Theme.new()
	theme.default_font = FONT
	theme.default_font_size = 20
	if run != null: _render()

func _render() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	action_buttons.clear()
	var creation: Dictionary = run.data.creation
	var valid = Creation.validate(creation)
	if not valid.ok:
		_background("wangxi")
		_label(self, "這一程暫時無法接續", Vector2(70, 100), Vector2(1200, 70), 40, JADE, true)
		_label(self, str(valid.message), Vector2(70, 220), Vector2(1200, 170), 26)
		_button(self, "save_exit", "返回卷首", Vector2(70, 690), Vector2(300, 60), _close)
		return
	match str(creation.page):
		"summary": _show_summary()
		"review": _show_review()
		_: _show_story(str(creation.page) == "aftermath")

func _background(location: String) -> void:
	var ground = ColorRect.new()
	ground.color = PAPER
	ground.size = Vector2(1440, 900)
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ground)
	var picture = TextureRect.new()
	picture.texture = Art.location(location)
	picture.position = Vector2(930, 0)
	picture.size = Vector2(510, 900)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.modulate = Color(1, 1, 1, 0.2)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(picture)

func _show_story(aftermath: bool) -> void:
	var creation: Dictionary = run.data.creation
	var index = int(creation.question)
	var content: Dictionary = Creation.response(creation, index, run.data.origin, run.data.hero_name) if aftermath else Creation.scene(creation, index, run.data.origin, run.data.hero_name)
	_background(str(content.location))
	_label(self, "抵達之前 · " + str(Creation.QUESTIONS[index].chapter), Vector2(38, 23), Vector2(1030, 38), 21, JADE)
	_label(self, str(Creation.QUESTIONS[index].title), Vector2(36, 73), Vector2(1130, 65), 40, INK, true)
	_button(self, "save_exit", "記下這一頁，稍後再走", Vector2(1130, 27), Vector2(275, 47), _close)
	var story = _panel(self, Vector2(36, 150), Vector2(1005, 426))
	_label(story, str(content.speaker) + (" · 這一步之後" if aftermath else ""), Vector2(24, 13), Vector2(945, 42), 25, JADE, true)
	var scroller = _scroll(story, Vector2(24, 68), Vector2(954, 330))
	var body = _flow_label(str(content.body), 914, 22, INK)
	scroller.add_child(body)
	var portrait = TextureRect.new()
	portrait.texture = Art.portrait(str(content.portrait))
	portrait.position = Vector2(1070, 180)
	portrait.size = Vector2(320, 346)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(portrait)
	_label(self, "先把今天走完。\n七日行程，明晨才開始。", Vector2(1068, 520), Vector2(326, 72), 20, MUTED)
	if aftermath:
		_label(self, "你做的事，有了回聲。下一步仍由你自己決定。", Vector2(42, 624), Vector2(1310, 50), 24, JADE)
		_button(self, "back", "回看這一步", Vector2(40, 763), Vector2(280, 62), _return_to_question)
		_button(self, "continue", "回到能力總覽" if creation.review_return else ("看看自己帶來了什麼" if index == 5 else "接著往前走"), Vector2(950, 763), Vector2(450, 62), _continue, true)
	else:
		_label(self, str(content.prompt), Vector2(42, 592), Vector2(1330, 44), 23, JADE)
		for choice in range(3):
			_button(self, "answer_%d" % choice, str(content.choices[choice].label), Vector2(40, 648 + choice * 66), Vector2(1360, 57), _answer.bind(choice), false, 22)
		var back = _button(self, "back", "返回回顧" if creation.review_return else "回看上一段", Vector2(40, 851), Vector2(230, 36), _back, false, 17)
		back.disabled = index == 0 and not creation.review_return
	_label(self, "｜".repeat(index + 1) + " · " + str(index + 1) + " / 6", Vector2(1110, 851), Vector2(280, 36), 17, MUTED)

func _show_summary() -> void:
	_background("wangxi")
	var creation: Dictionary = run.data.creation
	var info = Creation.summary(creation)
	var source = str(creation.get("move_source", ""))
	_label(self, "這一程，成為你的起點", Vector2(36, 25), Vector2(1070, 65), 39, JADE, true)
	_button(self, "save_exit", "記下結果，稍後再走", Vector2(1130, 34), Vector2(274, 48), _close)
	_label(self, "%s · %s · %s" % [run.data.hero_name, Data.ORIGINS[run.data.origin].name, info.motivation.label], Vector2(40, 99), Vector2(1340, 45), 23)
	_label(self, "每項從 4 起步，六次選擇各帶來 1 點。合計 30 點；這只是起點，門派仍由你選。", Vector2(40, 146), Vector2(1340, 45), 20, MUTED)
	for i in range(6):
		var attribute: String = Creation.ATTRIBUTE_KEYS[i]
		var value = int(info.attributes[attribute])
		var card = _panel(self, Vector2(36 + (i % 2) * 333, 208 + (i / 2) * 177), Vector2(320, 164), Color("fffbef"))
		_label(card, "%s　%d" % [Creation.LABELS[attribute], value], Vector2(16, 4), Vector2(286, 48), 28, JADE, true)
		_label(card, Creation.effect_text(attribute, value), Vector2(16, 53), Vector2(286, 65), 17)
		var minus = _button(card, "move_" + attribute, "已選作挪出" if source == attribute else "挪出一點", Vector2(14, 125), Vector2(136, 30), _choose_source.bind(attribute), source == attribute, 16)
		minus.disabled = info.moves_used >= 2 or value <= 2
		var plus = _button(card, "to_" + attribute, "挪到這裡", Vector2(167, 125), Vector2(137, 30), _move_to.bind(attribute), not source.is_empty() and source != attribute, 16)
		plus.disabled = source.is_empty() or source == attribute or info.moves_used >= 2 or value >= 8
	var review = _panel(self, Vector2(722, 208), Vector2(680, 520))
	_label(review, "你如何走到這裡", Vector2(20, 12), Vector2(630, 44), 27, JADE, true)
	var list = _scroll(review, Vector2(20, 66), Vector2(640, 431))
	for row in info.answer_rows:
		list.add_child(_flow_label("%s　｜　%s\n%s" % [row.question, row.effect, row.answer], 603, 18, INK, 92))
	list.add_child(_flow_label("初學交鋒\n" + Creation.card_advice(creation), 603, 18, JADE, 145))
	var status = "已微調 %d / 2 點；每項維持 2–8。" % info.moves_used
	if not source.is_empty(): status += " 已選%s，請選另一項挪入。" % Creation.LABELS[source]
	_label(self, _message if not _message.is_empty() else status, Vector2(40, 742), Vector2(1350, 46), 19, JADE)
	_button(self, "reset_adjustments", "重設微調", Vector2(40, 800), Vector2(180, 55), _reset)
	_button(self, "cancel_move", "取消挪點", Vector2(233, 800), Vector2(180, 55), _cancel_move).disabled = source.is_empty()
	_button(self, "review", "回看／改選故事", Vector2(430, 800), Vector2(270, 55), _open_review)
	_button(self, "confirm", "收好行囊，迎接明晨", Vector2(977, 800), Vector2(425, 55), _confirm, true)
	_label(self, "改選會重新計算並清除微調；所有選項都能繼續故事。", Vector2(40, 861), Vector2(1360, 30), 16, MUTED)

func _show_review() -> void:
	_background("wangxi")
	var info = Creation.summary(run.data.creation)
	_label(self, "回頭看看，不必重走全部的路", Vector2(38, 35), Vector2(1100, 65), 38, JADE, true)
	_label(self, "選一段重讀；重新作答後會回到能力總覽，原有微調會清除。", Vector2(40, 111), Vector2(1340, 50), 21, MUTED)
	_button(self, "save_exit", "記下這一頁", Vector2(1215, 45), Vector2(190, 47), _close)
	for index in range(6):
		var row: Dictionary = info.answer_rows[index]
		var card = _panel(self, Vector2(40, 190 + index * 93), Vector2(1360, 83))
		_label(card, str(row.question) + "　·　" + str(row.effect), Vector2(20, 8), Vector2(1080, 29), 20, JADE)
		_label(card, str(row.answer), Vector2(20, 41), Vector2(1080, 32), 20)
		_button(card, "review_%d" % index, "重讀這一段", Vector2(1115, 18), Vector2(220, 48), _review_question.bind(index))
	_button(self, "review_back", "回到能力總覽", Vector2(1040, 800), Vector2(360, 60), _summary, true)

func _answer(choice: int) -> void:
	var result: Dictionary = run.set_creation_answer(int(run.data.creation.question), choice)
	if not result.ok:
		_message = str(result.message)
		return
	_message = ""
	_persist()

func _continue() -> void:
	if run.data.creation.review_return or int(run.data.creation.question) == 5:
		_summary()
	else:
		run.data.creation.question = int(run.data.creation.question) + 1
		run.data.creation.page = "question"
		_persist()

func _return_to_question() -> void:
	run.data.creation.page = "question"
	_persist()

func _back() -> void:
	if run.data.creation.review_return:
		run.data.creation.page = "review"
	elif int(run.data.creation.question) > 0:
		run.data.creation.question = int(run.data.creation.question) - 1
		run.data.creation.page = "question"
	_persist()

func _summary() -> void:
	run.data.creation.page = "summary"
	run.data.creation.review_return = false
	run.data.creation.move_source = ""
	_persist()

func _open_review() -> void:
	run.data.creation.page = "review"
	run.data.creation.move_source = ""
	_persist()

func _review_question(index: int) -> void:
	run.data.creation.question = index
	run.data.creation.page = "question"
	run.data.creation.review_return = true
	_persist()

func _choose_source(attribute: String) -> void:
	run.data.creation.move_source = attribute
	_message = ""
	_persist()

func _cancel_move() -> void:
	run.data.creation.move_source = ""
	_message = ""
	_persist()

func _move_to(attribute: String) -> void:
	var result: Dictionary = run.move_creation_point(str(run.data.creation.get("move_source", "")), attribute)
	_message = str(result.message)
	if result.ok: _persist()
	else: _render()

func _reset() -> void:
	var result: Dictionary = run.reset_creation_adjustments()
	_message = str(result.message)
	if result.ok: _persist()
	else: _render()

func _confirm() -> void:
	if _confirming: return
	_confirming = true
	var result: Dictionary = run.confirm_creation()
	if not result.ok:
		_confirming = false
		_message = str(result.message)
		_render()
		return
	changed.emit()
	confirmed.emit()

func _close() -> void:
	changed.emit()
	closed.emit()

func _persist() -> void:
	changed.emit()
	_render()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or run == null: return
	if event.keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()
	elif run.data.creation.page == "question" and event.keycode >= KEY_1 and event.keycode <= KEY_3:
		_answer(int(event.keycode) - KEY_1)
		get_viewport().set_input_as_handled()
	elif run.data.creation.page == "aftermath" and event.keycode == KEY_ENTER:
		_continue()
		get_viewport().set_input_as_handled()

func _style(fill: Color, edge: Color = Color("d4c8a9")) -> StyleBoxFlat:
	var value = StyleBoxFlat.new()
	value.bg_color = fill
	value.border_color = edge
	value.set_border_width_all(1)
	value.set_corner_radius_all(14)
	return value

func _panel(parent: Node, position_value: Vector2, extent: Vector2, fill: Color = Color("fffbef")) -> Panel:
	var value = Panel.new()
	value.position = position_value
	value.size = extent
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value.add_theme_stylebox_override("panel", _style(fill))
	parent.add_child(value)
	return value

func _label(parent: Node, text: String, position_value: Vector2, extent: Vector2, font_size: int = 20, color: Color = INK, serif: bool = false) -> Label:
	var value = Label.new()
	# Apply typography before the extent: Label's unwrapped text minimum can
	# otherwise enlarge it before wrap is enabled and leave it wider than its card.
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.clip_text = true
	value.add_theme_font_override("font", SERIF if serif else FONT)
	value.add_theme_font_size_override("font_size", font_size)
	value.add_theme_color_override("font_color", color)
	value.text = text
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(value)
	value.position = position_value
	value.size = Vector2(extent.x, maxf(extent.y, float(value.get_line_height())))
	return value

func _button(parent: Node, id: String, text: String, position_value: Vector2, extent: Vector2, callback: Callable, primary: bool = false, font_size: int = 20) -> Button:
	var value = Button.new()
	value.text = text
	value.position = position_value
	value.size = extent
	value.add_theme_font_size_override("font_size", font_size)
	value.add_theme_color_override("font_color", PAPER if primary else INK)
	value.add_theme_color_override("font_hover_color", PAPER if primary else INK)
	value.add_theme_color_override("font_disabled_color", Color("8a8e80"))
	value.add_theme_stylebox_override("normal", _style(JADE if primary else Color("fffbef")))
	value.add_theme_stylebox_override("hover", _style(Color("447461") if primary else Color("e9efdc"), GOLD))
	value.add_theme_stylebox_override("pressed", _style(Color("24473f") if primary else Color("dae2cc")))
	value.add_theme_stylebox_override("disabled", _style(Color("e5e3d8")))
	value.pressed.connect(callback)
	parent.add_child(value)
	action_buttons[id] = value
	return value

func _scroll(parent: Node, position_value: Vector2, extent: Vector2) -> VBoxContainer:
	var container = ScrollContainer.new()
	container.position = position_value
	container.size = extent
	container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(container)
	var padding = MarginContainer.new()
	padding.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	padding.add_theme_constant_override("margin_right", 12)
	container.add_child(padding)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	padding.add_child(list)
	return list

func _flow_label(text: String, width: float, font_size: int, color: Color, minimum_height: float = 0.0) -> Label:
	var value = Label.new()
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.add_theme_font_size_override("font_size", font_size)
	value.add_theme_color_override("font_color", color)
	value.text = text
	value.custom_minimum_size = Vector2(width, minimum_height)
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return value
