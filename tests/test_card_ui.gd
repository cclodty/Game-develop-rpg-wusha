extends SceneTree
## Real native scene integration for martial v3. Uses live controls and legal
## card actions; ending eligibility alone uses labeled presentation fixtures.
## Player save directories must be isolated. This is not a human playtest.

const MainScene = preload("res://scenes/main.tscn")
const Run = preload("res://scripts/run_state.gd")
const Cards = preload("res://scripts/card_catalog.gd")
const Creation = preload("res://scripts/character_creation.gd")
var passed: int = 0
var failed: int = 0
var app: Control
var battle_coverage: Dictionary = {"normal": false, "boost": false, "cycle": false, "retain": false, "lab_choice_restore": false}
var _checkpoint_cycle = false


func _initialize() -> void:
	call_deferred("_run")


func expect(condition: bool, description: String) -> void:
	if condition:
		passed += 1
		print("PASS CARD UI: " + description)
	else:
		failed += 1
		push_error("FAIL CARD UI: " + description)


func frames(count: int = 2) -> void:
	for _frame in range(count):
		await process_frame


func same_saved_value(left: Variant, right: Variant) -> bool:
	# JSON preserves integral values, but loads them as floats before individual
	# model fields are normalized. Compare the actual persistence representation.
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))


func capture(label: String) -> void:
	var directory: String = OS.get_environment("WEIYUAN_CARD_UI_CAPTURE_DIR")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(directory)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join(label + ".png"))


func action_sets() -> Array:
	var result: Array = []
	for child in [app.creation_journey, app.arena, app]:
		if is_instance_valid(child):
			var value = child.get("action_buttons")
			if value is Dictionary:
				result.append(value)
	return result


func button_for(action: String) -> Button:
	for buttons: Dictionary in action_sets():
		var button = buttons.get(action)
		if is_instance_valid(button) and button is Button and button.is_visible_in_tree():
			return button
	return null


func press(action: String) -> bool:
	var button: Button = button_for(action)
	if button == null or button.disabled:
		expect(false, "visible enabled action: " + action)
		return false
	var ancestor: Node = button.get_parent()
	while ancestor != null and ancestor != app:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(button)
		ancestor = ancestor.get_parent()
	await frames()
	if not is_instance_valid(button):
		expect(false, "action remains available after scrolling: " + action)
		return false
	button.pressed.emit()
	await frames()
	return true


func fit(view: String) -> void:
	var outside: Array[String] = []
	var viewport := Rect2(Vector2.ZERO, Vector2(1440, 900))
	for buttons: Dictionary in action_sets():
		for action in buttons:
			var button = buttons[action]
			if not is_instance_valid(button) or not button.is_visible_in_tree():
				continue
			var visible_rect: Rect2 = button.get_global_rect()
			var ancestor: Node = button.get_parent()
			while ancestor != null and ancestor != app:
				if ancestor is Control and ancestor.clip_contents:
					visible_rect = visible_rect.intersection(ancestor.get_global_rect())
				ancestor = ancestor.get_parent()
			if visible_rect.has_area() and not viewport.grow(1).encloses(visible_rect):
				outside.append(str(action))
	expect(outside.is_empty(), view + " controls fit the viewport: " + str(outside))


func text_under(node: Node) -> String:
	var result: String = str(node.text) + "\n" if node is Label or node is Button else ""
	for child in node.get_children():
		result += text_under(child)
	return result


func prologue_body_visible(description: String) -> void:
	# A Label can retain its text while a VBox gives it zero height. Verify the
	# actual laid-out prose rather than only checking model content or buttons.
	var creation: Dictionary = app.run.data.creation
	var index: int = int(creation.question)
	var content: Dictionary = Creation.response(creation, index, app.run.data.origin, app.run.data.hero_name) if creation.page == "aftermath" else Creation.scene(creation, index, app.run.data.origin, app.run.data.hero_name)
	var found_visible: bool = false
	for label in app.creation_journey.find_children("*", "Label", true, false):
		if label.text != str(content.body):
			continue
		var visible_rect: Rect2 = label.get_global_rect()
		var ancestor: Node = label.get_parent()
		while ancestor != app.creation_journey:
			if ancestor is Control and ancestor.clip_contents:
				visible_rect = visible_rect.intersection(ancestor.get_global_rect())
			ancestor = ancestor.get_parent()
		found_visible = label.is_visible_in_tree() and label.get_line_count() > 0 and label.get_visible_line_count() > 0 and visible_rect.size.y >= label.get_line_height() and label.size.y + 4 >= label.get_line_count() * label.get_line_height()
	expect(found_visible, description + ": authored prose renders readable lines inside its scroll viewport")


