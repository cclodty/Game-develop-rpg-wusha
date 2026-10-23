class_name WeiyuanRun
extends RefCounted
## Transactional run rules. UI, walking, dialogue and fighting do not advance time.

const Content = preload("res://scripts/game_data.gd")
const SAVE_PATH = "user://run-v1.json"
const SAVE_VERSION = 1
const MAX_SAVE_BYTES = 2097152
const PHASES = ["intro", "town", "activity", "exam", "results", "ending"]
const PERIODS = ["早", "午", "晚"]
var data: Dictionary = {}

func new_run(hero_name: String, origin: String) -> void:
	if not Content.ORIGINS.has(origin):
		origin = "herbalist"
	var clean_name: String = hero_name.strip_edges().replace("\n", "").replace("\r", "").replace("\t", "").substr(0, 16)
	if clean_name.is_empty():
		clean_name = "行路人"
	var origin_data: Dictionary = Content.ORIGINS[origin]
	var favor: Dictionary = {}
	for npc in Content.NPCS:
		favor[npc] = 0
	data = {
		"hero_name": clean_name, "origin": origin, "spent": 0,
		"money": int(origin_data.money), "medicine": int(origin_data.medicine),
		"training": 0, "insight": int(origin_data.insight), "favor": favor,
		"skills": [], "completed": [], "journal": [], "pending": {},
		"phase": "intro", "exam_result": {}, "school": "", "serial": 0,
		"world_position": [540.0, 520.0], "dialogue": {},
	}
	_journal("以%s的身分抵達望溪鎮。七日之後，便是入門選拔。" % str(origin_data.name))

func day() -> int:
	return mini(8, int(data.get("spent", 0)) / 3 + 1)

func period() -> String:
	if remaining() <= 0:
		return "選拔日"
	return PERIODS[int(data.get("spent", 0)) % 3]

func remaining() -> int:
	return maxi(0, Content.MAX_SLOTS - int(data.get("spent", 0)))

func ready_for_exam() -> bool:
	return not data.is_empty() and remaining() == 0 and data.get("pending", {}).is_empty() and str(data.get("phase", "")) in ["intro", "town"]

func has_skill(id: String) -> bool:
	return id in data.get("skills", [])

func activity_status(id: String) -> Dictionary:
	if data.is_empty():
		return _fail("請先建立旅程。")
	if not Content.ACTIVITIES.has(id):
		return _fail("找不到這項活動。")
	var activity: Dictionary = Content.ACTIVITIES[id]
	if not data.pending.is_empty():
		return _fail("先完成或退出目前的活動。")
	if str(data.phase) not in ["intro", "town"]:
		return _fail("這個階段已不能安排日常活動。")
	if remaining() < int(activity.cost):
		return _fail("剩餘 %d 個時段，不足以安排這項活動的 %d 個時段。" % [remaining(), int(activity.cost)])
	if not bool(activity.repeatable) and id in data.completed:
		return _fail("這件事已經完成，成果已記在紀事裡。")
	var fee: int = int(activity.get("fee", 0))
	if int(data.money) < fee:
		return _fail("需要 %d 文，目前有 %d 文。" % [fee, int(data.money)])
	var needs: Dictionary = activity.get("requires", {})
	for key in ["training", "insight"]:
		if int(data[key]) < int(needs.get(key, 0)):
			var label: String = "武學" if key == "training" else "見識"
			return _fail("需要%s %d，目前為 %d。" % [label, int(needs[key]), int(data[key])])
	var required_event: String = str(needs.get("completed", ""))
	if not required_event.is_empty() and required_event not in data.completed:
		return _fail("先完成「%s」，對方才願意交付這件事。" % str(Content.ACTIVITIES[required_event].name))
	if activity.has("insight_cap") and int(data.insight) >= int(activity.insight_cap):
		return _fail("書攤能教的已經讀過了。更多見識要到江湖上尋找。")
	return {"ok": true, "message": "消耗 %d 個時段%s" % [int(activity.cost), "、%d 文" % fee if fee > 0 else ""], "cost": int(activity.cost), "fee": fee}

