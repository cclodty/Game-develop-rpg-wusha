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
	value.tooltip_text = str(card.get("name", "")) + "\n" + str(card.get("description", "")) + str(card.get("preview_tooltip", ""))
	var accent = Color("a55f4c") if card.get("type", "skill") == "attack" else JADE
	value.add_theme_stylebox_override("normal", style(Color("fcf7e9"), GOLD if selected else accent, 3 if selected else 1))
	var category = "攻擊" if card.get("type", "skill") == "attack" else "技法"
	label(value, category, Vector2(14, 10), Vector2(size.x - 65, 22), 14, accent)
	var cost = label(value, str(card.get("cost", 0)), Vector2(size.x - 43, 7), Vector2(32, 32), 23, JADE, true)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var portrait = TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture = Art.portrait(str(card.get("art_id", "courier")))
	portrait.position = Vector2(12, 32)
	portrait.size = Vector2(35, 46)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value.add_child(portrait)
	label(value, str(card.get("name", "招式")), Vector2(54, 34), Vector2(size.x - 67, 44), 18, INK, true)
	var description = label(value, str(card.get("face_description", compact_description(card))), Vector2(14, 82), Vector2(size.x - 28, size.y - 112), 15, INK)
	description.name = "Effect"
	var group = {"basic": "基本功", "zhaoling": "照嶺劍路", "duyun": "渡雲身法", "origin": "出身所長", "event": "江湖際遇"}
	label(value, "已選取" if selected else str(group.get(str(card.get("group", "basic")), "招式")), Vector2(14, size.y - 26), Vector2(size.x - 28, 20), 13, GOLD if selected else MUTED)
	return value

static func compact_description(card: Dictionary) -> String:
	var lines: Array[String] = []
	if card.has("damage"):
		lines.append("%s %d%s 傷害" % ["全體" if card.get("all", false) else "造成", int(card.damage), " × %d" % int(card.hits) if int(card.get("hits", 1)) > 1 else ""])
	if card.has("block"): lines.append("獲得 %d 防護" % int(card.block))
	if card.has("draw"): lines.append("抽 %d 張牌" % int(card.draw))
	if card.has("energy"): lines.append("回復 %d 真氣" % int(card.energy))
	if card.has("heal"): lines.append("回復 %d 氣血" % int(card.heal))
	if card.has("weak"): lines.append("虛弱 %d 回合" % int(card.weak))
	if card.has("vulnerable"): lines.append("破綻 %d 回合" % int(card.vulnerable))
	if card.has("next_attack"): lines.append("下一張攻擊 +%d" % int(card.next_attack))
	if card.has("guard_bonus"): lines.append("有防護時傷害 +%d" % int(card.guard_bonus))
	if card.has("skill_refund"): lines.append("技法後施展：回氣 %d" % int(card.skill_refund))
	if card.get("block_damage", false): lines.append("全部防護轉為傷害")
	if card.get("exhaust", false): lines.append("本場除外")
	return "\n".join(lines)