func summary_text_fits() -> void:
	var failures: Array[String] = []
	for panel in app.creation_journey.get_children():
		if not panel is Panel or panel.size.x > 400:
			continue
		for label in panel.get_children():
			if not label is Label:
				continue
			if not Rect2(Vector2.ZERO, panel.size).grow(1).encloses(label.get_rect()) or label.get_line_count() < 1 or label.get_visible_line_count() < 1 or label.get_line_count() * label.get_line_height() > label.size.y + 4:
				failures.append(label.text)
	expect(failures.is_empty(), "ability explanations wrap completely within their cards: " + str(failures))


func workshop_portrait_fits() -> void:
	var overlaps: Array[String] = []
	for picture in app._overlay.find_children("*", "TextureRect", true, false):
		var labels: Array = []
		for label in picture.get_parent().get_children():
			if label is Label and picture.get_global_rect().intersects(label.get_global_rect()):
				overlaps.append(label.text)
			if label is Label and not label.text.is_empty():
				labels.append(label)
		for left in range(labels.size()):
			for right in range(left + 1, labels.size()):
				if labels[left].get_global_rect().intersects(labels[right].get_global_rect()):
					overlaps.append(labels[left].text + " / " + labels[right].text)
	expect(overlaps.is_empty(), "workshop portrait, name and ability explanations do not overlap: " + str(overlaps))


func wait_story() -> bool:
	for _frame in range(180):
		await process_frame
		if app._overlay_kind == "dialogue" and app.story_line != null and not app._story_busy:
			return true
	expect(false, "authored dialogue reaches an actionable line")
	return false


func finish_story() -> bool:
	for _step in range(150):
		await frames()
		if app._overlay_kind != "dialogue":
			return true
		if not await wait_story():
			return false
		var action: String = "dialogue_next" if app.story_line.responses.is_empty() else "dialogue_response_" + str(app.story_line.responses.size() - 1)
		if not await press(action):
			return false
	expect(false, "authored dialogue returns to gameplay within its finite flow")
	return false


func restart_app() -> void:
	app.queue_free()
	await frames(3)
	app = MainScene.instantiate()
	root.add_child(app)
	await frames(4)


func restore_creation_checkpoint(description: String) -> bool:
	var creation: Dictionary = app.run.data.creation.duplicate(true)
	var attributes: Dictionary = app.run.data.attributes.duplicate(true)
	if not await press("save_exit"):
		return false
	expect(app._screen == "title", description + ": save-and-exit returns to title")
	await restart_app()
	if not await press("continue"):
		return false
	expect(app._overlay_kind == "prologue" and is_instance_valid(app.creation_journey), description + ": Continue recreates the prologue component")
	expect(same_saved_value(app.run.data.creation, creation) and same_saved_value(app.run.data.attributes, attributes), description + ": exact page, answers, adjustment and source selection survive restart")
	fit(description + " restored page")
	return true