func begin_activity(id: String) -> Dictionary:
	var available: Dictionary = activity_status(id)
	if not bool(available.ok):
		return available
	var activity: Dictionary = Content.ACTIVITIES[id]
	var before: int = int(data.spent)
	data.serial = int(data.serial) + 1
	data.pending = {
		"id": id, "token": int(data.serial), "cost": int(activity.cost), "fee": int(activity.get("fee", 0)),
		"start_spent": before, "attempt": 0, "medicine_at_start": int(data.medicine),
		"stage": "", "visited": [], "combat": {},
	}
	data.spent = before + int(activity.cost)
	data.money = int(data.money) - int(activity.get("fee", 0))
	data.phase = "activity"
	data.dialogue = {}
	_journal("安排「%s」，投入 %d 個時段%s。" % [str(activity.name), int(activity.cost), "與 %d 文" % int(activity.get("fee", 0)) if int(activity.get("fee", 0)) > 0 else ""], before)
	return {"ok": true, "message": "活動已安排；本次行程不再額外扣時。", "activity": activity.duplicate(true), "pending_token": int(data.pending.token)}

func complete_activity(outcome: String = "success", detail: Dictionary = {}) -> Dictionary:
	if outcome in ["retreat", "failure"]:
		return retreat_activity(detail)
	if outcome != "success":
		return _fail("未知的活動結果，沒有變更旅程。")
	var check: Dictionary = _check_pending(detail, false)
	if not bool(check.ok):
		return check
	var id: String = str(data.pending.id)
	var activity: Dictionary = Content.ACTIVITIES[id]
	var rewards: Dictionary = activity.get("rewards", {}).duplicate(true)
	if id == "courier_work" and str(data.origin) == "courier":
		rewards.money = int(rewards.get("money", 0)) + 8
	if id == "stage_work" and str(data.origin) == "performer":
		rewards.money = int(rewards.get("money", 0)) + 8
	if id in ["herb_errand", "medicine_lesson"] and str(data.origin) == "herbalist":
		rewards.medicine = int(rewards.get("medicine", 0)) + 1
	_commit_medicine(detail)
	for key in ["money", "medicine", "training", "insight"]:
		var cap: int = 99999 if key == "money" else (99 if key == "medicine" else 60)
		data[key] = mini(cap, int(data[key]) + int(rewards.get(key, 0)))
	for skill in rewards.get("skills", []):
		if skill not in data.skills:
			data.skills.append(skill)
	var favor_rewards: Dictionary = rewards.get("favor", {})
	for npc in favor_rewards:
		var cap: int = int(activity.get("favor_cap", 9))
		var current: int = int(data.favor[npc])
		if current < cap:
			data.favor[npc] = mini(cap, current + int(favor_rewards[npc]))
	if id not in data.completed:
		data.completed.append(id)
	data.pending = {}
	data.phase = "town"
	data.dialogue = {}
	var message: String = "完成「%s」。%s" % [str(activity.name), _rewards_text(rewards)]
	_journal(message)
	return {"ok": true, "message": message, "rewards": rewards, "activity_id": id, "exam_ready": ready_for_exam()}

func retreat_activity(detail: Dictionary = {}) -> Dictionary:
	if not data.is_empty() and str(data.get("pending", {}).get("id", "")) == "exam":
		return complete_exam(false, detail)
	var check: Dictionary = _check_pending(detail, false)
	if not bool(check.ok):
		return check
	var id: String = str(data.pending.id)
	_commit_medicine(detail)
	data.pending = {}
	data.phase = "town"
	data.dialogue = {}
	var message: String = "暫別「%s」。已投入的時段保留，本次未取得完成獎勵。" % str(Content.ACTIVITIES[id].name)
	_journal(message)
	return {"ok": true, "message": message, "activity_id": id, "exam_ready": ready_for_exam()}

func retry_activity() -> Dictionary:
	if data.is_empty() or data.get("pending", {}).is_empty() or str(data.phase) not in ["activity", "exam"]:
		return _fail("目前沒有可重試的活動。")
	data.pending.attempt = int(data.pending.get("attempt", 0)) + 1
	data.pending.combat = {}
	return {"ok": true, "message": "重新迎戰，不額外消耗時段或回復藥。", "pending_token": int(data.pending.token)}

