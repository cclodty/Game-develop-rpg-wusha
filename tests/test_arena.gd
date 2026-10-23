extends SceneTree
## Exercise the live simulation, without advancing any run-state calendar.

const Arena = preload("res://scripts/arena.gd")
var passed: int = 0
var failed: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error("FAIL: " + message)


func _arena(encounter: String = "spar", skills: Array = []) -> WeiyuanArena:
	var arena := Arena.new()
	root.add_child(arena)
	arena.set_process(false)
	# Accelerated manual simulation should not queue dozens of real audio plays.
	arena._sound.stream = null
	arena.configure(encounter, {"training": 4, "insight": 3, "skills": skills, "medicine": 3, "origin": "herbalist", "exam_aid": false})
	_advance(arena, 1.3)
	for enemy in arena.enemies:
		enemy.cooldown = 10.0
	return arena


func _advance(arena: WeiyuanArena, seconds: float, movement: Vector2 = Vector2.ZERO) -> void:
	for frame in range(ceili(seconds / 0.02)):
		arena.step_simulation(0.02, movement)


func _single_target(arena: WeiyuanArena, relative: Vector2 = Vector2(65, 0), kind: String = "bandit") -> Dictionary:
	arena.enemies.clear()
	var enemy: Dictionary = arena._make_enemy(kind, arena.player_position + relative, 100)
	enemy.cooldown = 10.0
	enemy.hp = 500.0
	enemy.max_hp = 500.0
	arena.enemies.append(enemy)
	return enemy