func new_origin(origin: String) -> bool:
	if not await press("new_game"):
		return false
	fit("origin selection")
	await press("origin_" + origin)
	app.name_entry.text = "卡牌試玩行者"
	if not await press("create"):
		return false
	expect(app.run.data.phase == "prologue" and is_instance_valid(app.creation_journey), origin + ": naming starts the six-question journey")
	expect(app.run.data.hero_name == "卡牌試玩行者" and app.run.data.origin == origin, origin + ": name and background are retained")
	var choices: Array[int] = [2, 1, 0, 2, 1, 0]
	for question in range(6):
		expect(app.run.data.creation.page == "question" and app.run.data.creation.question == question, origin + ": scenario question %d is shown in order" % (question + 1))
		fit(origin + " question " + str(question + 1))
		prologue_body_visible(origin + " question " + str(question + 1))
		if origin == "herbalist":
			await capture("prologue-question-" + str(question + 1))
		if not await press("answer_" + str(choices[question])):
			return false
		expect(app.run.data.creation.page == "aftermath" and int(app.run.data.creation.answers[question]) == choices[question], origin + ": answer %d receives its story response" % (question + 1))
		fit(origin + " answer response " + str(question + 1))
		prologue_body_visible(origin + " answer response " + str(question + 1))
		if question == 2 and origin == "herbalist":
			if not await restore_creation_checkpoint("mid-question aftermath"):
				return false
		if not await press("continue"):
			return false
	expect(app.run.data.creation.page == "summary" and app.run.data.attributes.size() == 6, origin + ": six answers produce the six-attribute explanation")
	expect(app.run.data.spent == 0 and app.run.remaining() == 21, origin + ": scenario decisions use no preparation slots")
	fit(origin + " attribute summary")
	summary_text_fits()
	await capture(origin + "-summary")
	# Reconsider one authored decision through the actual review navigation.
	await press("review")
	expect(app.run.data.creation.page == "review", origin + ": summary offers review of previous answers")
	fit("answer review")
	await press("review_1")
	choices[1] = 2
	await press("answer_2")
	await press("continue")
	expect(app.run.data.creation.page == "summary" and int(app.run.data.creation.answers[1]) == 2, origin + ": revising an answer returns to the updated summary")
	var source: String = ""
	for attribute: String in ["constitution", "strength", "agility", "resolve", "aptitude", "fortune"]:
		var candidate: Button = button_for("move_" + attribute)
		if candidate != null and not candidate.disabled:
			source = attribute
			break
	expect(not source.is_empty(), origin + ": result offers a legal adjustment source")
	if source.is_empty():
		return false
	await press("move_" + source)
	if origin == "courier":
		if not await restore_creation_checkpoint("selected adjustment source"):
			return false
	var destination: String = ""
	for attribute: String in ["fortune", "aptitude", "resolve", "agility", "strength", "constitution"]:
		var candidate: Button = button_for("to_" + attribute)
		if candidate != null and not candidate.disabled:
			destination = attribute
			break
	expect(not destination.is_empty(), origin + ": result offers a legal adjustment destination")
	if destination.is_empty():
		return false
	var before_attributes: Dictionary = app.run.data.attributes.duplicate(true)
	await press("to_" + destination)
	expect(app.run.data.creation.adjustments.size() == 1 and int(app.run.data.attributes[source]) == int(before_attributes[source]) - 1 and int(app.run.data.attributes[destination]) == int(before_attributes[destination]) + 1, origin + ": point transfer visibly changes only the two chosen abilities")
	if origin == "performer":
		if not await restore_creation_checkpoint("completed result adjustment"):
			return false
	var final_creation: Dictionary = app.run.data.creation.duplicate(true)
	if not await press("confirm"):
		return false
	if not await wait_story():
		return false
	expect(app.run.data.phase == "intro" and app.run.data.dialogue.title == "arrival_morning", origin + ": confirming the result enters the authored arrival morning")
	expect(app.run.data.creation.answers == final_creation.answers and app.run.data.creation.adjustments == final_creation.adjustments, origin + ": confirmation retains the chosen background decisions")
	fit("arrival morning dialogue")
	if not await finish_story():
		return false
	expect(app.run.data.phase == "town" and app.current_location == "wangxi" and is_instance_valid(app.world), origin + ": prologue returns control in Wangxi town")
	expect(app.run.data.spent == 0 and app.run.remaining() == 21, origin + ": all seven preparation days remain after the prologue")
	return true


func start_activity(id: String) -> bool:
	if not await press("planner"):
		return false
	if not await press("activity_" + id):
		return false
	fit(id + " activity cost")
	if not await press("confirm_activity"):
		return false
	return await finish_story()


func test_deck_editor() -> void:
	var before: Array = app.run.data.deck.duplicate()
	var spent: int = app.run.data.spent
	if not await press("deck"):
		return
	fit("deck editor")
	workshop_portrait_fits()
	await capture("workshop-initial")
	expect(app._overlay_kind == "deck" and before.size() == 10, "town opens the ten-card editor")
	expect(not text_under(app._overlay).contains("\"id\":"), "character motivation is readable text rather than a serialized object")
	var upgrade: Button = button_for("upgrade_opening_thrust")
	expect(upgrade == null or upgrade.disabled, "unlearned refinement cannot be purchased")
	await press("deck_remove_guard")
	expect(app._deck_draft.size() == 9 and button_for("deck_save").disabled, "nine-card draft cannot be applied")
	expect(app.run.data.deck == before and app.run.data.spent == spent, "incomplete draft does not change the active deck or schedule")
	await press("deck_cancel")
	expect(app.run.data.deck == before, "cancelling leaves the original deck intact")
	await press("deck")
	await press("deck_remove_guard")
	var origin_card: String = "gather_momentum"
	await press("deck_add_" + origin_card)
	expect(app._deck_draft.size() == 10 and not button_for("deck_save").disabled, "learned gathering technique completes a valid ten-card draft")
	fit("scrolled deck library")
	await capture("workshop-scrolled")
	await press("deck_save")
	expect(app._overlay_kind.is_empty() and origin_card in app.run.data.deck and app.run.data.deck.count("guard") == 1, "applying saves the chosen composition and returns to town")
	expect(app.run.data.spent == spent, "legal deck editing costs no activity slots")
	await press("pause")
	await press("save_exit")
	await restart_app()
	await press("continue")
	expect(origin_card in app.run.data.deck and app.run.data.deck.size() == 10, "new scene instance restores the saved deck")