func buy_medicine() -> Dictionary:
	if data.is_empty() or not data.get("pending", {}).is_empty() or str(data.phase) not in ["intro", "town"]:
		return _fail("請先回到鎮上，再購買回復藥。")
	if int(data.money) < Content.MEDICINE_PRICE:
		return _fail("一份回復藥需要 %d 文。" % Content.MEDICINE_PRICE)
	if int(data.medicine) >= 99:
		return _fail("行囊裡的藥已經足夠。")
	data.money = int(data.money) - Content.MEDICINE_PRICE
	data.medicine = int(data.medicine) + 1
	_journal("買了一份回復藥，花費 %d 文；沒有消耗行程。" % Content.MEDICINE_PRICE)
	return {"ok": true, "message": "回復藥 +1，盤纏 -%d 文。" % Content.MEDICINE_PRICE}

func prepare_exam_now() -> Dictionary:
	if data.is_empty() or not data.get("pending", {}).is_empty() or str(data.phase) not in ["intro", "town"]:
		return _fail("先完成目前的事情，再決定是否提前收拾行囊。")
	var unused: int = remaining()
	data.spent = Content.MAX_SLOTS
	data.phase = "town"
	data.dialogue = {}
	if unused > 0:
		_journal("選擇收拾行囊、靜候選拔，略過剩餘 %d 個時段。" % unused)
	return {"ok": true, "message": "第八日到了。可以前往入門選拔。", "forfeited_slots": unused}

func begin_exam() -> Dictionary:
	if not ready_for_exam():
		return _fail("完成七日準備後，才能參加入門選拔。")
	data.serial = int(data.serial) + 1
	data.pending = {"id": "exam", "token": int(data.serial), "cost": 0, "fee": 0, "start_spent": Content.MAX_SLOTS, "attempt": 0, "medicine_at_start": int(data.medicine), "stage": "story", "visited": [], "combat": {}}
	data.phase = "exam"
	data.dialogue = {}
	_journal("走上選拔劍坪。這七日做過的事，都跟著你一起來了。")
	return {"ok": true, "message": "入門選拔開始。", "pending_token": int(data.pending.token)}

func complete_exam(won: bool, detail: Dictionary = {}) -> Dictionary:
	var check: Dictionary = _check_pending(detail, true)
	if not bool(check.ok):
		return check
	_commit_medicine(detail)
	var eligible: Array = eligible_schools(won)
	data.exam_result = {"won": won, "eligible": eligible, "training": int(data.training), "insight": int(data.insight), "explorations": exploration_count(), "promise": has_kept_promise()}
	data.pending = {}
	data.phase = "results"
	data.dialogue = {}
	var message: String = "你完成了教頭切磋。" if won else "你向教頭拱手認輸，仍把這七日的經歷說清楚。"
	if eligible.is_empty():
		message += " 這次尚未獲得引薦，望溪鎮仍留著下一段路。"
	else:
		var names: PackedStringArray = []
		for school in eligible:
			names.append(str(Content.SCHOOLS[school].name))
		message += " 獲得%s的入門邀請。" % "、".join(names)
	_journal(message)
	return {"ok": true, "message": message, "eligible": eligible}

func choose_school(id: String) -> Dictionary:
	if data.is_empty() or str(data.phase) != "results":
		return _fail("尚未完成選拔，或已經選定去向。")
	if id != "stay" and id not in data.exam_result.get("eligible", []):
		return _fail("目前沒有這個門派的入門邀請。")
	data.school = id
	data.phase = "ending"
	data.dialogue = {}
	var message: String = "選擇了「%s」。入山之前，已經走出了自己的第一程。" % str(Content.SCHOOLS[id].name)
	_journal(message)
	return {"ok": true, "message": message, "school": id}

func exploration_count() -> int:
	var count: int = 0
	for id in Content.EXPLORATIONS:
		if id in data.get("completed", []):
			count += 1
	return count

func has_kept_promise() -> bool:
	return "missing_letter" in data.get("completed", []) or "escort_promise" in data.get("completed", [])

