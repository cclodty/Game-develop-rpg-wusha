class_name WeiyuanCardUI
extends RefCounted
## Shared readable card faces; presentation never changes combat values.

const FONT = preload("res://assets/fonts/JianghuSans.otf")
const SERIF = preload("res://assets/fonts/JianghuSerif.otf")
const Art = preload("res://scripts/art.gd")
const PAPER = Color("f8f1df")
const INK = Color("293f39")
const JADE = Color("376c5c")
const GOLD = Color("bc9457")
const MUTED = Color("65746a")

class CardButton extends Button:
	func _make_custom_tooltip(for_text: String) -> Object:
		var panel = PanelContainer.new()
		panel.add_theme_stylebox_override("panel", WeiyuanCardUI.style(WeiyuanCardUI.PAPER, WeiyuanCardUI.GOLD, 2))
		var margin = MarginContainer.new()
		for side in ["left", "top", "right", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 12)
		panel.add_child(margin)
		var detail = Label.new()
		detail.add_theme_font_override("font", WeiyuanCardUI.FONT)
		detail.add_theme_font_size_override("font_size", 17)
		detail.add_theme_color_override("font_color", WeiyuanCardUI.INK)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.custom_minimum_size = Vector2(350, 0)
		detail.text = for_text
		margin.add_child(detail)
		return panel

static func style(fill: Color = PAPER, edge: Color = Color("c7c9af"), thickness: int = 1) -> StyleBoxFlat:
	var value = StyleBoxFlat.new()
	value.bg_color = fill
	value.border_color = edge
	value.set_border_width_all(thickness)
	value.set_corner_radius_all(12)
	value.content_margin_left = 10
	value.content_margin_right = 10
	return value

static func label(parent: Node, text: String, position: Vector2, size: Vector2, font_size: int = 17, color: Color = INK, serif: bool = false) -> Label:
	var value = Label.new()
	value.position = position
	value.add_theme_font_override("font", SERIF if serif else FONT)
	value.add_theme_font_size_override("font_size", font_size)
	value.add_theme_color_override("font_color", color)
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value.size = size
	value.text = text
	parent.add_child(value)
	value.size = size
	return value

static func button(parent: Node, text: String, position: Vector2, size: Vector2, callback: Callable, primary: bool = false, card_face: bool = false) -> Button:
	var value = CardButton.new() if card_face else Button.new()
	value.text = text
	value.position = position
	value.size = size
	value.add_theme_font_override("font", FONT)
	value.add_theme_font_size_override("font_size", 17)
	value.add_theme_color_override("font_color", PAPER if primary else INK)
	value.add_theme_color_override("font_hover_color", INK)
	value.add_theme_color_override("font_pressed_color", INK)
	value.add_theme_color_override("font_disabled_color", Color("8a9080"))
	value.add_theme_stylebox_override("normal", style(JADE if primary else PAPER))
	value.add_theme_stylebox_override("hover", style(Color("e3ecd5"), GOLD, 2))
	value.add_theme_stylebox_override("pressed", style(Color("d3e3c6"), JADE, 2))
	value.add_theme_stylebox_override("disabled", style(Color("e5e4d6"), Color("c8cbb7")))
	value.add_theme_stylebox_override("focus", style(Color(0, 0, 0, 0), GOLD, 2))
	value.pressed.connect(callback)
	parent.add_child(value)
	return value

static func card_button(parent: Node, card: Dictionary, position: Vector2, size: Vector2, callback: Callable, selected: bool = false) -> Button:
	var value = button(parent, "", position, size, callback, false, true)
	value.clip_contents = true
	var details = str(card.get("name", "")) + "\n普通：" + str(card.get("normal_description", card.get("description", "")))
	if int(card.get("boost_cost", 0)) > 0:
		details += "\n運勁 %d 勢：%s" % [int(card.boost_cost), str(card.get("boost_description", ""))]
	value.tooltip_text = details + str(card.get("preview_tooltip", ""))
	var accents = {"attack": Color("a55f4c"), "guard": JADE, "change": Color("57788a")}
	var accent: Color = accents.get(str(card.get("type", "change")), JADE)
	value.add_theme_stylebox_override("normal", style(Color("fcf7e9"), GOLD if selected else accent, 3 if selected else 1))
	var category = {"attack": "攻", "guard": "守", "change": "變"}.get(str(card.get("type", "change")), "變")
	var discipline = {"basic": "通用", "sword": "劍術", "palm": "拳掌", "dart": "暗器", "footwork": "身法"}.get(str(card.get("discipline", "basic")), "通用")
	label(value, "%s · %s" % [category, discipline], Vector2(12, 8), Vector2(size.x - 57, 23), 13, accent)
	var cost = label(value, str(card.get("cost", 0)), Vector2(size.x - 39, 6), Vector2(29, 32), 23, JADE, true)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var portrait = TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture = Art.portrait(str(card.get("art_id", "courier")))
	portrait.position = Vector2(10, 32)
	portrait.size = Vector2(34, 40)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value.add_child(portrait)
	var card_name = str(card.get("name", "招式")).replace("（穩定）", "·穩").replace("（專精）", "·專")
	label(value, card_name, Vector2(49, 32), Vector2(size.x - 60, 43), 17, INK, true)
	var description = label(value, str(card.get("face_description", compact_description(card))), Vector2(12, 78), Vector2(size.x - 24, size.y - 107), 14, INK)
	description.name = "Effect"
	var caption = str(card.get("selection_label", ""))
	if caption.is_empty(): caption = "留至下回合" if card.get("retained", false) else ("已選取" if selected else "需劍" if card.get("weapon", "any") == "sword" else "通用武學")
	label(value, caption, Vector2(12, size.y - 24), Vector2(size.x - 24, 22), 12, GOLD if selected else JADE if card.get("retained", false) else MUTED)
	return value

static func compact_description(card: Dictionary) -> String:
	var lines: Array[String] = []
	if int(card.get("strip_block", 0)) > 0: lines.append("先移除 %d 防護" % int(card.strip_block))
	if int(card.get("damage", 0)) > 0: lines.append("造成 %d 傷害" % int(card.damage))
	if int(card.get("guard_bonus", 0)) > 0: lines.append("有防護再 +%d 傷害" % int(card.guard_bonus))
	if int(card.get("block", 0)) > 0: lines.append("獲得 %d 防護" % int(card.block))
	if int(card.get("draw", 0)) > 0: lines.append("抽 %d 張牌" % int(card.draw))
	if int(card.get("energy", 0)) > 0: lines.append("回復 %d 真氣" % int(card.energy))
	if int(card.get("cycle_limit", 0)) > 0: lines.append("可棄 %d 張，抽等量" % int(card.cycle_limit))
	if int(card.get("delayed_damage", 0)) > 0: lines.append("下回合造成 %d 傷害" % int(card.delayed_damage))
	if int(card.get("momentum_gain", 0)) > 0: lines.append("獲得 %d 勢" % int(card.momentum_gain))
	if int(card.get("retaliation", 0)) > 0: lines.append("準備反擊 %d 傷害" % int(card.retaliation))
	if card.get("exhaust", false): lines.append("本場除外")
	if int(card.get("boost_cost", 0)) > 0 and not card.get("empowered", false):
		lines.append("可運勁 · %d 勢" % int(card.boost_cost))
	return "\n".join(lines)