func select_hand(index: int) -> bool:
	var desired_page: int = index / 5
	while int(app.arena.view_state().page) != desired_page:
		if not await press("hand_next" if int(app.arena.view_state().page) < desired_page else "hand_previous"):
			return false
	return await press("card_" + str(index))


func restore_battle_checkpoint(lab: bool, description: String) -> bool:
	await press("pause")
	var frozen: Dictionary = app.arena.snapshot().duplicate(true)
	var spent: int = app.run.data.spent
	await press("save_exit")
	await restart_app()
	await press("lab_continue" if lab else "continue")
	expect(is_instance_valid(app.arena) and same_saved_value(app.arena.snapshot(), frozen), description + ": exact model and UI choices survive an app restart")
	if app.run.data.is_empty():
		var diagnosis: Dictionary = Run.new().load_game(Run.LAB_SAVE_PATH if lab else Run.SAVE_PATH)
		expect(false, description + ": load rejected: " + str(diagnosis))
		return false
	expect(app.run.data.spent == spent, description + ": restore does not charge a slot")
	return is_instance_valid(app.arena)


func battle_step() -> bool:
	var state: Dictionary = app.arena.battle.status()
	if state.phase == "mulligan":
		return await press("mulligan_skip")
	if state.resolved:
		return false
	if state.phase == "choice":
		battle_coverage.cycle = true
		if state.hand.size() > 0:
			await select_hand(0)
		if _checkpoint_cycle and not battle_coverage.lab_choice_restore:
			fit("cycle selection")
			await capture("lab-cycle-selected")
			var before_count: int = int(state.cards_played)
			if not await restore_battle_checkpoint(true, "mid-cycle selection"):
				return false
			battle_coverage.lab_choice_restore = true
			await capture("lab-cycle-resumed")
			await press("cycle_confirm")
			var after: Dictionary = app.arena.battle.status()
			expect(after.phase == "player" and after.get("in_play", []).is_empty() and after.get("pending_choice", {}).is_empty(), "restored cycle resolves its reserved card exactly once")
			expect(int(after.cards_played) == before_count, "resolving a saved cycle does not count a second card play")
			return true
		return await press("cycle_confirm" if state.hand.size() > 0 else "cycle_skip")
	if state.get("can_use_medicine", false) and state.hp <= state.max_hp - 20:
		return await press("medicine")
	var target: int = -1
	var incoming: int = 0
	for index in range(state.enemies.size()):
		var enemy: Dictionary = state.enemies[index]
		if int(enemy.hp) <= 0:
			continue
		if target < 0 or enemy.hp < state.enemies[target].hp:
			target = index
		incoming += int(enemy.intent.get("display_damage", enemy.intent.get("damage", 0))) * int(enemy.intent.get("hits", 1))
	var choice: int = -1
	var boosted: bool = false
	var best: float = 0.05
	for index in range(state.hand.size()):
		var id: String = str(state.hand[index])
		for empowered: bool in [false, true]:
			var card: Dictionary = Cards.card(id, state.stats.get("refinements", {}).get(id, ""), empowered)
			if empowered and int(card.get("boost_cost", 0)) == 0:
				continue
			var preview: Dictionary = app.arena.battle.preview_card(index, target, empowered)
			if not bool(preview.get("can_play", false)):
				continue
			var damage: float = 0.0
			for hit in preview.get("damage", []):
				damage += float(hit.get("hp_loss", hit.get("amount", 0)))
			var score: float = damage * 3.0
			var missing_block: int = maxi(0, incoming - int(state.block))
			score += mini(int(preview.get("block", card.get("block", 0))), missing_block) * 4.0
			if card.has("delayed_damage"):
				score += int(card.delayed_damage) * 2.5
			if int(card.get("retaliation", 0)) > 0 and incoming > 0 and int(state.get("retaliation", 0)) == 0:
				score += int(card.retaliation) * 3.5
			if card.has("energy"):
				score += 45.0 if state.hand.size() > 1 else 1.0
			if card.has("draw") and int(state.qi) > int(card.cost):
				score += int(card.draw) * 7.0
			if card.has("cycle_limit") and state.hand.size() > 1:
				score += 6.0
			if card.has("momentum_gain") and int(state.get("momentum", 0)) < 3 and int(state.get("momentum_gained", 0)) < 2:
				score += 12.0
			if card.has("strip_block") and target >= 0:
				score += mini(int(card.strip_block), int(state.enemies[target].block)) * 2.0
			if empowered:
				score -= int(card.get("momentum_cost", 0)) * 2.0
			# Saved qi is a deliberate resource choice for Guiyuan, not a forced
			# attempt to spend every last point on an ineffective card.
			if state.stats.get("inner", "") == "guiyuan" and int(state.qi) == int(card.cost) and int(state.get("momentum", 0)) < 3 and score < 15.0:
				score -= 12.0
			if score > best:
				best = score
				choice = index
				boosted = empowered
	if choice < 0:
		if state.hand.size() > 0:
			var retain: int = 0
			for index in range(state.hand.size()):
				if state.hand[index] == "sword_qi" or (not battle_coverage.cycle and state.hand[index] == "cloud_step"):
					retain = index
					break
			await select_hand(retain)
			if int(app.arena.view_state().get("retained_index", -1)) != retain:
				await press("retain_selected")
			battle_coverage.retain = int(app.arena.view_state().get("retained_index", -1)) == retain
		return await press("end_turn")
	if not await select_hand(choice):
		return false
	var card: Dictionary = Cards.card(str(state.hand[choice]), state.stats.get("refinements", {}).get(str(state.hand[choice]), ""), boosted)
	if card.target == "enemy":
		await press("target_" + str(target))
	var before_cards: int = int(state.cards_played)
	if not battle_coverage["boost" if boosted else "normal"]:
		await capture("lab-boost-selected" if boosted else "lab-normal-selected")
	if not await press("play_boost" if boosted else "play_normal"):
		return false
	if is_instance_valid(app.arena) and int(app.arena.battle.status().cards_played) > before_cards:
		battle_coverage["boost" if boosted else "normal"] = true
	return true


