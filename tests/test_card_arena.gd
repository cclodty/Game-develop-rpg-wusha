extends SceneTree
## Real view controls exercise explicit spending, retention and in-flight choices.
const Arena = preload("res://scripts/card_arena.gd")
const Cards = preload("res://scripts/card_catalog.gd")
const UI = preload("res://scripts/card_ui.gd")
var passed = 0
var failed = 0
var finished_count = 0
var changed_count = 0
var arena
var active_stats: Dictionary = {}

func _initialize() -> void: call_deferred("_run")

func expect(value: bool, description: String) -> void:
	if value:
		passed += 1
		print("PASS CARD ARENA: " + description)
	else:
		failed += 1
		push_error("FAIL CARD ARENA: " + description)

func hero_stats(preset: String = "shouzhong", seed: int = 1, refinements: Dictionary = {}) -> Dictionary:
	var selected: Dictionary = Cards.PRESETS[preset]
	return {"name": "試招少俠", "origin": "courier", "attributes": {"constitution": 5, "strength": 5, "agility": 5, "resolve": 5, "aptitude": 5, "fortune": 5}, "deck": selected.deck.duplicate(), "weapon": selected.weapon, "inner": selected.inner, "refinements": refinements.duplicate(), "medicine": 1, "seed": seed, "upgraded_cards": refinements.keys(), "exam_aid": 0}

func fresh(mode: String = "practice", preset: String = "shouzhong", seed: int = 1, refinements: Dictionary = {}) -> bool:
	if is_instance_valid(arena): arena.free()
	arena = Arena.new()
	root.add_child(arena)
	arena.set_process(false)
	# This fixture rapidly replaces encounters without waiting for real audio time.
	# The dummy mixer can otherwise retain a WAV playback after its node is freed.
	# Sound stays enabled in rendered game runs; this fixture checks input/state.
	if DisplayServer.get_name() == "headless": arena._sound.stream = null
	arena.finished.connect(func(_won, _report): finished_count += 1)
	arena.changed.connect(func(): changed_count += 1)
	active_stats = hero_stats(preset, seed, refinements)
	var result: Dictionary = arena.configure(mode, active_stats)
	expect(result.ok, "new %s / %s encounter accepts its preparation" % [mode, preset])
	return result.ok

func find_hand(ids: Array, preset: String = "xingyun", mode: String = "practice", refinements: Dictionary = {}) -> void:
	for seed in range(1, 200):
		var candidate = Arena.Battle.new()
		candidate.configure(mode, hero_stats(preset, seed, refinements))
		var found = true
		for id in ids: found = found and id in candidate.status().hand
		if found:
			fresh(mode, preset, seed, refinements)
			return
	expect(false, "a legal shuffled hand contains requested test cards")

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
		if not Rect2(Vector2.ZERO, Arena.SIZE).grow(1).encloses(button.get_global_rect()): outside.append(id)
	expect(outside.is_empty(), "all actionable controls fit 1080x640: " + str(outside))

func restored_view(saved: Dictionary):
	var restored = Arena.new()
	root.add_child(restored)
	restored.set_process(false)
	if DisplayServer.get_name() == "headless": restored._sound.stream = null
	var result: Dictionary = restored.configure(arena.mode, active_stats, JSON.parse_string(JSON.stringify(saved)))
	expect(result.ok, "exact JSON snapshot restores into a separate view: " + str(result.get("message", "")))
	return restored

func play_id(id: String, boosted: bool = false) -> bool:
	var index: int = arena.status().hand.find(id)
	if index < 0: return false
	if not arena.select_card(index): return false
	return press("play_boost" if boosted else "play_normal")

