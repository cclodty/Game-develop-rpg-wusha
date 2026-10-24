class_name WeiyuanCards
extends RefCounted
## Martial-core catalogue: one source for effects, preparation and card text.

const TYPE_LABELS = {"attack": "攻", "guard": "守", "change": "變"}
const WEAPONS = {
	"sword": {"name": "劍", "description": "可配劍術及所有通用武學。"},
	"saber": {"name": "刀", "description": "刀法列入擴充藍圖；本輪可配通用武學。"},
	"polearm": {"name": "長兵", "description": "長兵招式列入擴充藍圖；本輪可配通用武學。"},
	"unarmed": {"name": "徒手", "description": "以拳掌、暗器、身法與通用技法配招。"},
}
const DISCIPLINES = {
	"basic": {"name": "基礎", "description": "調息、審勢與基本攻守。"},
	"sword": {"name": "劍術", "description": "精準單點、掌握破綻與集中終結。"},
	"saber": {"name": "刀法", "description": "重擊、破防、橫掃與追擊；正式牌池待擴充。"},
	"palm": {"name": "拳掌", "description": "卸力、反擊與防守轉攻。"},
	"claw": {"name": "指爪", "description": "干擾附加招式、製造破綻；正式牌池待擴充。"},
	"polearm": {"name": "長兵", "description": "牽制多敵、掃擊與攔截蓄勢；正式牌池待擴充。"},
	"dart": {"name": "暗器", "description": "佈置、延遲發作與補刀。"},
	"footwork": {"name": "身法", "description": "調整手牌、節奏與短暫防護。"},
	"medicine": {"name": "醫毒", "description": "有限續航、持續傷害與解狀態；正式牌池待擴充。"},
}
const INNERS = {
	"shouzhong": {
		"name": "守中訣", "source_label": "聽劍入門",
		"description": "敵方回合首次以防護實際吸收傷害，獲得 1 勢。每實際消耗 1 勢，在該牌效果結算後獲得 2 防護。",
		"gain_description": "敵方回合首次以防護吸收傷害，獲得 1 勢。",
		"spend_description": "每耗 1 勢，招式結算後獲得 2 防護。",
		"tradeoff": "對手不進攻時，需要主動尋找蓄勢機會。",
	},
	"xingyun": {
		"name": "行雲訣", "source_label": "望風尋跡",
		"description": "本回合首次連續打出不同招路的付費牌，獲得 1 勢；零費牌不更新判斷。每回合首次耗勢出牌，效果結算後額外抽 1 張。",
		"gain_description": "首次相鄰兩張付費牌招路不同，獲得 1 勢；零費牌不更新判斷。",
		"spend_description": "每回合首次耗勢出牌，額外抽 1 張。",
		"tradeoff": "需要混合招路，並為新抽到的牌保留真氣。",
	},
	"guiyuan": {
		"name": "歸元功", "source_label": "旅前基礎修習",
		"description": "回合末若有真氣，消耗 1 真氣取得 1 勢，每回合一次。單張攻牌實際消耗 3 勢時，整張額外造成 8 傷害，只計一次。",
		"gain_description": "回合末有餘氣時，消耗 1 真氣獲得 1 勢。",
		"spend_description": "單張攻牌實付 3 勢時，整張額外造成 8 傷害。",
		"tradeoff": "需要犧牲眼前行動，準備集中爆發。",
	},
}
const BASIC_CARDS = ["strike", "guard", "breath", "observe", "probing_stone"]
# Origins retain supplies and story conveniences; none owns an exclusive card.
const ORIGIN_CARDS = {}
const REFINABLE = ["opening_thrust", "cloud_step", "sword_qi"]
const REFINEMENT_LABELS = {"stable": "穩定", "specialist": "專精"}
const ACTIVITY_CARDS = {
	"sword_lesson": ["sword_qi", "opening_thrust"],
	"practice": ["pushing_palm"],
	"spar": ["yielding_palm"],
	"ridge_tracks": ["cloud_step"],
	"hermit_visit": ["hidden_needle"],
}
const ACTIVITY_INNERS = {"sword_lesson": ["shouzhong"], "ridge_tracks": ["xingyun"]}
const PRESETS = {
	"shouzhong": {
		"name": "守中反擊", "weapon": "sword", "inner": "shouzhong",
		"description": "先以防護取得勢，再選擇卸力反擊或照隙出劍；面對守勢敵人時，需用推碑掌主動拆防。",
		"deck": ["strike", "strike", "guard", "guard", "opening_thrust", "opening_thrust", "yielding_palm", "yielding_palm", "pushing_palm", "gather_momentum"],
	},
	"xingyun": {
		"name": "行雲變招", "weapon": "unarmed", "inner": "xingyun",
		"description": "交替攻、守、變取得勢，以飛石問路接續手牌；掠影步整理牌序，伏針避開眼前反制。",
		"deck": ["guard", "breath", "observe", "cloud_step", "cloud_step", "pushing_palm", "pushing_palm", "probing_stone", "probing_stone", "hidden_needle"],
	},
	"guiyuan": {
		"name": "歸元爆發", "weapon": "sword", "inner": "guiyuan",
		"description": "以收勢和回合末餘氣蓄積三勢，保留破雲劍氣等待爆發；也要衡量眼前防守的需要。",
		"deck": ["strike", "strike", "guard", "guard", "breath", "observe", "sword_qi", "sword_qi", "gather_momentum", "gather_momentum"],
	},
}
const CARDS = {
	"strike": {"name": "出劍", "type": "attack", "group": "basic", "discipline": "sword", "weapon": "sword", "cost": 1, "damage": 6, "source_label": "旅前基礎修習"},
	"guard": {"name": "架勢", "type": "guard", "group": "basic", "discipline": "basic", "weapon": "any", "cost": 1, "block": 5, "source_label": "旅前基礎修習"},
	"breath": {"name": "調息", "type": "change", "group": "basic", "discipline": "basic", "weapon": "any", "cost": 0, "energy": 1, "exhaust": true, "source_label": "旅前基礎修習"},
	"observe": {"name": "審勢", "type": "change", "group": "basic", "discipline": "basic", "weapon": "any", "cost": 1, "draw": 2, "source_label": "旅前基礎修習"},
	"cloud_step": {"name": "掠影步", "type": "change", "group": "duyun", "discipline": "footwork", "weapon": "any", "cost": 1, "block": 3, "cycle_limit": 1, "source_label": "望風尋跡"},
	"opening_thrust": {"name": "照隙一劍", "type": "attack", "group": "zhaoling", "discipline": "sword", "weapon": "sword", "cost": 1, "damage": 4, "guard_bonus": 4, "boost": {"cost": 1, "damage_bonus": 4}, "source_label": "聽劍入門"},
	"sword_qi": {"name": "破雲劍氣", "type": "attack", "group": "zhaoling", "discipline": "sword", "weapon": "sword", "cost": 2, "damage": 10, "boost": {"cost": 3, "damage_bonus": 12}, "source_label": "聽劍入門"},
	"pushing_palm": {"name": "推碑掌", "type": "attack", "group": "palm", "discipline": "palm", "weapon": "any", "cost": 1, "strip_block": 6, "damage": 4, "source_label": "劍坪練習"},
	"yielding_palm": {"name": "卸力掌", "type": "guard", "group": "palm", "discipline": "palm", "weapon": "any", "cost": 1, "block": 4, "boost": {"cost": 1, "retaliation": 6}, "source_label": "同門對練"},
	"probing_stone": {"name": "飛石問路", "type": "change", "group": "basic", "discipline": "dart", "weapon": "any", "cost": 0, "strip_block": 2, "boost": {"cost": 1, "draw": 1}, "source_label": "旅前基礎修習"},
	"hidden_needle": {"name": "伏針", "type": "change", "group": "duyun", "discipline": "dart", "weapon": "any", "cost": 1, "delayed_damage": 7, "boost": {"cost": 1, "delayed_damage": 11}, "source_label": "風亭問路"},
	"gather_momentum": {"name": "收勢", "type": "change", "group": "basic", "discipline": "basic", "weapon": "any", "cost": 1, "momentum_gain": 1, "source_label": "旅前基礎修習"},
}
const REFINEMENTS = {
	"opening_thrust": {
		"stable": {"description": "基礎傷害改為 6，有防護時的追加傷害改為 2；運勁仍耗 1 勢追加 4 傷害。", "effects": {"damage": 6, "guard_bonus": 2}},
		"specialist": {"description": "普通效果不變；運勁改耗 2 勢，追加 9 傷害。", "boost": {"cost": 2, "damage_bonus": 9}},
	},
	"cloud_step": {
		"stable": {"description": "防護提高至 5；仍可棄另一張手牌，再抽一張。", "effects": {"block": 5}},
		"specialist": {"description": "防護維持 3；可棄最多兩張其他手牌，再抽相同數量。", "effects": {"cycle_limit": 2}},
	},
	"sword_qi": {
		"stable": {"description": "真氣費用降至 1，基礎傷害改為 7；運勁仍耗 3 勢追加 12 傷害。", "effects": {"cost": 1, "damage": 7}},
		"specialist": {"description": "普通效果不變；運勁時先移除目標最多 8 防護，再造成傷害。", "boost": {"cost": 3, "damage_bonus": 12, "strip_block": 8}},
	},
}


