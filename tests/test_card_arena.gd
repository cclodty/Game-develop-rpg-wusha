extends SceneTree
## Real view actions exercise selection, paging, pause and deterministic restore.
const Arena = preload("res://scripts/card_arena.gd")
const Cards = preload("res://scripts/card_catalog.gd")
const UI = preload("res://scripts/card_ui.gd")
var passed: int = 0
var failed: int = 0
var finished_count: int = 0
var changed_count: int = 0
var arena

func _initialize() -> void:
	call_deferred("_run")

func expect(value: bool, description: String) -> void:
	if value:
		passed += 1
		print("PASS CARD ARENA: " + description)
	else:
		failed += 1
		push_error("FAIL CARD ARENA: " + description)

func hero_stats(seed: int = 1) -> Dictionary:
	return {"name": "試招少俠", "origin": "courier", "attributes": {"constitution": 5, "strength": 5, "agility": 5, "resolve": 5, "aptitude": 5, "fortune": 5}, "deck": Cards.starting_deck(), "medicine": 3, "seed": seed, "upgraded_cards": [], "exam_aid": 0}

func fresh(mode: String = "practice", seed: int = 1) -> void:
	if is_instance_valid(arena):
		arena.free()
	arena = Arena.new()
	root.add_child(arena)
	arena.set_process(false)
	arena.finished.connect(func(_won, _report): finished_count += 1)
	arena.changed.connect(func(): changed_count += 1)
	expect(arena.configure(mode, hero_stats(seed)).ok, "new %s encounter accepts valid stats" % mode)

func press(id: String) -> bool:
	var button = arena.action_buttons.get(id)
	if not is_instance_valid(button) or button.disabled:
		expect(false, "enabled visible button: " + id)
		return false
	button.pressed.emit()
	return true

func fit() -> void:
	var outside: Array = []
	for id in arena.action_buttons:
		var button: Button = arena.action_buttons[id]
		if not Rect2(Vector2.ZERO, Arena.SIZE).grow(1).encloses(button.get_global_rect()):
			outside.append(id)
	expect(outside.is_empty(), "all active controls fit 1080×640: " + str(outside))

func first_attack() -> int:
	var hand: Array = arena.status().hand
	for index in range(hand.size()):
		if Cards.card(hand[index]).target == "enemy":
			return index
	return -1

