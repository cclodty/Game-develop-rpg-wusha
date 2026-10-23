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

	print("TESTS COMPLETE: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