static func has(id: String) -> bool:
	return CARDS.has(id)


static func starting_deck() -> Array:
	var result: Array = []
	for id in BASIC_CARDS:
		result.append(id)
		result.append(id)
	return result


static func starting_learned(_origin: String = "herbalist") -> Array:
	var result: Array = BASIC_CARDS.duplicate()
	result.append("gather_momentum")
	return result


static func cards_for_activity(id: String) -> Array:
	return ACTIVITY_CARDS.get(id, []).duplicate()


static func inners_for_activity(id: String) -> Array:
	return ACTIVITY_INNERS.get(id, []).duplicate()


static func validate_deck(deck: Variant, learned: Variant, weapon: String = "sword") -> Dictionary:
	if not WEAPONS.has(weapon):
		return {"ok": false, "message": "請選擇劍、刀、長兵或徒手。"}
	if not deck is Array or not learned is Array or deck.size() != 10:
		return {"ok": false, "message": "牌組必須恰好十張。"}
	var counts: Dictionary = {}
	for id in deck:
		if not id is String or not has(id) or id not in learned:
			return {"ok": false, "message": "牌組含有未學會或不存在的招式。"}
		var need: String = str(CARDS[id].weapon)
		if need != "any" and need != weapon:
			return {"ok": false, "message": "「%s」需要主兵器：%s。" % [CARDS[id].name, WEAPONS[need].name]}
		counts[id] = int(counts.get(id, 0)) + 1
		if counts[id] > 2:
			return {"ok": false, "message": "每種招式最多放入兩張。"}
	return {"ok": true, "message": "十張招式與主兵器相符，可出發。"}