func win_visible_battle() -> bool:
	for _action in range(180):
		if not is_instance_valid(app.arena):
			break
		var state: Dictionary = app.arena.battle.status()
		if state.resolved:
			expect(state.won and state.cards_played > 0, "legal card and end-turn inputs defeat the practice opponent")
			await create_timer(0.35).timeout
			await frames()
			break
		if not await battle_step():
			return false
	if app._overlay_kind == "dialogue":
		if not await finish_story():
			return false
	var completed: bool = app.run.data.pending.is_empty() and app.run.data.phase == "town" and is_instance_valid(app.world)
	expect(completed, "card victory and authored debrief settle once and return to town")
	return completed


func test_card_battle_flow() -> void:
	var before: int = app.run.data.spent
	if not await start_activity("sword_lesson"):
		return
	expect(app.run.data.spent == before + 2 and app.run.data.training == 2 and "sword_qi" in app.run.data.learned_cards, "completed lesson consumes two slots and unlocks its card")
	var deck: Array = app.run.data.deck.duplicate()
	if not await start_activity("practice"):
		return
	expect(is_instance_valid(app.arena) and app.run.data.pending.stage == "combat", "practice briefing creates the actual card battlefield")
	if not is_instance_valid(app.arena):
		return
	fit("card battle initial hand")
	await capture("practice-mulligan")
	var initial: Dictionary = app.arena.battle.status()
	expect(initial.hand.size() == 5 and int(initial.qi) == 3 and initial.phase == "mulligan", "opening shows five drawn cards, three energy and one opening adjustment")
	expect(app.run.data.pending.deck == deck and initial.stats.deck == deck, "encounter uses the deck applied before departure")
	var locked: Dictionary = app.run.data.pending.duplicate(true)
	expect(not app.run.set_deck(Cards.starting_deck()).ok and not app.run.upgrade_card("opening_thrust").ok and app.run.data.pending == locked, "active encounter locks deck and upgrades without changing its snapshot")
	await press("card_0")
	expect(app.arena.mulligan_selection == [0], "opening card click selects a replacement without playing it")
	await press("pause")
	fit("card battle pause")
	var frozen: Dictionary = app.arena.snapshot().duplicate(true)
	var all_disabled: bool = true
	for button in app.arena.action_buttons.values():
		all_disabled = all_disabled and button.disabled
	expect(all_disabled, "pause disables every card encounter control")
	app.arena.end_turn()
	app.arena.select_card(0)
	await frames(5)
	expect(app.arena.snapshot() == frozen, "paused public inputs cannot change hand, choice, turn, energy or enemies")
	await press("save_exit")
	await restart_app()
	await press("continue")
	expect(is_instance_valid(app.arena) and same_saved_value(app.arena.snapshot(), frozen), "Continue restores exact hand, piles, RNG, intents and selected mulligan card")
	if app.run.data.is_empty() or not is_instance_valid(app.arena):
		var diagnosis: Dictionary = Run.new().load_game()
		expect(false, "battle Continue failed: " + str(diagnosis))
		return
	expect(app.run.data.spent == before + 3, "battle save and resume do not charge the activity again")
	await press("mulligan_confirm")
	expect(app.arena.battle.status().phase == "player" and app.arena.battle.status().hand.size() == 5, "confirming a legal replacement starts the first player turn")
	await press("rules")
	fit("card rules panel")
	await press("panel_close")
	await press("deck")
	for pile: String in ["draw", "discard", "exhaust", "hand"]:
		await press("pile_" + pile)
		expect(app.arena.view_state().pile_tab == pile, "pile viewer shows " + pile + " without changing the battle")
		fit("card pile " + pile)
	await press("panel_close")
	# An actual enemy turn gives the potion button a meaningful damaged target.
	await press("end_turn")
	expect(app.arena.battle.status().turn == 2 and app.arena.battle.status().hp < initial.hp, "ending the turn resolves the advertised attack and deals the next hand")
	await press("medicine")
	expect(app.arena.battle.status().medicine_used == 1 and app.arena.battle.status().qi == 2, "medicine costs one qi and consumes the once-per-battle allowance")
	expect(button_for("medicine").disabled, "medicine cannot be used again in this battle")
	if not await win_visible_battle():
		return
	expect(app.run.data.spent == before + 3 and app.run.data.training == 3 and app.run.data.mastery == 1, "practice awards one training and one mastery without recharging time")
	var reward_state: Dictionary = app.run.data.duplicate(true)
	await press("pause")
	await press("save_exit")
	await restart_app()
	await press("continue")
	expect(app.run.data.training == reward_state.training and app.run.data.mastery == reward_state.mastery and app.run.data.medicine == reward_state.medicine and app.run.data.spent == reward_state.spent, "restoring a settled win neither repeats rewards nor consumes medicine again")
	if not await start_activity("practice"):
		return
	if not await win_visible_battle():
		return
	var mastery: int = app.run.data.mastery
	var cost: int = app.run.upgrade_status("opening_thrust").cost
	var slots: int = app.run.data.spent
	await press("deck")
	expect(not button_for("upgrade_opening_thrust").disabled, "earned practice mastery enables a real upgrade")
	await press("upgrade_opening_thrust")
	expect("opening_thrust" in app.run.data.upgraded_cards and app.run.data.mastery == mastery - cost and app.run.data.spent == slots, "upgrade consumes its advertised mastery and no schedule slots")
	expect(app.run.data.refinements.get("opening_thrust") == "stable", "purchased refinement starts on the stable branch")
	var paid_mastery: int = app.run.data.mastery
	await press("refine_opening_thrust_specialist")
	expect(app.run.data.refinements.get("opening_thrust") == "specialist" and app.run.data.mastery == paid_mastery and app.run.data.spent == slots, "switching an unlocked refinement is free and persists for the card kind")
	await press("deck_cancel")