func _run() -> void:
	fresh()
	expect(arena.status().phase == "mulligan" and arena.status().hand.size() == 5, "five opening cards and once-only mulligan are visible")
	fit()
	press("card_0")
	press("card_1")
	expect(arena.mulligan_selection == [0, 1] and not arena.select_card(2), "opening choice respects resolve limit")
	var saved: Dictionary = arena.snapshot()
	var restored = restored_view(saved)
	expect(restored.mulligan_selection == [0, 1] and restored.snapshot() == saved, "opening selection restores without drawing or changing RNG")
	restored.free()
	var before_changes = changed_count
	press("mulligan_confirm")
	expect(arena.status().phase == "player" and changed_count == before_changes + 1, "visible redraw performs exactly one action notification")
	expect(not arena.confirm_mulligan(), "opening redraw cannot repeat")
	var before: Dictionary = arena.battle.snapshot()
	press("card_0")
	expect(arena.selected_card == 0 and arena.battle.snapshot() == before, "selecting any card never automatically spends qi or momentum")
	expect(arena.action_buttons.has("play_normal") and arena.action_buttons.has("play_boost"), "ordinary and empowered actions are explicit separate controls")
	press("retain_selected")
	expect(arena.retained_index == 0 and arena.battle.snapshot() == before, "marking a retained card is only a saved view choice")
	saved = arena.snapshot()
	restored = restored_view(saved)
	expect(restored.retained_index == 0 and restored.selected_card == 0 and restored.snapshot() == saved, "retained card and selected target restore exactly")
	restored.free()
	var retained: String = str(arena.status().hand[0])
	press("end_turn")
	expect(arena.status().hand.size() == 5 and retained in arena.status().hand and arena.retained_index == -1, "retaining one card fills to five, then clears next-turn marker")
	before = arena.battle.snapshot()
	arena.advance_presentation(1000)
	expect(arena.battle.snapshot() == before, "real time never advances the card model")
	press("rules")
	fit()
	expect(not arena.end_turn() and not arena.play_selected(), "read-only rules modal blocks combat inputs")
	saved = arena.snapshot()
	restored = restored_view(saved)
	expect(restored.view_state().panel == "rules" and restored.snapshot() == saved, "open rule view restores with underlying battle unchanged")
	restored.free()
	arena.set_input_enabled(false)
	var disabled = true
	for button in arena.action_buttons.values(): disabled = disabled and button.disabled
	expect(disabled and not arena.close_panel() and not arena.select_card(0), "external pause disables every UI action including modal close")
	var age: float = arena._visual_age
	arena.advance_presentation(999)
	expect(arena._visual_age == age and arena.snapshot() == saved, "pause freezes effects without modifying saved choices")
	arena.set_input_enabled(true)
	press("panel_close")
	press("deck")
	press("pile_hand")
	expect(arena._pile_cards("hand") == arena.status().hand, "pile viewer displays actual current cards")
	press("pile_draw")
	expect(arena._pile_cards("draw").size() == arena.status().draw_count, "draw viewer counts without exposing draw order")
	fit()
	press("panel_close")
	expect(arena.battle.snapshot() == before, "rule and pile inspection never changes state")
	# Real cycle payment and two-card refinement, saved in the middle of the choice.
	find_hand(["cloud_step"], "xingyun", "practice", {"cloud_step": "specialist"})
	press("mulligan_skip")
	expect(play_id("cloud_step"), "ordinary button legally starts a refined cycle card")
	expect(arena.status().phase == "choice" and arena.status().pending_choice.max_count == 2 and arena.status().qi == 2, "choice phase records already-paid qi and two-card capacity")
	var protected: Dictionary = arena.battle.snapshot()
	press("card_0")
	press("card_1")
	expect(arena.cycle_selection == [0, 1] and not arena.select_card(2), "cycle card buttons toggle at most the allowed count")
	expect(not arena.end_turn() and not arena.play_selected() and not arena.use_medicine(), "in-flight cycle forbids unrelated combat actions")
	saved = arena.snapshot()
	restored = restored_view(saved)
	expect(restored.cycle_selection == [0, 1] and restored.snapshot() == saved, "in-flight selection and paid effects survive exact JSON restore")
	restored.free()
	fit()
	press("cycle_confirm")
	expect(arena.status().phase == "player" and arena.status().qi == protected.qi and arena.status().cards_played == protected.cards_played, "confirm cycle finishes once without paying or playing the card again")
	expect(arena.cycle_selection.is_empty() and not arena.confirm_cycle([0]), "completed cycle cannot be replayed for another reward")
	# The optional zero-card choice is an actual visible operation.
	find_hand(["cloud_step"], "xingyun")
	press("mulligan_skip")
	play_id("cloud_step")
	protected = arena.battle.snapshot()
	press("cycle_skip")
	expect(arena.status().phase == "player" and arena.status().hand == protected.hand and arena.status().qi == protected.qi, "skip cycle preserves hand and finishes the paid action")
	# Empowered use is blocked at zero momentum and only legal after generating it.
	find_hand(["gather_momentum", "yielding_palm"], "shouzhong")
	press("mulligan_skip")
	arena.select_card(arena.status().hand.find("yielding_palm"))
	before = arena.battle.snapshot()
	expect(arena.action_buttons.play_boost.disabled and not arena.play_selected(true), "zero momentum leaves ordinary mode available but rejects empowerment")
	expect(arena.battle.snapshot() == before, "rejected empowerment spends nothing")
	arena.cancel_selection()
	play_id("gather_momentum")
	arena.select_card(arena.status().hand.find("yielding_palm"))
	var actual_preview: Dictionary = arena.battle.preview_card(arena.selected_card, 0, true)
	expect(not arena.action_buttons.play_boost.disabled and arena.action_buttons.play_boost.tooltip_text == actual_preview.description, "empowered button exposes the exact model preview")
	before = arena.battle.snapshot()
	press("play_boost")
	expect(arena.status().qi == before.qi - 1 and arena.status().momentum == 0 and arena.status().retaliation == 6, "explicit empowerment pays one qi and one momentum, preparing retaliation")
	arena.select_card(0)
	var counter_label: Control = arena.find_child("RetaliationReady", true, false)
	var preview_panel: Control = arena.find_child("EffectPreview", true, false)
	expect(is_instance_valid(counter_label) and is_instance_valid(preview_panel) and not counter_label.get_global_rect().intersects(preview_panel.get_global_rect()), "a selected card preview leaves the prepared retaliation visible")
	press("end_turn")
	expect(arena.status().enemies[0].hp < before.enemies[0].hp, "visible defensive empowerment counterattacks a real enemy action")
	# A real draw card grows the hand and exposes the sixth selectable card.
	find_hand(["observe"], "xingyun")
	press("mulligan_skip")
	play_id("observe")
	expect(arena.status().hand.size() == 6, "draw-two grows the hand above five through a legal action")
	press("hand_next")
	expect(arena.action_buttons.has("card_5") and not arena.action_buttons.has("card_0"), "sixth card is available on page two")
	press("card_5")
	saved = arena.snapshot()
	restored = restored_view(saved)
	expect(restored.action_buttons.has("card_5") and restored.selected_card == 5, "second page and selected sixth card restore")
	restored.free()
	fit()
	if not arena.action_buttons.play_normal.disabled:
		var played_before: int = arena.status().cards_played
		press("play_normal")
		expect(arena.status().cards_played == played_before + 1, "sixth card can be explicitly played")
		if arena.status().phase == "choice": press("cycle_skip")
	# Target selection is also non-mutating until the action button is pressed.
	find_hand(["strike"], "shouzhong", "grove")
	press("mulligan_skip")
	arena.select_card(arena.status().hand.find("strike"))
	before = arena.battle.snapshot()
	press("target_1")
	expect(arena.selected_target == 1 and arena.battle.snapshot() == before, "choosing second enemy changes only view selection")
	press("play_normal")
	expect(arena.status().enemies[0].hp == before.enemies[0].hp and arena.status().enemies[1].hp < before.enemies[1].hp, "explicit normal action hits selected second enemy")
	press("end_turn")
	before = arena.battle.snapshot()
	press("medicine")
	expect(arena.status().medicine_used == 1 and arena.status().qi == before.qi - 1 and arena.action_buttons.medicine.disabled, "medicine costs one qi and is limited once per battle")
	press("end_turn")
	expect(arena.action_buttons.medicine.disabled, "next turn does not reset the medicine allowance")
	# Win using only public card and turn actions, never editing enemy state.
	fresh()
	press("mulligan_skip")
	for turn in range(40):
		if arena.status().resolved: break
		for action in range(30):
			if arena.status().resolved: break
			var current: Dictionary = arena.status()
			if current.phase == "choice": arena.confirm_cycle([]); continue
			var best = -1
			var boosted = false
			var score_best = -1.0
			for index in range(current.hand.size()):
				for boost in [false, true]:
					var preview: Dictionary = arena.battle.preview_card(index, 0, boost)
					if not preview.get("can_play", false): continue
					var card: Dictionary = Cards.card(current.hand[index], "", boost)
					var damage = 0.0
					for hit in preview.get("damage", []): damage += hit.hp_loss
					var score = damage * 6 + float(preview.get("block", 0)) * 0.7 + float(card.get("energy", 0)) * 20 + float(card.get("momentum_gain", 0)) * 4 + float(preview.get("momentum_gain", 0)) * 2
					if score > score_best: best = index; boosted = boost; score_best = score
			if best < 0: break
			arena.select_card(best)
			if not arena.play_selected(boosted): break
		if not arena.status().resolved: arena.end_turn()
	expect(arena.status().won, "real explicit card controls win a practice encounter")
	var old_finished = finished_count
	arena.set_input_enabled(false)
	arena.advance_presentation(1)
	expect(finished_count == old_finished, "paused terminal effects cannot send completion")
	arena.set_input_enabled(true)
	arena.advance_presentation(1)
	arena.advance_presentation(1)
	expect(finished_count == old_finished + 1 and arena.last_report.won, "completed view sends its real result exactly once")
	var victory = arena.snapshot()
	var completions: Array = []
	restored = restored_view(victory)
	restored.finished.connect(func(won, report): completions.append([won, report]))
	await process_frame
	restored.advance_presentation(1)
	expect(completions.size() == 1 and completions[0][0], "completed save emits only one result on restoration")
	restored.free()
	var broken: Dictionary = victory.duplicate(true)
	broken.hp = -20
	expect(not arena.configure("practice", active_stats, broken).ok and not arena.restore_error.is_empty(), "invalid snapshot reports a restore failure")
	expect(arena.snapshot().is_empty() and arena.action_buttons.is_empty() and arena.status().phase == "error", "invalid restore never silently creates a fresh battle")
	expect(not arena.configure("practice", active_stats, {"_view": {"panel": "rules"}}).ok, "view-only snapshot cannot masquerade as a saved battle")
	# Every concrete refinement face has real Godot text layout checked.
	var host = Control.new()
	root.add_child(host)
	var faces: Array = []
	for id in Cards.CARDS:
		for branch in ["", "stable", "specialist"]:
			if not branch.is_empty() and id not in Cards.REFINABLE: continue
			faces.append(UI.card_button(host, Cards.card(id, branch), Vector2.ZERO, Vector2(202, 196), func(): pass))
	for frame in range(5): await process_frame
	var overflowing: Array = []
	for face: Button in faces:
		for child in face.get_children():
			if child is Control and not Rect2(Vector2.ZERO, face.size).grow(1).encloses(Rect2(child.position, child.size)): overflowing.append(child.name)
			if child is Label and child.name == "Effect" and child.get_line_count() * child.get_line_height() > child.size.y + 1: overflowing.append(child.text)
	expect(overflowing.is_empty(), "all twelve cards and six refinement faces fit readable text bounds: " + str(overflowing))
	host.free()
	arena.free()
	for frame in range(3): await process_frame
	print("TESTS COMPLETE: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