static func refinement_description(id: String, branch: String) -> String:
	return str(REFINEMENTS.get(id, {}).get(branch, {}).get("description", ""))


static func card(id: String, refinement: Variant = "", empowered: bool = false) -> Dictionary:
	if not has(id): return {}
	var branch: String = ""
	if refinement is bool:
		branch = "stable" if refinement and id in REFINABLE else ""
	elif refinement is String:
		branch = refinement
	else:
		return {}
	if not branch.is_empty() and (id not in REFINABLE or branch not in REFINEMENT_LABELS):
		return {}
	var normal: Dictionary = CARDS[id].duplicate(true)
	if not branch.is_empty():
		var changes: Dictionary = REFINEMENTS[id][branch]
		for key in changes.get("effects", {}): normal[key] = changes.effects[key]
		if changes.has("boost"): normal.boost = changes.boost.duplicate(true)
	var boost: Dictionary = normal.get("boost", {})
	if empowered and boost.is_empty(): return {}
	var strengthened: Dictionary = _apply_boost(normal, boost)
	var result: Dictionary = strengthened if empowered else normal
	result.id = id
	result.refinement = branch
	result.refinement_label = REFINEMENT_LABELS.get(branch, "未精修")
	result.upgraded = not branch.is_empty()
	result.empowered = empowered
	result.boost_available = not boost.is_empty()
	result.boost_cost = int(boost.get("cost", 0))
	result.momentum_cost = result.boost_cost if empowered else 0
	result.target = "enemy" if result.has("damage") or result.has("strip_block") or result.has("delayed_damage") else "self"
	result.normal_description = _description(normal)
	result.boost_description = ("消耗 %d 勢；" % result.boost_cost) + _description(strengthened) if not boost.is_empty() else "這項招式沒有運勁版本。"
	result.description = result.boost_description if empowered else result.normal_description
	if not branch.is_empty(): result.name += "（%s）" % REFINEMENT_LABELS[branch]
	return result


static func _apply_boost(normal: Dictionary, boost: Dictionary) -> Dictionary:
	var result: Dictionary = normal.duplicate(true)
	for key in boost:
		if key == "cost": continue
		if key == "damage_bonus": result.damage = int(result.get("damage", 0)) + int(boost[key])
		elif key == "draw": result.draw = int(result.get("draw", 0)) + int(boost[key])
		else: result[key] = boost[key]
	return result


static func _description(c: Dictionary) -> String:
	var parts: Array[String] = []
	# Text follows actual resolution order: strip, direct damage, guard and support.
	if c.has("strip_block"): parts.append("先移除目標最多 %d 防護" % int(c.strip_block))
	if c.has("damage"): parts.append("對一名敵人造成 %d 傷害" % int(c.damage))
	if c.has("guard_bonus"): parts.append("出招時已有防護，額外造成 %d 傷害" % int(c.guard_bonus))
	if c.has("block"): parts.append("獲得 %d 防護" % int(c.block))
	if c.has("cycle_limit"):
		parts.append("可棄最多 %d 張其他手牌，再抽相同數量" % int(c.cycle_limit))
	if c.has("draw"): parts.append("抽 %d 張牌" % int(c.draw))
	if c.has("energy"): parts.append("回復 %d 真氣" % int(c.energy))
	if c.has("momentum_gain"): parts.append("獲得 %d 勢（仍受當輪上限限制）" % int(c.momentum_gain))
	if c.has("delayed_damage"): parts.append("下個玩家回合開始時，對目標造成 %d 傷害；目標已死則取消" % int(c.delayed_damage))
	if c.has("retaliation"): parts.append("準備一次 %d 傷害反擊（實際吸傷且存活時觸發，不累加）" % int(c.retaliation))
	if c.get("exhaust", false): parts.append("本場除外")
	return "；".join(parts) + "。"