func _run() -> void:
	var arena := _arena()
	_check(arena.max_hp == 128.0 and arena.hp == 128.0, "training increases maximum health")
	_check(arena.status().ready and arena.wave == 1, "start countdown completes through real time")
	var start := arena.player_position
	_advance(arena, 0.4, Vector2.RIGHT)
	_check(arena.player_position.x > start.x + 80.0, "movement advances at real simulation speed")
	_advance(arena, 10.0, Vector2(-1, -1).normalized())
	_check(arena.player_position.x >= 76.0 and arena.player_position.y >= 118.0, "movement remains inside arena bounds")
	arena.free()

	# A sword hit has an actual windup and respects facing, reach and cooldown.
	arena = _arena()
	var enemy := _single_target(arena)
	var initial_hp: float = enemy.hp
	_check(arena.attack(Vector2.RIGHT), "first sword attack is accepted")
	_check(not arena.attack(Vector2.RIGHT), "held attack cannot bypass cooldown")
	_advance(arena, 0.08)
	_check(enemy.hp == initial_hp, "sword does not hit before its active frame")
	_advance(arena, 0.08)
	_check(enemy.hp < initial_hp and arena.successful_hits == 1, "sword active frame damages a nearby facing target once")
	_advance(arena, 0.2)
	_check(arena.attack(Vector2.LEFT) and arena.status().combo == 2, "timely follow-up advances the combo")
	var before_wrong_facing: float = enemy.hp
	_advance(arena, 0.35)
	_check(enemy.hp == before_wrong_facing, "enemy behind the sword arc receives no damage")
	enemy.pos = arena.player_position + Vector2(65, 0)
	_check(arena.attack(Vector2.RIGHT) and arena.status().combo == 3, "third attack completes the combo")
	_advance(arena, 0.16)
	_check(before_wrong_facing - float(enemy.hp) > initial_hp - before_wrong_facing, "third combo strike deals a stronger hit")
	_advance(arena, 1.3)
	_check(arena.attack() and arena.status().combo == 1, "combo resets after its input window")
	arena.free()

	# Enemy aim locks during a generous telegraph, then produces real damage.
	arena = _arena()
	enemy = _single_target(arena)
	enemy.cooldown = 0.0
	arena.step_simulation(0.02)
	_check(enemy.windup >= 0.75 and enemy.attack_dir.x < 0.0, "melee enemy shows and locks its windup")
	var full_hp := arena.hp
	_advance(arena, 0.6)
	_check(arena.hp == full_hp, "telegraph gives time to respond before damage")
	_advance(arena, 0.22)
	_check(arena.hp == full_hp - 9.0, "melee attack resolves after its windup")
	_check(not arena._damage_player(9, Vector2.LEFT), "hurt recovery prevents stacked same-frame damage")
	arena.free()

	arena = _arena()
	enemy = _single_target(arena, Vector2(180, 0), "lancer")
	enemy.cooldown = 0.0
	arena.step_simulation(0.02)
	_check(enemy.attack_kind == "shot" and enemy.windup >= 1.0, "ranged opponent displays a full directional telegraph")
	_advance(arena, 0.8)
	_check(arena.projectiles.is_empty(), "ranged attack cannot launch before its telegraph finishes")
	_advance(arena, 0.24)
	_check(arena.projectiles.size() == 1, "ranged attack launches a travelling sword wave")
	full_hp = arena.hp
	_advance(arena, 0.7)
	_check(arena.hp == full_hp - 9.0, "enemy projectile collision damages the player once")
	arena.free()

	arena = _arena()
	enemy = _single_target(arena, Vector2(45, 0))
	enemy.windup = 0.04
	enemy.windup_total = 0.78
	enemy.attack_dir = Vector2.LEFT
	full_hp = arena.hp
	_check(arena.dodge(Vector2.UP) and arena.stamina == 76.0, "dodge consumes the shown stamina cost")
	_advance(arena, 0.06)
	_check(arena.hp == full_hp and arena.successful_dodges > 0, "dodge invulnerability avoids a resolving attack")
	_check(not arena.dodge(), "dodge cannot be stacked while active")
	_advance(arena, 0.35)
	arena.stamina = 0.0
	_check(not arena.dodge(), "dodge requires stamina")
	_advance(arena, 1.0)
	_check(arena.stamina >= 24.0, "stamina regenerates during active combat")
	arena.free()

	arena = _arena()
	_check(not arena.cast_qi() and not arena.cast_step(), "unlearned skills remain unavailable")
	arena.free()
	arena = _arena("ridge", ["sword_qi", "cloud_step"])
	enemy = _single_target(arena, Vector2(160, 0))
	initial_hp = enemy.hp
	_check(arena.cast_qi(Vector2.RIGHT) and arena.stamina == 78.0, "learned sword qi consumes stamina and launches")
	_check(not arena.cast_qi(), "sword qi cannot bypass its cooldown")
	_advance(arena, 0.4)
	_check(enemy.hp < initial_hp and arena.successful_hits == 1, "travelling sword qi hits a target only once")
	_check(arena.status().sword_qi_cooldown > 3.5, "skill cooldown decreases with simulation time")
	enemy.pos = arena.player_position + Vector2(100, 0)
	initial_hp = enemy.hp
	_check(arena.cast_step(Vector2.RIGHT), "learned cloud step begins a movement attack")
	_advance(arena, 0.34)
	_check(enemy.hp < initial_hp and arena.successful_hits == 2, "cloud step moves through and hits a target only once")
	_check(not arena.cast_step(), "cloud step respects its cooldown")
	arena.free()

	arena = _arena()
	_check(not arena.use_medicine(), "healing at full health does not consume medicine")
	arena.hp = 20.0
	_check(arena.use_medicine() and arena.medicine_used == 1, "medicine consumption is reported locally")
	_check(is_equal_approx(arena.hp, 20.0 + arena.max_hp * 0.45), "medicine restores the advertised proportion")
	_check(not arena.use_medicine() and arena.stats.medicine == 3, "healing cooldown prevents repeated use and leaves persistent inventory untouched")
	_advance(arena, 1.1)
	_check(arena.use_medicine() and arena.hp <= arena.max_hp, "healing caps at maximum health")
	arena.free()

	# Pause suspends all combat time and input, including pending attacks.
	arena = _arena("grove", ["sword_qi"])
	enemy = _single_target(arena)
	arena.attack(Vector2.RIGHT)
	arena.cast_qi(Vector2.RIGHT)
	arena.hp -= 20.0
	arena.set_input_enabled(false)
	var paused_snapshot := JSON.stringify(arena.snapshot())
	_advance(arena, 10.0, Vector2.RIGHT)
	_check(JSON.stringify(arena.snapshot()) == paused_snapshot, "pause preserves position, timers, enemies, projectiles and health")
	_check(not arena.attack() and not arena.dodge() and not arena.cast_qi() and not arena.use_medicine(), "paused action input is rejected")
	_check(not arena._damage_player(9.0, Vector2.LEFT), "paused player cannot receive damage")
	arena.set_input_enabled(true)
	_advance(arena, 0.1)
	_check(JSON.stringify(arena.snapshot()) != paused_snapshot, "unpause resumes the same encounter")
	arena.free()

	# Round-trip through JSON, including a pending enemy attack and qi projectile.
	arena = _arena("ridge", ["sword_qi", "cloud_step"])
	enemy = _single_target(arena)
	enemy.windup = 0.42
	enemy.windup_total = 0.78
	enemy.attack_dir = Vector2.LEFT
	arena.hp = 80.0
	arena.use_medicine()
	arena.cast_qi(Vector2.RIGHT)
	_advance(arena, 0.08)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(arena.snapshot()))
	var resumed := _arena("ridge", ["sword_qi", "cloud_step"])
	resumed.configure("ridge", arena.stats, saved)
	_check(resumed.medicine_used == 1 and resumed.hp == arena.hp, "JSON restore preserves medicine and health")
	_check(resumed.enemies.size() == 1 and is_equal_approx(resumed.enemies[0].windup, enemy.windup), "JSON restore preserves pending telegraph")
	_check(resumed.projectiles.size() == 1 and is_equal_approx(resumed.status().sword_qi_cooldown, arena.status().sword_qi_cooldown), "JSON restore preserves projectile and skill cooldown")
	_advance(arena, 0.5)
	_advance(resumed, 0.5)
	if not is_equal_approx(resumed.hp, arena.hp) or not is_equal_approx(resumed.enemies[0].hp, arena.enemies[0].hp):
		print("Snapshot mismatch: hero %s/%s, enemy %s/%s" % [arena.hp, resumed.hp, arena.enemies[0].hp, resumed.enemies[0].hp])
	_check(is_equal_approx(resumed.hp, arena.hp) and is_equal_approx(resumed.enemies[0].hp, arena.enemies[0].hp), "restored pending attacks resolve to the same damage")
	_check(resumed.player_position.distance_to(arena.player_position) < 0.1, "restored movement and knockback match")
	resumed.configure("ridge", resumed.stats)
	_check(resumed.medicine_used == 0 and resumed.hp == resumed.max_hp and resumed.wave == 1, "fresh retry resets encounter without spending run-state resources")
	resumed.free()
	arena.free()

	arena = _arena()
	var corrupted := arena.snapshot()
	corrupted.version = {"bad": "value"}
	arena.configure("spar", arena.stats, corrupted)
	_check(arena.enemies.size() == 2 and arena.hp == arena.max_hp, "malformed version falls back safely to a fresh encounter")
	corrupted = arena.snapshot()
	corrupted.wave = 2
	corrupted.enemies = []
	arena.configure("spar", arena.stats, corrupted)
	_check(arena.wave == 1 and arena.enemies.size() == 2 and not arena.status().resolved, "incomplete final wave cannot grant a free victory")
	arena.free()

	# Exam has a distinct boss phase and a complete result is emitted only once.
	arena = _arena("exam")
	enemy = _single_target(arena, Vector2(130, 0), "boss")
	enemy.hp = enemy.max_hp * 0.49
	arena.step_simulation(0.02)
	_check(enemy.phase == 2 and enemy.recovery >= 1.5, "exam boss visibly pauses before its second phase")
	initial_hp = enemy.hp
	arena._hit_enemy(enemy, 20.0, Vector2.ZERO)
	_check(enemy.hp == initial_hp - 20.0, "boss recovery opening receives full damage")
	enemy.recovery = 0.0
	initial_hp = enemy.hp
	arena._hit_enemy(enemy, 20.0, Vector2.ZERO)
	_check(enemy.hp == initial_hp - 12.0, "visible boss defensive stance reduces damage between openings")
	enemy.cooldown = 0.0
	enemy.attack_counter = 1
	arena.step_simulation(0.02)
	_check(enemy.attack_kind == "rush" and enemy.windup > 1.0, "second phase adds a clearly telegraphed rush")
	var outcomes: Array = []
	arena.finished.connect(func(won: bool, report: Dictionary) -> void: outcomes.append({"won": won, "report": report}))
	arena._damage_player(999.0, Vector2.LEFT)
	_advance(arena, 5.0)
	arena._settle(false)
	_check(outcomes.size() == 1 and not outcomes[0].won, "defeat emits exactly one result")
	_check(outcomes[0].report.has("medicine_used") and outcomes[0].report.mode == "exam", "result carries settlement data for the owning run controller")
	arena.free()

	arena = _arena("practice")
	outcomes = []
	arena.finished.connect(func(won: bool, report: Dictionary) -> void: outcomes.append({"won": won, "report": report}))
	for stage in range(3):
		enemy = _single_target(arena)
		enemy.hp = 1.0
		arena.attack(Vector2.RIGHT)
		_advance(arena, 0.2)
		if stage < 2:
			_check(not arena.status().resolved, "early wave does not resolve the entire encounter")
			_advance(arena, 1.9)
	_advance(arena, 3.0)
	_check(arena.wave == 3 and outcomes.size() == 1 and outcomes[0].won, "all waves must be defeated for one victory result")
	var resolved_save := arena.snapshot()
	var restored_outcomes: Array = []
	resumed = _arena("practice")
	resumed.finished.connect(func(won: bool, report: Dictionary) -> void: restored_outcomes.append({"won": won, "report": report}))
	resumed.configure("practice", arena.stats, resolved_save)
	await process_frame
	resumed._emit_restored_result(resumed._generation)
	_check(restored_outcomes.size() == 1 and restored_outcomes[0].won, "restoring an already resolved encounter emits its result only once")
	# A stale deferred callback must not settle a newly configured retry.
	resumed.configure("practice", arena.stats, resolved_save)
	resumed.configure("practice", arena.stats)
	await process_frame
	_check(restored_outcomes.size() == 1 and not resumed.status().resolved, "stale restored-result callback cannot finish a fresh retry")
	resumed.free()
	arena.free()

	await _test_frame_animation()
	print("TESTS COMPLETE: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)


func _test_frame_animation() -> void:
	var arena := _arena()
	_check(arena.player_animation().clip == "idle", "stationary hero selects a real idle clip")
	arena.step_simulation(0.02, Vector2.RIGHT)
	_check(arena.player_animation().clip == "walk", "actual movement selects the walk clip")
	var walk_frame: int = arena.player_animation().frame
	_advance(arena, 0.12, Vector2.RIGHT)
	_check(arena.player_animation().frame != walk_frame, "walking advances to another separately drawn frame")
	var frozen_animation := JSON.stringify(arena.player_animation())
	arena.set_input_enabled(false)
	_advance(arena, 1.0)
	_check(JSON.stringify(arena.player_animation()) == frozen_animation, "pause freezes the exact walk frame rather than changing to idle")
	arena.set_input_enabled(true)
	arena.free()

	arena = _arena()
	var enemy := _single_target(arena)
	var initial_hp: float = enemy.hp
	arena.attack(Vector2.RIGHT)
	_check(arena.player_animation().clip == "attack" and arena.player_animation().frame == 0, "sword begins with anticipation frame zero")
	_advance(arena, 0.10)
	_check(arena.player_animation().frame == 1 and enemy.hp == initial_hp, "attack first two frames precede the hit at 0.11 seconds")
	arena.step_simulation(0.01)
	_check(arena.player_animation().frame == 2 and enemy.hp < initial_hp, "attack contact frame two and actual damage coincide at 0.11 seconds")
	_check(arena._animation.call("frame_index", "attack", arena.player_animation().progress) == arena.player_animation().frame, "arena contact sample selects bank frame two")
	var hero_frame := arena._frame_texture("courier", arena.player_animation()) as AtlasTexture
	_check(hero_frame != null and hero_frame.atlas.resource_path == "res://assets/generated/animation/courier.png", "arena hero draws the actual attack atlas instead of a tilted portrait")
	var foe_frame := arena._frame_texture("bandit", arena.enemy_animation(enemy)) as AtlasTexture
	_check(foe_frame != null and foe_frame.atlas.resource_path == "res://assets/generated/animation/bandit.png", "enemy hurt renders the actual animation atlas")
	var pending_attack: Dictionary = JSON.parse_string(JSON.stringify(arena.snapshot()))
	var resumed := _arena()
	resumed.configure("spar", arena.stats, pending_attack)
	_check(JSON.stringify(resumed.player_animation()) == JSON.stringify(arena.player_animation()), "mid-sword save restores the exact clip and frame")
	_advance(arena, 0.18)
	_advance(resumed, 0.18)
	_check(arena.player_animation().frame == 5 and resumed.player_animation().frame == 5, "sword recovery reaches its last drawn frame after resume")
	arena.free()
	resumed.free()

	arena = _arena("ridge", ["sword_qi", "cloud_step"])
	arena.cast_qi(Vector2.RIGHT)
	_check(arena.player_animation().clip == "attack" and arena.player_animation().frame == 2, "instant sword qi starts its attack clip at projectile release")
	arena.cast_step(Vector2.RIGHT)
	_check(arena.player_animation().clip == "dodge" and arena.player_animation().frame == 0, "cloud step uses the dodge pose sequence")
	_advance(arena, 0.16)
	_check(arena.player_animation().frame >= 2, "cloud step advances drawn dodge poses")
	arena.free()

	arena = _arena()
	arena.dodge(Vector2.UP)
	var dodge_frames: Dictionary = {int(arena.player_animation().frame): true}
	for frame in range(12):
		arena.step_simulation(0.02)
		dodge_frames[int(arena.player_animation().frame)] = true
	_check(arena.player_animation().clip == "dodge" and dodge_frames.size() == 6, "ordinary dodge presents all six frames during its unchanged 0.25 seconds")
	arena.free()

	arena = _arena()
	arena._damage_player(9.0, Vector2.LEFT)
	_check(arena.player_animation().clip == "hurt" and arena.player_animation().frame == 0, "damage starts a genuine player hurt pose")
	_advance(arena, 0.18)
	_check(arena.player_animation().clip == "hurt" and arena.player_animation().frame >= 4, "hurt remains visible and advances beyond its first frame")
	var hurt_save := arena.snapshot()
	resumed = _arena()
	resumed.configure("spar", arena.stats, JSON.parse_string(JSON.stringify(hurt_save)))
	_check(JSON.stringify(resumed.player_animation()) == JSON.stringify(arena.player_animation()), "player hurt clock survives JSON round-trip")
	_advance(arena, 0.1)
	_check(arena.player_animation().clip == "idle", "hurt finishes without changing combat recovery or damage")
	resumed.free()
	arena.free()

	arena = _arena()
	enemy = _single_target(arena)
	enemy.cooldown = 0.0
	arena.step_simulation(0.02)
	_check(arena.enemy_animation(enemy).clip == "attack" and arena.enemy_animation(enemy).frame == 0, "enemy windup begins on attack frame zero")
	_advance(arena, 0.4)
	_check(arena.enemy_animation(enemy).frame == 1 and enemy.windup > 0.0, "enemy anticipation uses only the first two frames")
	_advance(arena, 0.4)
	_check(arena.enemy_animation(enemy).frame == 2 and arena.hp < arena.max_hp, "enemy contact damage visibly selects strike frame two")
	var enemy_contact := arena.snapshot()
	resumed = _arena()
	resumed.configure("spar", arena.stats, JSON.parse_string(JSON.stringify(enemy_contact)))
	_check(JSON.stringify(resumed.enemy_animation(resumed.enemies[0])) == JSON.stringify(arena.enemy_animation(enemy)), "enemy strike presentation restores without firing a second attack")
	_advance(arena, 0.06)
	_check(arena.enemy_animation(enemy).frame == 2, "enemy strike frame is held long enough to see")
	_advance(arena, 0.08)
	_check(arena.enemy_animation(enemy).frame == 3, "enemy recovery starts on fourth drawn attack frame")
	_advance(arena, 0.42)
	_check(arena.enemy_animation(enemy).frame == 5, "enemy recovery continues through the final three frames")
	resumed.free()
	arena.free()

	arena = _arena()
	enemy = _single_target(arena)
	arena._hit_enemy(enemy, 10, Vector2.ZERO)
	_check(arena.enemy_animation(enemy).clip == "hurt", "enemy hit feedback includes a distinct hurt clip")
	_advance(arena, 0.18)
	_check(arena.enemy_animation(enemy).clip == "hurt" and arena.enemy_animation(enemy).frame >= 4, "enemy hurt animation remains visible after its gameplay stun ends")
	var legacy := arena.snapshot()
	legacy.erase("visual")
	legacy.erase("settlement_remaining")
	for entry in legacy.enemies:
		for key in ["moving", "hurt_timer", "strike_timer", "recovery_total", "attack_visual"]:
			entry.erase(key)
	resumed = _arena()
	resumed.configure("spar", arena.stats, legacy)
	_check(is_finite(resumed.player_animation().progress) and is_finite(resumed.enemy_animation(resumed.enemies[0]).progress), "legacy combat saves default missing animation clocks safely")
	_check(resumed.hp == arena.hp and resumed.enemies[0].hp == enemy.hp, "legacy animation defaults do not reset encounter health")
	resumed.free()
	arena.free()

	# A defeated foe becomes only a visual copy, never another damage target.
	arena = _arena()
	enemy = _single_target(arena)
	arena.enemies.append(arena._make_enemy("lancer", Vector2(950, 500), 101))
	enemy.hp = 1.0
	arena._hit_enemy(enemy, 10, Vector2.ZERO)
	_advance(arena, 0.30)
	_check(arena._corpses.size() == 1 and arena.enemies.size() == 1 and not arena.status().resolved, "defeated enemy plays a visual-only copy while other foes continue")
	_check(arena._clip_state("defeat", arena._corpses[0].age / arena.DEFEAT_DURATION).frame == 2, "enemy defeat sequence advances through separate frames")
	var corpse_save: Dictionary = JSON.parse_string(JSON.stringify(arena.snapshot()))
	resumed = _arena()
	resumed.configure("spar", arena.stats, corpse_save)
	_check(is_equal_approx(resumed._corpses[0].age, arena._corpses[0].age), "defeat visual position and phase survive saving")
	_advance(arena, 0.8)
	_check(arena._corpses.is_empty() and arena.successful_hits == 1, "defeat copy expires without becoming a target or granting another hit")
	resumed.free()
	arena.free()

	# Final player defeat gets a short presentation phase with all combat frozen.
	arena = _arena()
	var outcomes: Array = []
	arena.finished.connect(func(won: bool, report: Dictionary) -> void: outcomes.append({"won": won, "report": report}))
	arena._damage_player(999.0, Vector2.LEFT)
	_check(arena.status().resolved and outcomes.is_empty() and arena.player_animation().frame == 0, "defeat resolves gameplay immediately but starts the visible death sequence")
	var stopped_position := arena.player_position
	var stopped_elapsed := arena.elapsed
	var stopped_enemies := JSON.stringify(arena.snapshot().enemies)
	_advance(arena, 0.30, Vector2.RIGHT)
	_check(arena.player_animation().clip == "defeat" and arena.player_animation().frame == 2 and outcomes.is_empty(), "player defeat plays intermediate frames before result UI")
	_check(arena.player_position == stopped_position and arena.elapsed == stopped_elapsed and JSON.stringify(arena.snapshot().enemies) == stopped_enemies, "settled presentation cannot advance AI, movement or combat time")
	_check(not arena.attack() and not arena.dodge() and not arena.use_medicine(), "settled presentation cannot accept combat actions")
	arena.set_input_enabled(false)
	var frozen_defeat := JSON.stringify(arena.snapshot())
	_advance(arena, 2.0)
	_check(JSON.stringify(arena.snapshot()) == frozen_defeat and outcomes.is_empty(), "pause freezes defeat presentation and delays the result callback")
	var defeat_save: Dictionary = JSON.parse_string(frozen_defeat)
	var resumed_outcomes: Array = []
	resumed = _arena()
	resumed.finished.connect(func(won: bool, report: Dictionary) -> void: resumed_outcomes.append({"won": won, "report": report}))
	resumed.configure("spar", arena.stats, defeat_save)
	resumed._emit_restored_result(resumed._generation)
	_check(resumed_outcomes.is_empty() and resumed.player_animation().frame == 2, "resuming mid-defeat retains phase and cannot dispatch prematurely")
	_advance(resumed, 0.32)
	_check(resumed_outcomes.is_empty() and resumed.player_animation().frame == 5, "last defeat frame is shown before settlement completes")
	_advance(resumed, 0.1)
	_advance(resumed, 1.0)
	_check(resumed_outcomes.size() == 1 and not resumed_outcomes[0].won and resumed.player_animation().frame == 5, "resumed defeat finishes exactly once after its remaining visual time")
	resumed.free()
	# Old saves already marked resolved retain their previous immediate dispatch.
	defeat_save.erase("settlement_remaining")
	defeat_save.erase("visual")
	resumed_outcomes = []
	resumed = _arena()
	resumed.finished.connect(func(won: bool, report: Dictionary) -> void: resumed_outcomes.append({"won": won, "report": report}))
	resumed.configure("spar", arena.stats, defeat_save)
	await process_frame
	_check(resumed_outcomes.size() == 1 and resumed.player_animation().frame == 5, "legacy resolved saves dispatch once without replaying or charging a fight")
	resumed.free()
	arena.free()

	arena = _arena("practice")
	outcomes = []
	arena.finished.connect(func(won: bool, report: Dictionary) -> void: outcomes.append({"won": won, "report": report}))
	arena.wave = arena._waves.size()
	enemy = _single_target(arena)
	enemy.hp = 1.0
	arena.attack(Vector2.RIGHT)
	_advance(arena, 0.12)
	_check(arena.status().resolved and outcomes.is_empty() and arena._corpses.size() == 1, "final enemy defeat remains visible before victory UI")
	_advance(arena, 0.30)
	_check(outcomes.is_empty() and arena._corpses[0].age >= 0.29, "last enemy plays its defeat frames instead of disappearing immediately")
	_check(arena.player_animation().clip == "idle" and arena._attack_timer > 0.0, "winning pose finishes visually while settled gameplay attack timer stays frozen")
	var victory_save: Dictionary = JSON.parse_string(JSON.stringify(arena.snapshot()))
	resumed_outcomes = []
	resumed = _arena("practice")
	resumed.finished.connect(func(won: bool, report: Dictionary) -> void: resumed_outcomes.append({"won": won, "report": report}))
	resumed.configure("practice", arena.stats, victory_save)
	_check(resumed_outcomes.is_empty() and resumed._corpses.size() == 1 and is_equal_approx(resumed._corpses[0].age, arena._corpses[0].age), "mid-victory reload preserves final enemy pose and unfinished presentation")
	_advance(arena, 0.4)
	arena._settle(true)
	_check(outcomes.size() == 1 and outcomes[0].won and arena.successful_hits == 1, "victory dispatches exactly once after defeat presentation with unchanged hit totals")
	_advance(resumed, 0.4)
	_check(resumed_outcomes.size() == 1 and resumed_outcomes[0].won and resumed_outcomes[0].report.hits == 1, "resumed victory presents then settles once with its original report")
	resumed.free()
	arena.free()
