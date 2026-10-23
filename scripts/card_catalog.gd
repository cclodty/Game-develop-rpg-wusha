class_name WeiyuanCards
extends RefCounted
## The complete first-chapter pool. Upgrades change values, never deck identity.

const BASIC_CARDS = ["strike", "guard", "breath", "observe", "feint"]
const ORIGIN_CARDS = {"herbalist": "herb_poultice", "courier": "courier_dash", "performer": "stage_flourish"}
const ACTIVITY_CARDS = {
	"sword_lesson": ["sword_qi", "steady_guard"], "spar": ["opening_thrust"],
	"ridge_tracks": ["cloud_step"], "hermit_visit": ["flowing_cut", "returning_swallow"],
	"medicine_lesson": ["herb_poultice"], "courier_work": ["courier_dash"], "stage_work": ["stage_flourish"],
	"bridge_repair": ["bridge_oath"], "missing_letter": ["letter_focus"],
	"old_ballad": ["old_ballad"], "grove_survey": ["mountain_echo"],
}
const CARDS = {
	"strike": {"name": "出劍", "type": "attack", "group": "basic", "cost": 1, "damage": 6, "upgrade": {"damage": 9}, "source_label": "起始招式"},
	"guard": {"name": "架勢", "type": "skill", "group": "basic", "cost": 1, "block": 5, "upgrade": {"block": 8}, "source_label": "起始招式"},
	"breath": {"name": "調息", "type": "skill", "group": "basic", "cost": 0, "energy": 1, "exhaust": true, "upgrade": {"energy": 2}, "source_label": "起始招式"},
	"observe": {"name": "審勢", "type": "skill", "group": "basic", "cost": 1, "draw": 2, "upgrade": {"draw": 3}, "source_label": "起始招式"},
	"feint": {"name": "虛招", "type": "attack", "group": "basic", "cost": 1, "damage": 4, "weak": 1, "upgrade": {"damage": 6, "weak": 2}, "source_label": "起始招式"},
	"sword_qi": {"name": "破雲劍氣", "type": "attack", "group": "zhaoling", "cost": 2, "damage": 8, "all": true, "upgrade": {"damage": 11}, "source_label": "聽劍入門"},
	"steady_guard": {"name": "守嶺式", "type": "skill", "group": "zhaoling", "cost": 1, "block": 8, "next_attack": 3, "upgrade": {"block": 11, "next_attack": 4}, "source_label": "聽劍入門"},
	"opening_thrust": {"name": "照隙一劍", "type": "attack", "group": "zhaoling", "cost": 1, "damage": 7, "guard_bonus": 4, "upgrade": {"damage": 10, "guard_bonus": 5}, "source_label": "同門對練"},
	"cloud_step": {"name": "掠影突進", "type": "skill", "group": "duyun", "cost": 1, "block": 5, "draw": 1, "upgrade": {"block": 8}, "source_label": "望風尋跡"},
	"flowing_cut": {"name": "流雲切", "type": "attack", "group": "duyun", "cost": 1, "damage": 5, "skill_refund": 1, "upgrade": {"damage": 8}, "source_label": "風亭問路"},
	"returning_swallow": {"name": "雙燕回鋒", "type": "attack", "group": "duyun", "cost": 1, "damage": 3, "hits": 2, "upgrade": {"damage": 5}, "source_label": "風亭問路"},
	"herb_poultice": {"name": "隨身藥敷", "type": "skill", "group": "origin", "cost": 1, "heal": 5, "block": 3, "exhaust": true, "upgrade": {"heal": 8, "block": 5}, "source_label": "藥鋪出身／藥鋪學方"},
	"courier_dash": {"name": "熟路快步", "type": "skill", "group": "origin", "cost": 0, "block": 3, "draw": 1, "exhaust": true, "upgrade": {"block": 6}, "source_label": "驛站出身／街巷送信"},
	"stage_flourish": {"name": "亮相誘招", "type": "skill", "group": "origin", "cost": 1, "vulnerable": 2, "draw": 1, "upgrade": {"vulnerable": 3, "draw": 2}, "source_label": "戲班出身／街頭小戲"},
	"bridge_oath": {"name": "護橋之約", "type": "skill", "group": "event", "cost": 1, "block": 7, "draw": 1, "upgrade": {"block": 10}, "source_label": "小橋補板"},
	"letter_focus": {"name": "一諾凝神", "type": "skill", "group": "event", "cost": 0, "next_attack": 4, "exhaust": true, "upgrade": {"next_attack": 7}, "source_label": "未送達的信"},
	"old_ballad": {"name": "舊曲回氣", "type": "skill", "group": "event", "cost": 1, "draw": 2, "energy": 1, "exhaust": true, "upgrade": {"draw": 3}, "source_label": "半支舊曲"},
	"mountain_echo": {"name": "山溪回響", "type": "attack", "group": "event", "cost": 2, "damage": 12, "block_damage": true, "upgrade": {"damage": 16}, "source_label": "青篁訪路"},
}