func test_exam_presentations() -> void:
	# Eligibility fixtures isolate branch presentation. Production rule tests
	# separately complete both legal preparation routes within twenty-one slots.
	for school: String in ["zhaoling", "duyun", "stay"]:
		app.run.new_run("結局呈現行者", "performer")
		app.run.data.phase = "town"
		app.run.data.spent = 21
		app.run.data.training = 6
		app.run.data.insight = 6
		app.run.data.favor.shen = 2
		app.run.data.favor.lu = 2
		app.run.data.completed = ["missing_letter", "ridge_tracks", "herb_errand"]
		for activity: String in app.run.data.completed:
			for card_id: String in Cards.cards_for_activity(activity):
				if card_id not in app.run.data.learned_cards:
					app.run.data.learned_cards.append(card_id)
			for inner_id: String in Cards.inners_for_activity(activity):
				if inner_id not in app.run.data.learned_inners:
					app.run.data.learned_inners.append(inner_id)
		var saved: Dictionary = app.run.save_game()
		expect(saved.ok, "ending fixture passes the production save validator: " + str(saved.message))
		if not saved.ok:
			return
		app._show_title()
		await press("continue")
		await press("exam")
		fit("exam confirmation")
		await press("exam_confirm")
		if not await finish_story():
			return
		expect(is_instance_valid(app.arena) and app.arena.mode == "exam", "exam introduction opens the real card examiner encounter")
		await press("retreat")
		await press("retreat")
		expect(app._overlay_kind == "results" and not app.run.data.exam_result.won and app.run.data.exam_result.eligible.size() == 2, "concession evaluates both previously earned invitations")
		fit("school invitation choices")
		await press("school_" + school)
		if not await finish_story():
			return
		expect(app.run.data.school == school and app.run.data.phase == "ending" and button_for("new_game") != null, school + " ending offers a new journey")
		fit("ending")
	app.run.new_run("初學行者", "herbalist")
	app.run.data.phase = "town"
	app._recover_screen()
	await press("planner")
	await press("exam")
	expect(app.run.data.spent == 0, "previewing an early exam does not silently discard preparation time")
	await press("exam_confirm")
	if not await finish_story():
		return
	await press("retreat")
	await press("retreat")
	expect(app.run.data.spent == 21 and button_for("school_zhaoling").disabled and button_for("school_duyun").disabled and not button_for("school_stay").disabled, "unprepared concession leaves the town ending available")
	await press("school_stay")
	await finish_story()
	expect(app.run.data.school == "stay", "an unsuccessful applicant can finish without forced retries")