func _run() -> void:
	fresh()
	expect(arena.status().phase == "mulligan" and arena.status().hand.size() == 5, "encounter begins with five cards and an unspent mulligan")
	fit()
	press("card_0")
	press("card_1")
	expect(arena.mulligan_selection == [0, 1], "real card buttons select mulligan indices")
	expect(not arena.select_card(2), "mulligan respects resolve limit")
	var saved: Dictionary = arena.snapshot()
	var restored = Arena.new()
	root.add_child(restored)
	restored.set_process(false)
	expect(restored.configure("practice", hero_stats(), JSON.parse_string(JSON.stringify(saved))).ok, "JSON battle snapshot restores")
	expect(restored.mulligan_selection == [0, 1] and restored.snapshot() == saved, "mulligan selections restore without drawing or using RNG")
	restored.free()
	var prior_changes: int = changed_count
	press("mulligan_confirm")
	expect(arena.status().phase == "player" and arena.status().hand.size() == 5 and changed_count == prior_changes + 1, "confirm changes phase once and emits autosave notification")
	var preview_index: int = first_attack()
	if preview_index >= 0:
		var preview: Dictionary = arena.battle.preview_card(preview_index, 0)
		var shown: Dictionary = arena._hand_card(preview_index, arena.status())
		expect(shown.face_description.contains("本次 %d 傷害" % (preview.damage[0].amount + preview.damage[0].blocked)), "card face includes actual first-attack attribute bonus")
		expect(shown.preview_tooltip.contains(preview.description), "full tooltip retains model-authored state-sensitive preview")
	expect(not arena.confirm_mulligan(), "mulligan cannot be repeated")
	var before: Dictionary = arena.battle.snapshot()
	arena.advance_presentation(1000)
	expect(arena.battle.snapshot() == before, "elapsed real time never advances the model")
	press("rules")
	fit()
	expect(arena.view_state().panel == "rules" and arena.battle.snapshot() == before, "rules panel leaves turn and piles intact")
	expect(not arena.end_turn(), "modal blocks battle actions")
	var modal_snapshot: Dictionary = arena.snapshot()
	restored = Arena.new()
	root.add_child(restored)
	restored.set_process(false)
	expect(restored.configure("practice", hero_stats(), modal_snapshot).ok and restored.view_state().panel == "rules", "save restores an open rules panel")
	restored.free()
	arena.set_input_enabled(false)
	var all_disabled: bool = true
	for button in arena.action_buttons.values(): all_disabled = all_disabled and button.disabled
	expect(all_disabled, "external pause disables every button including modal close")
	expect(not arena.close_panel() and not arena.use_medicine() and not arena.select_card(0), "public actions also respect pause")
	var visual_age: float = arena._visual_age
	arena.advance_presentation(999)
	expect(arena._visual_age == visual_age and arena.snapshot() == modal_snapshot, "pause freezes presentation and preserves complete snapshot")
	arena.set_input_enabled(true)
	press("panel_close")
	press("deck")
	press("pile_hand")
	expect(arena._pile_cards("hand") == arena.status().hand, "hand viewer contains the actual current hand")
	press("pile_draw")
	expect(arena._pile_cards("draw").size() == arena.status().draw_count, "draw viewer has the real draw pile")
	fit()
	press("panel_close")
	expect(arena.battle.snapshot() == before, "opening and closing all utility views never changes battle")
	# The actual draw-two card grows a real five-card hand; no debug pile edits.
	for seed in range(1, 100):
		fresh("practice", seed)
		if "observe" in arena.status().hand:
			break
	press("mulligan_skip")
	var draw_index: int = arena.status().hand.find("observe")
	press("card_" + str(draw_index))
	expect(arena.status().hand.size() == 6, "playing draw-two legally grows hand above five")
	press("hand_next")
	expect(arena.action_buttons.has("card_5") and not arena.action_buttons.has("card_0"), "sixth card has a reachable real button on page two")
	fit()
	var six_snapshot: Dictionary = arena.snapshot()
	restored = Arena.new()
	root.add_child(restored)
	restored.set_process(false)
	expect(restored.configure("practice", hero_stats(int(six_snapshot.seed)), six_snapshot).ok and restored.action_buttons.has("card_5"), "saved second hand page restores with its actionable sixth card")
	restored.free()
	var played_before: int = arena.status().cards_played
	press("card_5")
	expect(arena.status().cards_played == played_before + 1, "sixth card can actually be played")
	# Multiple opponents require an explicit target; selecting alone spends nothing.
	for seed in range(1, 100):
		fresh("grove", seed)
		if first_attack() >= 0:
			break
	press("mulligan_skip")
	var attack_index: int = first_attack()
	before = arena.battle.snapshot()
	press("card_" + str(attack_index))
	expect(arena.selected_card == attack_index and arena.battle.snapshot() == before, "targeted attack waits for enemy selection without spending qi")
	var selecting: Dictionary = arena.snapshot()
	restored = Arena.new()
	root.add_child(restored)
	restored.set_process(false)
	expect(restored.configure("grove", hero_stats(int(selecting.seed)), selecting).ok and restored.selected_card == attack_index, "pending target selection survives restore")
	restored.free()
	press("target_1")
	expect(arena.status().enemies[0].hp == before.enemies[0].hp and arena.status().enemies[1].hp < before.enemies[1].hp, "selected second enemy receives the attack")
	press("end_turn")
	expect(arena.status().turn == 2 and arena.status().hp < arena.status().max_hp, "end-turn button executes readable enemy intentions")
	press("medicine")
	expect(arena.status().medicine_used == 1 and arena.action_buttons.medicine.disabled, "medicine can be used once this turn")
	# Reach a real victory through legal play, then hold its short presentation.
	fresh()
	press("mulligan_skip")
	for turn in range(50):
		if arena.status().resolved: break
		for action in range(30):
			if arena.status().resolved: break
			var current: Dictionary = arena.status()
			var best: int = -1
			var best_score: int = -999
			for index in range(current.hand.size()):
				var card: Dictionary = Cards.card(current.hand[index])
				if card.cost > current.qi: continue
				var score: int = 100 if card.has("energy") else (80 if card.type == "attack" else (40 if card.has("draw") else 20))
				if score > best_score: best = index; best_score = score
			if best < 0: break
			if not arena.select_card(best): break
		if not arena.status().resolved: arena.end_turn()
	expect(arena.status().won, "legal card actions win the practice encounter")
	var finished_before: int = finished_count
	arena.set_input_enabled(false)
	arena.advance_presentation(1)
	expect(finished_count == finished_before, "paused final presentation cannot deliver rewards early")
	arena.set_input_enabled(true)
	arena.advance_presentation(1)
	arena.advance_presentation(1)
	expect(finished_count == finished_before + 1 and arena.last_report.won, "resolved encounter emits finished exactly once with actual report")
	var victory: Dictionary = arena.snapshot()
	var restore_events: Array = []
	restored = Arena.new()
	root.add_child(restored)
	restored.set_process(false)
	restored.finished.connect(func(won, value): restore_events.append([won, value]))
	expect(restored.configure("practice", hero_stats(), victory).ok, "completed encounter snapshot validates")
	await process_frame
	restored.advance_presentation(1)
	expect(restore_events.size() == 1 and restore_events[0][0], "restored completion emits once after configuration")
	restored.free()
	var broken: Dictionary = victory.duplicate(true)
	broken.hp = -20
	expect(not arena.configure("practice", hero_stats(), broken).ok and not arena.restore_error.is_empty(), "invalid restore reports the failure")
	expect(arena.snapshot().is_empty() and arena.action_buttons.is_empty() and arena.status().phase == "error", "invalid restore does not silently start a new encounter")
	arena.advance_presentation(100)
	expect(finished_count == finished_before + 1, "invalid restore does not emit a completion")
	expect(not arena.configure("practice", hero_stats(), {"_view": {"panel": "rules"}}).ok, "interface-only restore is rejected rather than becoming a new battle")
	# All eighteen upgraded faces are measured using actual Godot font layout.
	var host = Control.new()
	root.add_child(host)
	var cards: Array = []
	for id in Cards.CARDS:
		var card: Dictionary = Cards.card(id, true)
		cards.append(UI.card_button(host, card, Vector2.ZERO, Vector2(202, 205), func(): pass))
	await process_frame
	var overflowing: Array = []
	for card: Button in cards:
		for child in card.get_children():
			if child is Control and not Rect2(Vector2.ZERO, card.size).grow(1).encloses(Rect2(child.position, child.size)):
				overflowing.append("%s %s card=%s child=%s/%s" % [card.tooltip_text.get_slice("\n", 0), child.name, card.size, child.position, child.size])
	expect(overflowing.is_empty(), "all upgraded card faces, labels and illustrations fit without clipping: " + str(overflowing))
	host.free()
	arena.free()
	for frame in range(3): await process_frame
	await create_timer(0.2).timeout
	print("TESTS COMPLETE: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