static func has(id: String) -> bool:
	return CARDS.has(id)

static func starting_deck() -> Array:
	var result: Array = []
	for id in BASIC_CARDS:
		result.append(id)
		result.append(id)
	return result

static func starting_learned(origin: String) -> Array:
	var result := BASIC_CARDS.duplicate()
	if ORIGIN_CARDS.has(origin): result.append(ORIGIN_CARDS[origin])
	return result

static func cards_for_activity(id: String) -> Array:
	return ACTIVITY_CARDS.get(id, []).duplicate()

static func validate_deck(deck: Variant, learned: Variant) -> Dictionary:
	if not deck is Array or not learned is Array or deck.size() != 10:
		return {"ok": false, "message": "牌組必須恰好十張。"}
	var counts: Dictionary = {}
	for id in deck:
		if not id is String or not has(id) or id not in learned:
			return {"ok": false, "message": "牌組含有未學會或不存在的招式。"}
		counts[id] = int(counts.get(id, 0)) + 1
		if counts[id] > 2:
			return {"ok": false, "message": "每種招式最多放入兩張。"}
	return {"ok": true, "message": "牌組可用。"}

static func card(id: String, upgraded: bool = false) -> Dictionary:
	if not has(id): return {}
	var result: Dictionary = CARDS[id].duplicate(true)
	if upgraded:
		for key in result.upgrade: result[key] = result.upgrade[key]
	result.erase("upgrade")
	result.id = id
	result.upgraded = upgraded
	result.target = "all_enemies" if result.get("all", false) else ("enemy" if result.has("damage") or result.has("weak") or result.has("vulnerable") else "self")
	if upgraded: result.name += "（精修）"
	result.description = _description(result)
	return result

static func _description(c: Dictionary) -> String:
	var parts: Array[String] = []
	if c.has("damage"):
		parts.append("對%s造成 %d%s 傷害" % ["所有敵人" if c.get("all", false) else "一名敵人", c.damage, " × %d" % c.hits if c.get("hits", 1) > 1 else ""])
	if c.has("block"): parts.append("獲得 %d 防護" % c.block)
	if c.has("draw"): parts.append("抽 %d 張牌" % c.draw)
	if c.has("energy"): parts.append("回復 %d 真氣" % c.energy)
	if c.has("heal"): parts.append("回復 %d 氣血" % c.heal)
	if c.has("weak"): parts.append("使目標虛弱 %d 回合（攻擊傷害減少四分之一）" % c.weak)
	if c.has("vulnerable"): parts.append("使目標破綻 %d 回合（受到傷害增加一半）" % c.vulnerable)
	if c.has("next_attack"): parts.append("本回合下一張攻擊牌額外 %d 傷害（整張一次）" % c.next_attack)
	if c.has("guard_bonus"): parts.append("有防護時額外 %d 傷害" % c.guard_bonus)
	if c.has("skill_refund"): parts.append("本回合已出過技法牌時回復 %d 真氣" % c.skill_refund)
	if c.get("block_damage", false): parts.append("消耗所有防護，轉成等量額外傷害")
	if c.get("exhaust", false): parts.append("本場除外")
	return "；".join(parts) + "。"