func test_lab_workshop() -> void:
	await press("deck")
	fit("trial loadout workshop")
	workshop_portrait_fits()
	await capture("lab-workshop")
	var original: Dictionary = app.run.data.duplicate(true)
	await press("weapon_unarmed")
	expect(button_for("deck_save").disabled and app.run.data.weapon == "sword", "incompatible weapon disables apply without changing the active loadout")
	await press("weapon_sword")
	for inner_id: String in ["shouzhong", "xingyun", "guiyuan"]:
		await press("inner_" + inner_id)
		await capture("lab-workshop-" + inner_id)
	await press("inner_guiyuan")
	await press("deck_save")
	expect(app.run.data.inner == "guiyuan" and app.run.data.weapon == "sword" and app.run.data.deck == original.deck, "weapon, inner and ten cards commit as one loadout")
	await press("deck")
	await press("refine_opening_thrust_specialist")
	expect(app.run.data.refinements.get("opening_thrust", "") == "specialist", "lab can select the costly opening-thrust refinement")
	await press("refine_opening_thrust_none")
	expect(not app.run.data.refinements.has("opening_thrust"), "lab can return an unlocked technique to its unrefined baseline")
	await press("deck_cancel")
	await press("preset_shouzhong")
	expect(app.run.data.inner == "shouzhong" and app.run.data.refinements.is_empty(), "a sample preset resets branch choices to its documented baseline")


func win_lab_battle(label: String) -> bool:
	var observed_win: bool = false
	for _action in range(220):
		if not is_instance_valid(app.arena):
			break
		var state: Dictionary = app.arena.battle.status()
		if state.resolved:
			observed_win = state.won
			expect(state.won and int(state.cards_played) > 0, label + ": legal visible card actions defeat this test opponent")
			await create_timer(0.4).timeout
			await frames(3)
			break
		if not await battle_step():
			return false
	if app._overlay_kind == "trial_result":
		fit(label + " result")
		await capture(label + "-result")
		await press("trial_again")
	expect(app.run.data.mode == "lab" and app.run.data.pending.is_empty() and app.run.data.phase == "town", label + ": completed trial returns to its independent hub")
	expect(app.run.data.spent == 0 and app.run.data.training == 0 and app.run.data.completed.is_empty(), label + ": trials do not create journey time, training or activity rewards")
	return observed_win and app.run.data.pending.is_empty()