func eligible_schools(won: bool) -> Array:
	var eligible: Array = []
	if data.is_empty():
		return eligible
	if int(data.training) >= 6 and int(data.favor.get("shen", 0)) >= 2 and (won or has_kept_promise()):
		eligible.append("zhaoling")
	if int(data.insight) >= 6 and int(data.favor.get("lu", 0)) >= 2 and (exploration_count() >= 2 or (won and exploration_count() >= 1)):
		eligible.append("duyun")
	return eligible

func exam_requirements() -> Dictionary:
	return {
		"zhaoling": "武學至少 6、沈照嶺信任至少 2，且切磋勝出或完成一件守約委託（未送達的信／守約護送）。",
		"duyun": "見識至少 6、陸行雲信任至少 2，且完成兩次不同探索；切磋勝出時，一次探索即可。",
		"stay": "沒有入門邀請也能留鎮續修；已有邀請時同樣可以自選留鎮。",
	}

func story_context() -> Dictionary:
	return {
		"hero_name": str(data.get("hero_name", "行路人")), "origin": str(data.get("origin", "herbalist")),
		"day": day(), "remaining": remaining(), "training": int(data.get("training", 0)), "insight": int(data.get("insight", 0)),
		"has_sword_qi": has_skill("sword_qi"), "has_cloud_step": has_skill("cloud_step"),
		"school": str(data.get("school", "")),
	}

func save_game(path: String = SAVE_PATH) -> Dictionary:
	var validated: Dictionary = _validate_data(data)
	if not bool(validated.ok):
		return _fail("目前進度資料不完整，未覆蓋存檔：" + str(validated.message))
	var payload: String = JSON.stringify({"version": SAVE_VERSION, "data": data})
	if payload.to_utf8_buffer().size() > MAX_SAVE_BYTES:
		return _fail("存檔資料超出安全大小，未覆蓋既有存檔。")
	var temporary: String = path + ".tmp"
	var backup: String = path + ".bak"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _fail("無法寫入存檔。請保留遊戲視窗，檢查瀏覽器或資料夾的儲存權限。")
	file.store_string(payload)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		return _fail("寫入未完成，既有存檔已保留。")
	var had_old: bool = FileAccess.file_exists(path)
	if had_old:
		if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup) != OK:
			return _fail("無法更新備份，既有存檔已保留。")
		if DirAccess.rename_absolute(path, backup) != OK:
			return _fail("無法保留舊存檔，已停止更新。")
	if DirAccess.rename_absolute(temporary, path) != OK:
		if had_old:
			DirAccess.rename_absolute(backup, path)
		return _fail("無法完成存檔替換，已嘗試還原舊存檔。")
	return {"ok": true, "message": "旅程已儲存。"}

func load_game(path: String = SAVE_PATH) -> Dictionary:
	var primary: Dictionary = _read_save(path)
	if bool(primary.ok):
		data = primary.data
		return {"ok": true, "message": "旅程已讀取。", "recovered": false}
	var backup: Dictionary = _read_save(path + ".bak")
	if bool(backup.ok):
		data = backup.data
		return {"ok": true, "message": "主存檔未能讀取，已恢復上一份完整備份。", "recovered": true}
	return _fail(str(primary.message))

func _check_pending(detail: Dictionary, exam: bool) -> Dictionary:
	if data.is_empty() or data.get("pending", {}).is_empty():
		return _fail("這項活動已經結算，沒有重複發放獎勵。")
	var pending: Dictionary = data.pending
	var is_exam: bool = str(pending.get("id", "")) == "exam"
	if exam != is_exam or str(data.phase) != ("exam" if exam else "activity"):
		return _fail("活動狀態不符，沒有變更旅程。")
	if detail.has("pending_token") and (not _whole(detail.pending_token, 1, int(data.serial)) or int(detail.pending_token) != int(pending.token)):
		return _fail("這是較早活動的回覆，已忽略。")
	var used: Variant = detail.get("medicine_used", 0)
	if not _whole(used, 0, mini(int(data.medicine), int(pending.medicine_at_start))):
		return _fail("回復藥數量不符，未結算活動。")
	return {"ok": true, "message": ""}

func _commit_medicine(detail: Dictionary) -> void:
	data.medicine = int(data.medicine) - int(detail.get("medicine_used", 0))