func test_lab_flow() -> void:
	app._show_title()
	await frames()
	var journey_file: String = FileAccess.get_file_as_string(Run.SAVE_PATH)
	expect(not journey_file.is_empty(), "formal journey exists before independent trial testing")
	await press("lab_new")
	expect(app.run.data.mode == "lab" and app.run.data.phase == "town" and app.run.data.learned_cards.size() == 12 and app.run.data.learned_inners.size() == 3, "trial entry offers the complete twelve-card verification pool and all three inners")
	fit("trial hub")
	await capture("lab-hub")
	for value in app.run.data.attributes.values():
		expect(int(value) == 5, "trial presets use equal five-point attributes")
	await test_lab_workshop()
	var cases: Array = [["shouzhong", "flurry"], ["xingyun", "armored"], ["guiyuan", "charging"], ["xingyun", "counter"]]
	for pair in cases:
		var preset: String = pair[0]
		var foe: String = pair[1]
		await press("preset_" + preset)
		expect(app.run.data.deck == Cards.PRESETS[preset].deck and app.run.data.inner == preset and app.run.data.weapon == Cards.PRESETS[preset].weapon, "trial preset applies its documented weapon, inner and exact ten cards: " + preset)
		await press("enemy_" + foe)
		await press("trial_start")
		expect(is_instance_valid(app.arena) and app.run.data.pending.id == "trial" and app.arena.mode == foe and app.run.data.pending.cost == 0, "trial starts the requested public-intent opponent without charging time: " + foe)
		if not is_instance_valid(app.arena):
			return
		fit("trial " + foe + " opening")
		await capture("lab-" + foe + "-mulligan")
		await press("mulligan_skip")
		if foe == "flurry":
			var first_hand: Array = app.arena.battle.status().hand.duplicate()
			await select_hand(0)
			await press("retain_selected")
			expect(app.arena.view_state().retained_index == 0, "retention is an explicit marked hand-card selection")
			await capture("lab-retain-selected")
			if not await restore_battle_checkpoint(true, "retained card selection"):
				return
			await press("end_turn")
			var next_hand: Array = app.arena.battle.status().hand
			expect(next_hand.size() == 5 and next_hand[0] == first_hand[0], "end turn preserves the selected card and fills the hand to five")
			battle_coverage.retain = true
		_checkpoint_cycle = preset == "xingyun"
		if not await win_lab_battle("lab-" + preset + "-" + foe):
			return
		_checkpoint_cycle = false
		expect(FileAccess.get_file_as_string(Run.SAVE_PATH) == journey_file, "trial battle and saves leave the formal journey file byte-identical: " + foe)
	for key in battle_coverage:
		expect(bool(battle_coverage[key]), "actual scene controls exercised: " + key)
	# A clean retry/retreat checkpoint exercises the same locked loadout and seed
	# without fabricating a battle outcome or changing a model field.
	await press("preset_guiyuan")
	await press("enemy_charging")
	await press("trial_start")
	var locked: Dictionary = app.run.data.pending.duplicate(true)
	var original_opening: Dictionary = app.arena.snapshot().duplicate(true)
	await press("mulligan_skip")
	# Deliberately pass legal turns until defeated; never assign combat health.
	for _turn in range(20):
		if app.arena.battle.status().resolved:
			break
		await press("end_turn")
	await create_timer(0.5).timeout
	expect(app._overlay_kind == "defeat" and app.run.data.pending.stage == "defeat", "legal inaction reaches the actual defeat and retry screen")
	await press("retry")
	expect(app.arena.battle.status().phase == "mulligan" and app.run.data.spent == 0 and app.run.data.pending.attempt == 1, "retry starts a fresh attempt without spending an activity slot")
	expect(app.run.data.pending.seed == locked.seed and app.run.data.pending.deck == locked.deck and app.run.data.pending.inner == locked.inner, "retry preserves the locked seed, deck and inner")
	expect(same_saved_value(app.arena.snapshot(), original_opening), "same-seed retry restores the same real opening hand, piles and intents")
	await press("retreat")
	await press("retreat")
	expect(app.run.data.pending.is_empty() and app.run.data.spent == 0 and app.run.data.mode == "lab", "trial withdrawal returns to the lab with no formal reward")
	await press("lab_exit")
	await restart_app()
	expect(not button_for("continue").disabled and not button_for("lab_continue").disabled, "title exposes separate formal and trial Continue actions")
	await press("continue")
	expect(app.run.data.mode == "journey" and FileAccess.get_file_as_string(Run.SAVE_PATH) == journey_file, "formal Continue selects the original journey rather than the latest trial")
	app._show_title()
	await press("lab_continue")
	expect(app.run.data.mode == "lab" and app.run.data.pending.is_empty(), "trial Continue independently restores the trial hub")


func _run() -> void:
	if FileAccess.file_exists(Run.SAVE_PATH) or FileAccess.file_exists(Run.SAVE_PATH + ".bak") or FileAccess.file_exists(Run.LAB_SAVE_PATH):
		push_error("Card UI tests require a fresh XDG_DATA_HOME; refusing to replace an existing player save.")
		quit(2)
		return
	root.size = Vector2i(1440, 900)
	root.content_scale_size = Vector2i(1440, 900)
	app = MainScene.instantiate()
	root.add_child(app)
	await frames(4)
	expect(button_for("new_game") != null and button_for("continue").disabled, "fresh title enables a new journey and disables missing Continue")
	fit("title")
	await capture("title")
	await press("help")
	fit("first-time help")
	expect(text_under(app._overlay).contains("六") and text_under(app._overlay).contains("五張"), "title help explains the scenario creation and card loop")
	await press("close")
	for origin: String in ["herbalist", "courier", "performer"]:
		if not await new_origin(origin):
			await _finish()
			return
		await press("pause")
		await press("save_exit")
		expect(app._screen == "title" and not button_for("continue").disabled, origin + ": town save enables Continue")
	await press("continue")
	await test_deck_editor()
	await test_card_battle_flow()
	await test_exam_presentations()
	await test_lab_flow()
	await _finish()


func _finish() -> void:
	if is_instance_valid(app):
		app.queue_free()
		await process_frame
		await create_timer(0.2).timeout
	print("TESTS COMPLETE: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