func _journal(text: String, at_spent: int = -1) -> void:
	var stamp: int = int(data.get("spent", 0)) if at_spent < 0 else at_spent
	data.journal.append({"day": mini(8, stamp / 3 + 1), "text": text})
	if data.journal.size() > 200:
		data.journal.pop_front()

func _rewards_text(rewards: Dictionary) -> String:
	var parts: PackedStringArray = []
	var labels: Dictionary = {"money": "盤纏", "medicine": "回復藥", "training": "武學", "insight": "見識"}
	for key in labels:
		if int(rewards.get(key, 0)) > 0:
			parts.append("%s +%d" % [str(labels[key]), int(rewards[key])])
	for skill in rewards.get("skills", []):
		parts.append("學會「%s」" % str(Content.SKILLS[skill].name))
	return "、".join(parts) + "。" if not parts.is_empty() else "這份人情已經記下。"

func _read_save(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("還沒有這段旅程的存檔。")
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("無法開啟存檔，檔案已保留。")
	if file.get_length() > MAX_SAVE_BYTES:
		file.close()
		return _fail("存檔大小異常，檔案已保留。")
	var json: JSON = JSON.new()
	var error: Error = json.parse(file.get_as_text())
	file.close()
	if error != OK or not (json.data is Dictionary):
		return _fail("存檔格式損毀，未重設目前旅程。")
	var envelope: Dictionary = json.data
	if not _whole(envelope.get("version"), SAVE_VERSION, SAVE_VERSION) or not (envelope.get("data") is Dictionary):
		return _fail("這份存檔不是本作支援的版本。")
	return _validate_data(envelope.data)

func _validate_data(source: Dictionary) -> Dictionary:
	if source.is_empty() or not _json_safe(source, 0):
		return _fail("內容為空或含不支援的資料。")
	var result: Dictionary = source.duplicate(true)
	for key in ["hero_name", "origin", "phase", "school"]:
		if not (result.get(key) is String):
			return _fail("缺少文字欄位：" + key)
	if str(result.hero_name).is_empty() or str(result.hero_name).length() > 16 or not Content.ORIGINS.has(result.origin) or result.phase not in PHASES:
		return _fail("主角或階段資料不符。")
	var limits: Dictionary = {"spent": 21, "money": 99999, "medicine": 99, "training": 60, "insight": 60, "serial": 1000000}
	for key in limits:
		if not _whole(result.get(key), 0, int(limits[key])):
			return _fail("數值範圍不符：" + key)
		result[key] = int(result[key])
	if not (result.get("favor") is Dictionary):
		return _fail("缺少人物關係。")
	for npc in Content.NPCS:
		if not _whole(result.favor.get(npc), 0, 9):
			return _fail("人物關係數值不符。")
		result.favor[npc] = int(result.favor[npc])
	for field in ["skills", "completed"]:
		if not (result.get(field) is Array) or result[field].size() > 32:
			return _fail("活動或武功清單不符。")
		var seen: Array = []
		for id in result[field]:
			if not (id is String) or id in seen:
				return _fail("活動或武功清單有重複或錯誤項目。")
			if field == "skills" and not Content.SKILLS.has(id):
				return _fail("不認得的武功。")
			if field == "completed" and not Content.ACTIVITIES.has(id):
				return _fail("不認得的活動。")
			seen.append(id)
	if not (result.get("journal") is Array) or result.journal.size() > 200:
		return _fail("紀事資料不符。")
	for entry in result.journal:
		if not (entry is Dictionary) or not (entry.get("text") is String) or str(entry.text).length() > 2048 or not _whole(entry.get("day"), 1, 8):
			return _fail("紀事項目損毀。")
		entry.day = int(entry.day)
	if not (result.get("pending") is Dictionary) or not (result.get("exam_result") is Dictionary):
		return _fail("活動進度資料不符。")
	var pending: Dictionary = result.pending
	if not pending.is_empty():
		if not (pending.get("id") is String) or (pending.id != "exam" and not Content.ACTIVITIES.has(pending.id)):
			return _fail("進行中的活動不存在。")
		var expected_cost: int = 0 if pending.id == "exam" else int(Content.ACTIVITIES[pending.id].cost)
		var expected_fee: int = 0 if pending.id == "exam" else int(Content.ACTIVITIES[pending.id].get("fee", 0))
		for key in ["cost", "fee", "start_spent", "attempt", "medicine_at_start", "token"]:
			if not _whole(pending.get(key), 0, 1000000):
				return _fail("活動檢查點不完整。")
			pending[key] = int(pending[key])
		if pending.cost != expected_cost or pending.fee != expected_fee or pending.start_spent + pending.cost != result.spent or pending.token <= 0 or pending.token > result.serial or pending.medicine_at_start > 99:
			return _fail("活動成本與行程不一致。")
		if pending.id == "exam" and (result.spent != 21 or result.phase != "exam"):
			return _fail("選拔日期不符。")
		if pending.id != "exam" and result.phase != "activity":
			return _fail("活動階段不符。")
		if pending.has("stage") and (not (pending.stage is String) or pending.stage not in ["", "story", "explore", "combat", "task", "defeat", "debrief"]):
			return _fail("活動場景不符。")
		if pending.has("visited"):
			if not (pending.visited is Array) or pending.visited.size() > 32:
				return _fail("探索標記不符。")
			for marker in pending.visited:
				if not (marker is String) or marker.length() > 128:
					return _fail("探索標記內容不符。")
		if pending.has("combat") and not (pending.combat is Dictionary):
			return _fail("戰鬥檢查點不符。")
		if pending.has("report") and not (pending.report is Dictionary):
			return _fail("戰鬥結果檢查點不符。")
		if pending.has("battle_won") and not (pending.battle_won is bool):
			return _fail("戰鬥勝負資料不符。")
		if pending.has("world_position") and not _valid_position(pending.world_position):
			return _fail("探索位置不符。")
	elif result.phase in ["activity", "exam"]:
		return _fail("活動階段缺少進度。")
	if result.phase in ["results", "ending"]:
		if result.spent != 21 or not (result.exam_result.get("won") is bool) or not (result.exam_result.get("eligible") is Array):
			return _fail("選拔結果不完整。")
		var seen_schools: Array = []
		for id in result.exam_result.eligible:
			if id not in ["zhaoling", "duyun"] or id in seen_schools:
				return _fail("選拔邀請不符。")
			seen_schools.append(id)
		if result.phase == "ending" and result.school != "stay" and result.school not in seen_schools:
			return _fail("所選門派沒有邀請。")
		if result.phase == "ending" and not Content.SCHOOLS.has(result.school):
			return _fail("去向不符。")
	elif not result.exam_result.is_empty() or not str(result.school).is_empty():
		return _fail("選拔前出現結局資料。")
	if result.has("world_position") and not _valid_position(result.world_position):
		return _fail("城鎮位置不符。")
	if result.has("dialogue"):
		if not (result.dialogue is Dictionary):
			return _fail("對話進度不符。")
		for key in result.dialogue:
			if key not in ["title", "cursor", "revision", "after", "return_npc"] or not (result.dialogue[key] is String) or str(result.dialogue[key]).length() > 256:
				return _fail("對話檢查點不符。")
	return {"ok": true, "message": "", "data": result}

func _valid_position(value: Variant) -> bool:
	if not (value is Array) or value.size() != 2:
		return false
	for number in value:
		if not (number is int or number is float) or not is_finite(float(number)) or absf(float(number)) > 10000.0:
			return false
	return true

func _whole(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) <= maximum

func _json_safe(value: Variant, depth: int) -> bool:
	if depth > 12:
		return false
	if value == null or value is bool or value is int:
		return true
	if value is float:
		return is_finite(value)
	if value is String:
		return value.length() <= 4096
	if value is Array:
		if value.size() > 512:
			return false
		for item in value:
			if not _json_safe(item, depth + 1):
				return false
		return true
	if value is Dictionary:
		if value.size() > 128:
			return false
		for key in value:
			if not (key is String or key is StringName) or str(key).length() > 128 or not _json_safe(value[key], depth + 1):
				return false
		return true
	return false

func _fail(message: String) -> Dictionary:
	return {"ok": false, "message": message}
