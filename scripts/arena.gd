class_name WeiyuanArena
extends Node2D
## Real-time encounters. The run controller owns the calendar and all rewards.

signal finished(won: bool, report: Dictionary)
signal status_changed(value: Dictionary)

const SIZE := Vector2(1080, 640)
const FIELD := Rect2(58, 100, 964, 466)
const PAPER := Color("f7eed9")
const INK := Color("263d3b")
const JADE := Color("478d7e")
const GOLD := Color("d8ad56")
const RED := Color("bd6153")
const HURT_DURATION := 0.24
const DEFEAT_DURATION := 0.65
const STRIKE_DURATION := 0.12

var mode: String = "practice"
var stats: Dictionary = {}
var player_position := Vector2(300, 370)
var facing := Vector2.RIGHT
var hp: float = 100.0
var max_hp: float = 100.0
var stamina: float = 100.0
var max_stamina: float = 100.0
var enemies: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []
var wave: int = 0
var medicine_used: int = 0
var successful_hits: int = 0
var successful_dodges: int = 0
var damage_taken: int = 0
var elapsed: float = 0.0

var _configured: bool = false
var _input_enabled: bool = true
var _block_held_attack: bool = false
var _resolved: bool = false
var _won: bool = false
var _result_emitted: bool = false
var _generation: int = 0
var _settlement_remaining: float = 0.0
var _cooldown: float = 0.0
var _attack_timer: float = 0.0
var _attack_style: String = "sword"
var _attack_direction := Vector2.RIGHT
var _attack_impacted: bool = false
var _combo: int = 0
var _combo_window: float = 0.0
var _dodge_timer: float = 0.0
var _dodge_direction := Vector2.RIGHT
var _invulnerability: float = 0.0
var _flash: float = 0.0
var _hurt_timer: float = 0.0
var _heal_cooldown: float = 0.0
var _qi_cooldown: float = 0.0
var _step_cooldown: float = 0.0
var _step_timer: float = 0.0
var _step_hit_ids: Array[int] = []
var _last_movement := Vector2.RIGHT
var _moving: bool = false
var _status_timer: float = 0.0
var _start_delay: float = 1.2
var _wave_delay: float = 0.0
var _next_enemy_id: int = 1
var _waves: Array = []
var _effects: Array[Dictionary] = []
var _floating: Array[Dictionary] = []
var _ghosts: Array[Dictionary] = []
var _corpses: Array[Dictionary] = []
var _ghost_timer: float = 0.0
var _banner: String = ""
var _banner_timer: float = 0.0
var _font: Font
var _art: Script
var _animation: Script
var _textures: Dictionary = {}
var _sound: AudioStreamPlayer


func _ready() -> void:
	_font = load("res://assets/fonts/JianghuSans.otf") as Font
	if ResourceLoader.exists("res://scripts/art.gd"):
		_art = load("res://scripts/art.gd") as Script
	if ResourceLoader.exists("res://scripts/animation_bank.gd"):
		_animation = load("res://scripts/animation_bank.gd") as Script
	_sound = AudioStreamPlayer.new()
	_sound.volume_db = -22.0
	if ResourceLoader.exists("res://assets/audio/tap.wav"):
		_sound.stream = load("res://assets/audio/tap.wav")
	add_child(_sound)
	queue_redraw()


func _exit_tree() -> void:
	if is_instance_valid(_sound):
		_sound.stop()


func configure(encounter_mode: String, hero_stats: Dictionary, restore: Dictionary = {}) -> void:
	_generation += 1
	mode = encounter_mode if encounter_mode in ["practice", "spar", "grove", "ridge", "exam"] else "practice"
	stats = hero_stats.duplicate(true)
	stats["training"] = clampi(int(stats.get("training", 0)), 0, 40)
	stats["insight"] = clampi(int(stats.get("insight", 0)), 0, 40)
	stats["medicine"] = clampi(int(stats.get("medicine", 0)), 0, 99)
	if not stats.get("skills", []) is Array:
		stats["skills"] = []
	max_hp = 108.0 + float(stats.training) * 5.0
	if bool(stats.get("exam_aid", false)) and mode == "exam":
		max_hp += 25.0
	hp = max_hp
	stamina = max_stamina
	player_position = Vector2(260, 370)
	facing = Vector2.RIGHT
	_last_movement = Vector2.RIGHT
	enemies.clear()
	projectiles.clear()
	_effects.clear()
	_floating.clear()
	_ghosts.clear()
	_corpses.clear()
	_step_hit_ids.clear()
	medicine_used = 0
	successful_hits = 0
	successful_dodges = 0
	damage_taken = 0
	elapsed = 0.0
	wave = 0
	_next_enemy_id = 1
	_cooldown = 0.0
	_attack_timer = 0.0
	_attack_style = "sword"
	_attack_impacted = false
	_combo = 0
	_combo_window = 0.0
	_dodge_timer = 0.0
	_invulnerability = 0.0
	_flash = 0.0
	_hurt_timer = 0.0
	_heal_cooldown = 0.0
	_qi_cooldown = 0.0
	_step_cooldown = 0.0
	_step_timer = 0.0
	_start_delay = 1.2
	_wave_delay = 0.0
	_resolved = false
	_won = false
	_result_emitted = false
	_settlement_remaining = 0.0
	_moving = false
	_waves = _wave_plan()
	_banner = "起手有聲，出劍有度"
	_banner_timer = 2.2
	_spawn_wave()
	_configured = true
	if not restore.is_empty():
		_restore(restore)
	_emit_status()
	queue_redraw()
	if _resolved and _settlement_remaining <= 0.0:
		call_deferred("_emit_restored_result", _generation)


func set_input_enabled(value: bool) -> void:
	_input_enabled = value
	if value:
		_block_held_attack = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_physical_key_pressed(KEY_J)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not _configured or not _input_enabled or _resolved or _start_delay > 0.0:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE:
				dodge()
				get_viewport().set_input_as_handled()
			KEY_Q:
				cast_qi()
				get_viewport().set_input_as_handled()
			KEY_E:
				cast_step()
				get_viewport().set_input_as_handled()
			KEY_R:
				use_medicine()
				get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _configured or not _input_enabled:
		return
	if _resolved:
		step_simulation(delta)
		return
	var movement := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	).normalized()
	var local_mouse := get_local_mouse_position()
	if Rect2(Vector2.ZERO, SIZE).has_point(local_mouse) and local_mouse.distance_to(player_position) > 12.0:
		facing = player_position.direction_to(local_mouse)
	elif movement.length_squared() > 0.0:
		facing = movement
	var attack_held := Input.is_physical_key_pressed(KEY_J) or (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Rect2(Vector2.ZERO, SIZE).has_point(local_mouse))
	if not attack_held:
		_block_held_attack = false
	if attack_held and not _block_held_attack:
		attack()
	step_simulation(minf(delta, 0.05), movement)


## Explicit input lets deterministic tests exercise the same simulation as play.
func step_simulation(delta: float, movement: Vector2 = Vector2.ZERO) -> void:
	if not _configured or not _input_enabled or delta <= 0.0:
		return
	delta = minf(delta, 0.05)
	if _resolved:
		# A settled fight cannot change gameplay again. Only its final defeat
		# frames advance before the owner opens the result UI.
		if _settlement_remaining > 0.0:
			_settlement_remaining = maxf(0.0, _settlement_remaining - delta)
			_update_effects(delta)
			queue_redraw()
		if _settlement_remaining <= 0.0 and not _result_emitted:
			_emit_restored_result(_generation)
		return
	elapsed += delta
	_update_effects(delta)
	_status_timer -= delta
	if _status_timer <= 0.0:
		_status_timer = 0.12
		_emit_status()
	if _start_delay > 0.0:
		_start_delay = maxf(0.0, _start_delay - delta)
		queue_redraw()
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	_combo_window = maxf(0.0, _combo_window - delta)
	_heal_cooldown = maxf(0.0, _heal_cooldown - delta)
	_qi_cooldown = maxf(0.0, _qi_cooldown - delta)
	_step_cooldown = maxf(0.0, _step_cooldown - delta)
	_invulnerability = maxf(0.0, _invulnerability - delta)
	_flash = maxf(0.0, _flash - delta)
	_hurt_timer = maxf(0.0, _hurt_timer - delta)
	stamina = minf(max_stamina, stamina + delta * 25.0)
	_moving = movement.length_squared() > 0.01
	if _moving:
		_last_movement = movement.normalized()
	if _step_timer > 0.0:
		_step_timer = maxf(0.0, _step_timer - delta)
		player_position += _dodge_direction * 710.0 * delta
		for enemy in enemies:
			if int(enemy.id) not in _step_hit_ids and enemy.pos.distance_to(player_position) < 78.0:
				_step_hit_ids.append(int(enemy.id))
				_hit_enemy(enemy, _base_damage() * 1.9, _dodge_direction * 32.0)
		_spawn_ghost(delta)
	elif _dodge_timer > 0.0:
		_dodge_timer = maxf(0.0, _dodge_timer - delta)
		player_position += _dodge_direction * 620.0 * delta
		_spawn_ghost(delta)
	else:
		var speed := 220.0 if _attack_timer <= 0.0 else 150.0
		player_position += movement.limit_length(1.0) * speed * delta
	player_position = _clamp_position(player_position)
	if _attack_timer > 0.0:
		_attack_timer = maxf(0.0, _attack_timer - delta)
		if not _attack_impacted and _attack_timer <= 0.21 + 0.000001:
			_attack_impacted = true
			_sword_impact()
	for enemy in enemies:
		if float(enemy.hp) > 0.0:
			_update_enemy(enemy, delta)
		if _resolved:
			return
	_update_projectiles(delta)
	if _resolved:
		return
	enemies = enemies.filter(func(enemy: Dictionary) -> bool: return float(enemy.hp) > 0.0)
	if enemies.is_empty():
		if wave >= _waves.size():
			_settle(true)
			return
		if _wave_delay <= 0.0:
			_wave_delay = 1.7
			_banner = "收劍調息 · 下一陣"
			_banner_timer = 1.5
		else:
			_wave_delay -= delta
			if _wave_delay <= 0.0:
				_spawn_wave()
	queue_redraw()


func attack(direction: Vector2 = Vector2.ZERO) -> bool:
	if not _can_act() or _cooldown > 0.0 or _dodge_timer > 0.0 or _step_timer > 0.0:
		return false
	if direction.length_squared() > 0.01:
		facing = direction.normalized()
	_combo = (_combo % 3) + 1 if _combo_window > 0.0 else 1
	_combo_window = 1.15
	_attack_timer = 0.32
	_attack_style = "sword"
	_attack_direction = facing
	_attack_impacted = false
	_cooldown = 0.39 if _combo == 3 else 0.33
	_sound_effect(1.0 + _combo * 0.1)
	return true


func dodge(direction: Vector2 = Vector2.ZERO) -> bool:
	if not _can_act() or stamina < 24.0 or _dodge_timer > 0.0 or _step_timer > 0.0:
		return false
	_dodge_direction = direction.normalized() if direction.length_squared() > 0.01 else _movement_or_facing()
	_dodge_timer = 0.25
	_invulnerability = maxf(_invulnerability, 0.34)
	stamina -= 24.0
	_attack_timer = 0.0
	_ghost_timer = 0.0
	_effects.append({"kind": "ring", "pos": player_position, "life": 0.3, "duration": 0.3, "color": JADE, "radius": 40.0})
	_emit_status()
	return true


func cast_qi(direction: Vector2 = Vector2.ZERO) -> bool:
	if not _can_act() or not "sword_qi" in stats.get("skills", []) or _qi_cooldown > 0.0 or stamina < 22.0:
		return false
	var aim := direction.normalized() if direction.length_squared() > 0.01 else facing
	_qi_cooldown = 4.0
	stamina -= 22.0
	_attack_direction = aim
	_attack_timer = 0.28
	_attack_style = "qi"
	_attack_impacted = true
	projectiles.append({"owner": "player", "pos": player_position + aim * 35.0, "velocity": aim * 460.0, "life": 1.55, "damage": _base_damage() * 2.1, "radius": 32.0, "hit_ids": [], "color": GOLD})
	_floating.append({"text": "破雲劍氣", "pos": player_position + Vector2(0, -80), "life": 1.0, "duration": 1.0, "color": GOLD})
	_sound_effect(1.7)
	_emit_status()
	return true


func cast_step(direction: Vector2 = Vector2.ZERO) -> bool:
	if not _can_act() or not "cloud_step" in stats.get("skills", []) or _step_cooldown > 0.0 or stamina < 28.0:
		return false
	_dodge_direction = direction.normalized() if direction.length_squared() > 0.01 else facing
	_step_timer = 0.32
	_step_cooldown = 5.0
	_invulnerability = maxf(_invulnerability, 0.40)
	stamina -= 28.0
	_step_hit_ids.clear()
	_attack_timer = 0.0
	_ghost_timer = 0.0
	_floating.append({"text": "掠影突進", "pos": player_position + Vector2(0, -80), "life": 1.0, "duration": 1.0, "color": JADE})
	_emit_status()
	return true


func use_medicine() -> bool:
	if not _can_act() or hp >= max_hp or _heal_cooldown > 0.0 or medicine_used >= int(stats.get("medicine", 0)):
		return false
	medicine_used += 1
	var recovered := minf(max_hp - hp, max_hp * 0.45)
	hp += recovered
	_heal_cooldown = 1.0
	_floating.append({"text": "+%d 氣血" % roundi(recovered), "pos": player_position + Vector2(0, -70), "life": 1.1, "duration": 1.1, "color": Color("83bb79")})
	_effects.append({"kind": "ring", "pos": player_position, "life": 0.55, "duration": 0.55, "color": Color("83bb79"), "radius": 65.0})
	_emit_status()
	return true


func status() -> Dictionary:
	return {"hp": roundi(hp), "max_hp": roundi(max_hp), "stamina": roundi(stamina), "max_stamina": roundi(max_stamina), "medicine": maxi(0, int(stats.get("medicine", 0)) - medicine_used), "wave": wave, "total_waves": _waves.size(), "enemies": enemies.filter(func(enemy: Dictionary) -> bool: return float(enemy.hp) > 0.0).size(), "sword_qi_cooldown": _qi_cooldown, "cloud_step_cooldown": _step_cooldown, "combo": _combo, "title": _title(), "objective": "避開起手，趁教頭收招時進攻" if mode == "exam" else "觀察起手，逐一應對", "ready": _start_delay <= 0.0, "resolved": _resolved}


func snapshot() -> Dictionary:
	var saved_enemies: Array = []
	for enemy in enemies:
		var copy := enemy.duplicate(true)
		for key in ["pos", "facing", "attack_dir", "target"]:
			copy[key] = _point(copy.get(key, Vector2.ZERO))
		saved_enemies.append(copy)
	var saved_projectiles: Array = []
	for projectile in projectiles:
		var copy := projectile.duplicate(true)
		copy.pos = _point(copy.pos)
		copy.velocity = _point(copy.velocity)
		copy.erase("color")
		saved_projectiles.append(copy)
	var saved_corpses: Array = []
	for corpse in _corpses:
		saved_corpses.append({"kind": corpse.kind, "pos": _point(corpse.pos), "facing": _point(corpse.facing), "age": corpse.age})
	return {"version": 1, "mode": mode, "position": _point(player_position), "facing": _point(facing), "hp": hp, "stamina": stamina, "wave": wave, "enemies": saved_enemies, "projectiles": saved_projectiles, "medicine_used": medicine_used, "hits": successful_hits, "dodges": successful_dodges, "damage_taken": damage_taken, "elapsed": elapsed, "next_enemy_id": _next_enemy_id, "cooldown": _cooldown, "attack_timer": _attack_timer, "attack_direction": _point(_attack_direction), "attack_impacted": _attack_impacted, "combo": _combo, "combo_window": _combo_window, "dodge_timer": _dodge_timer, "dodge_direction": _point(_dodge_direction), "invulnerability": _invulnerability, "heal_cooldown": _heal_cooldown, "qi_cooldown": _qi_cooldown, "step_cooldown": _step_cooldown, "step_timer": _step_timer, "step_hit_ids": _step_hit_ids.duplicate(), "start_delay": _start_delay, "wave_delay": _wave_delay, "resolved": _resolved, "won": _won, "settlement_remaining": _settlement_remaining, "visual": {"hurt_timer": _hurt_timer, "attack_style": _attack_style, "moving": _moving, "corpses": saved_corpses}}


func _restore(saved: Dictionary) -> void:
	if int(_number(saved.get("version"), -1)) != 1 or saved.get("mode", "") != mode:
		return
	if not saved.get("enemies", null) is Array or not saved.get("projectiles", null) is Array:
		return
	# Reject incomplete/corrupted encounters before replacing the fresh wave.
	# An empty final wave is only legal once its result has already been settled.
	var saved_wave := int(_number(saved.get("wave"), -1))
	if saved_wave < 1 or saved_wave > _waves.size() or saved.enemies.size() > 8 or saved.projectiles.size() > 64:
		return
	for value in saved.enemies:
		if not value is Dictionary or not value.get("kind", "") in ["bandit", "lancer", "boss"]:
			return
		if not value.get("pos") is Array or _number(value.get("max_hp"), -1) <= 0:
			return
	if saved.enemies.is_empty() and not bool(saved.get("resolved", false)):
		if saved_wave >= _waves.size() or _number(saved.get("wave_delay"), 0) <= 0:
			return
	player_position = _clamp_position(_vector(saved.get("position", []), player_position))
	facing = _vector(saved.get("facing", []), Vector2.RIGHT).normalized()
	hp = clampf(_number(saved.get("hp"), max_hp), 0.0, max_hp)
	stamina = clampf(_number(saved.get("stamina"), max_stamina), 0.0, max_stamina)
	wave = clampi(int(_number(saved.get("wave"), 1)), 1, _waves.size())
	medicine_used = clampi(int(_number(saved.get("medicine_used"), 0)), 0, int(stats.get("medicine", 0)))
	successful_hits = maxi(0, int(_number(saved.get("hits"), 0)))
	successful_dodges = maxi(0, int(_number(saved.get("dodges"), 0)))
	damage_taken = maxi(0, int(_number(saved.get("damage_taken"), 0)))
	elapsed = clampf(_number(saved.get("elapsed"), 0), 0.0, 86400.0)
	_next_enemy_id = maxi(1, int(_number(saved.get("next_enemy_id"), 10)))
	_cooldown = clampf(_number(saved.get("cooldown"), 0), 0.0, 2.0)
	_attack_timer = clampf(_number(saved.get("attack_timer"), 0), 0.0, 0.32)
	_attack_direction = _vector(saved.get("attack_direction", []), facing).normalized()
	_attack_impacted = bool(saved.get("attack_impacted", true))
	_combo = clampi(int(_number(saved.get("combo"), 0)), 0, 3)
	_combo_window = clampf(_number(saved.get("combo_window"), 0), 0.0, 1.15)
	_dodge_timer = clampf(_number(saved.get("dodge_timer"), 0), 0.0, 0.25)
	_dodge_direction = _vector(saved.get("dodge_direction", []), facing).normalized()
	_invulnerability = clampf(_number(saved.get("invulnerability"), 0), 0.0, 0.7)
	_heal_cooldown = clampf(_number(saved.get("heal_cooldown"), 0), 0.0, 1.0)
	_qi_cooldown = clampf(_number(saved.get("qi_cooldown"), 0), 0.0, 4.0)
	_step_cooldown = clampf(_number(saved.get("step_cooldown"), 0), 0.0, 5.0)
	_step_timer = clampf(_number(saved.get("step_timer"), 0), 0.0, 0.32)
	_step_hit_ids.clear()
	if saved.get("step_hit_ids", []) is Array:
		for id in saved.get("step_hit_ids", []):
			if id is int or id is float:
				_step_hit_ids.append(int(id))
	_start_delay = clampf(_number(saved.get("start_delay"), 0), 0.0, 1.2)
	_wave_delay = clampf(_number(saved.get("wave_delay"), 0), 0.0, 1.7)
	var visual: Dictionary = saved.get("visual", {}) if saved.get("visual", {}) is Dictionary else {}
	_hurt_timer = clampf(_number(visual.get("hurt_timer"), 0), 0.0, HURT_DURATION)
	_attack_style = "qi" if visual.get("attack_style", "sword") == "qi" else "sword"
	_moving = bool(visual.get("moving", false))
	_corpses.clear()
	if visual.get("corpses", []) is Array:
		for value in visual.get("corpses", []):
			if not value is Dictionary or _corpses.size() >= 16 or not value.get("kind", "") in ["bandit", "lancer", "boss"]:
				continue
			_corpses.append({"kind": str(value.kind), "pos": _clamp_position(_vector(value.get("pos"), player_position)), "facing": _vector(value.get("facing"), Vector2.RIGHT), "age": clampf(_number(value.get("age"), 0), 0.0, DEFEAT_DURATION + 0.4)})
	enemies.clear()
	for value in saved.enemies:
		if not value is Dictionary or not value.get("kind", "") in ["bandit", "lancer", "boss"]:
			continue
		if enemies.size() >= 8:
			break
		var enemy := _make_enemy(str(value.kind), _vector(value.get("pos", []), Vector2(750, 350)), int(_number(value.get("id"), _next_enemy_id)))
		for key in ["hp", "max_hp", "cooldown", "windup", "windup_total", "recovery", "stun", "flash", "attack_counter", "phase", "rush_remaining"]:
			enemy[key] = clampf(_number(value.get(key), float(enemy.get(key, 0))), 0.0, 3000.0)
		enemy.hp = minf(float(enemy.hp), float(enemy.max_hp))
		for key in ["facing", "attack_dir", "target"]:
			enemy[key] = _vector(value.get(key, []), enemy[key])
		enemy.attack_kind = str(value.get("attack_kind", "slash")) if value.get("attack_kind", "slash") in ["slash", "shot", "ring", "rush"] else "slash"
		enemy.moving = bool(value.get("moving", false))
		enemy.hurt_timer = clampf(_number(value.get("hurt_timer"), 0), 0.0, HURT_DURATION)
		enemy.strike_timer = clampf(_number(value.get("strike_timer"), 0), 0.0, STRIKE_DURATION)
		enemy.recovery_total = clampf(_number(value.get("recovery_total"), 1.25 if enemy.kind == "boss" else 0.75), 0.0, 2.0)
		enemy.attack_visual = bool(value.get("attack_visual", float(enemy.recovery) > 0.0))
		enemies.append(enemy)
	projectiles.clear()
	for value in saved.projectiles:
		if not value is Dictionary or projectiles.size() >= 64:
			continue
		var owner := "player" if value.get("owner", "") == "player" else "enemy"
		# JSON represents numbers as floats. Normalize identifiers so a piercing
		# projectile cannot hit the same target again after loading a save.
		var hit_ids: Array[int] = []
		if value.get("hit_ids", []) is Array:
			for id in value.get("hit_ids", []):
				if id is int or id is float:
					hit_ids.append(int(id))
		projectiles.append({"owner": owner, "pos": _vector(value.get("pos", []), player_position), "velocity": _vector(value.get("velocity", []), Vector2.ZERO).limit_length(600), "life": clampf(_number(value.get("life"), 0.0), 0.0, 5.0), "damage": clampf(_number(value.get("damage"), 0.0), 0.0, 500.0), "radius": clampf(_number(value.get("radius"), 10.0), 1.0, 60.0), "hit_ids": hit_ids, "color": GOLD if owner == "player" else RED})
	_resolved = bool(saved.get("resolved", false))
	_won = bool(saved.get("won", false))
	_settlement_remaining = clampf(_number(saved.get("settlement_remaining"), 0), 0.0, DEFEAT_DURATION) if _resolved else 0.0
	if hp <= 0.0 and not _resolved:
		_resolved = true
		_won = false
	_banner = "接續這一場交鋒"
	_banner_timer = 1.2


func _wave_plan() -> Array:
	match mode:
		"practice": return [["bandit"], ["bandit"], ["lancer"]]
		"spar": return [["bandit", "bandit"], ["bandit", "lancer"]]
		"grove": return [["bandit", "bandit"], ["bandit", "lancer"], ["lancer"]]
		"ridge": return [["bandit", "lancer"], ["lancer", "bandit"], ["bandit", "lancer"]]
		"exam": return [["bandit", "lancer"], ["boss"]]
	return [["bandit"]]


func _spawn_wave() -> void:
	if wave >= _waves.size():
		return
	var kinds: Array = _waves[wave]
	wave += 1
	var starts := [Vector2(780, 260), Vector2(800, 480), Vector2(600, 170), Vector2(650, 510)]
	for index in range(kinds.size()):
		enemies.append(_make_enemy(str(kinds[index]), starts[index % starts.size()], _next_enemy_id))
		_next_enemy_id += 1
	_banner = "第 %d 陣 · %s" % [wave, "教頭守式穩，收招有破綻" if "boss" in kinds else "看清起手，再出劍"]
	_banner_timer = 2.0
	_wave_delay = 0.0
	projectiles = projectiles.filter(func(projectile: Dictionary) -> bool: return projectile.owner == "player")
	if wave > 1:
		hp = minf(max_hp, hp + max_hp * 0.10)
		stamina = minf(max_stamina, stamina + 35.0)
	_emit_status()


func _make_enemy(kind: String, start: Vector2, identifier: int) -> Dictionary:
	var enemy_hp := 110.0 if kind == "bandit" else 92.0
	if mode == "practice": enemy_hp *= 0.65
	if kind == "boss": enemy_hp = 860.0
	return {"id": identifier, "kind": kind, "pos": _clamp_position(start), "hp": enemy_hp, "max_hp": enemy_hp, "facing": Vector2.LEFT, "attack_dir": Vector2.LEFT, "target": player_position, "cooldown": 1.1 + float(identifier % 3) * 0.35, "windup": 0.0, "windup_total": 1.0, "recovery": 0.0, "stun": 0.0, "flash": 0.0, "attack_kind": "slash", "attack_counter": 0, "phase": 1, "rush_remaining": 0.0, "moving": false, "hurt_timer": 0.0, "strike_timer": 0.0, "recovery_total": 0.0, "attack_visual": false}


func _update_enemy(enemy: Dictionary, delta: float) -> void:
	enemy.moving = false
	enemy.hurt_timer = maxf(0.0, float(enemy.get("hurt_timer", 0.0)) - delta)
	enemy.strike_timer = maxf(0.0, float(enemy.get("strike_timer", 0.0)) - delta)
	enemy.flash = maxf(0.0, float(enemy.flash) - delta)
	enemy.stun = maxf(0.0, float(enemy.stun) - delta)
	if float(enemy.stun) > 0.0:
		return
	if float(enemy.rush_remaining) > 0.0:
		enemy.rush_remaining = maxf(0.0, float(enemy.rush_remaining) - delta)
		enemy.pos = _clamp_position(enemy.pos + enemy.attack_dir * delta * 490.0)
		if enemy.pos.distance_to(player_position) < 49.0:
			_damage_player(15.0, enemy.attack_dir)
		return
	if float(enemy.windup) > 0.0:
		enemy.windup = maxf(0.0, float(enemy.windup) - delta)
		if float(enemy.windup) <= 0.0:
			_enemy_attack(enemy)
		return
	if float(enemy.recovery) > 0.0:
		enemy.recovery = maxf(0.0, float(enemy.recovery) - delta)
		return
	enemy.attack_visual = false
	var to_player: Vector2 = player_position - enemy.pos
	var distance := to_player.length()
	if distance > 0.01: enemy.facing = to_player.normalized()
	var is_boss: bool = enemy.kind == "boss"
	if is_boss and float(enemy.hp) <= float(enemy.max_hp) * 0.50 and int(enemy.phase) == 1:
		enemy.phase = 2
		enemy.recovery = 1.6
		_banner = "第二式 · 不急，再看一步"
		_banner_timer = 2.0
		_effects.append({"kind": "ring", "pos": enemy.pos, "life": 0.6, "duration": 0.6, "color": GOLD, "radius": 100.0})
		return
	enemy.cooldown = maxf(0.0, float(enemy.cooldown) - delta)
	var preferred := 200.0 if enemy.kind == "lancer" else (115.0 if is_boss else 78.0)
	if distance > preferred:
		var speed := 62.0 if enemy.kind == "lancer" else (78.0 if is_boss else 88.0)
		if mode == "practice": speed *= 0.7
		enemy.pos += to_player.normalized() * speed * delta
		enemy.moving = true
	elif enemy.kind == "lancer" and distance < 100.0:
		enemy.pos -= to_player.normalized() * 60.0 * delta
		enemy.moving = true
	for other in enemies:
		if int(other.id) == int(enemy.id): continue
		var spacing: Vector2 = enemy.pos - other.pos
		if spacing.length() < 52.0 and spacing.length() > 0.01:
			enemy.pos += spacing.normalized() * 40.0 * delta
	enemy.pos = _clamp_position(enemy.pos)
	if distance < 40.0 and _dodge_timer <= 0.0 and _step_timer <= 0.0:
		player_position = _clamp_position(player_position + to_player.normalized() * 85.0 * delta)
	if float(enemy.cooldown) <= 0.0 and distance < (470.0 if enemy.kind == "lancer" else 175.0):
		enemy.attack_counter = int(enemy.attack_counter) + 1
		enemy.attack_dir = enemy.pos.direction_to(player_position)
		enemy.target = player_position
		enemy.attack_kind = "shot" if enemy.kind == "lancer" else "slash"
		if is_boss:
			if int(enemy.attack_counter) % 3 == 0: enemy.attack_kind = "ring"
			elif int(enemy.phase) >= 2 and int(enemy.attack_counter) % 2 == 0: enemy.attack_kind = "rush"
		enemy.windup_total = 1.0 if enemy.kind == "lancer" else (1.05 if is_boss else 0.78)
		if mode == "practice": enemy.windup_total = 1.2
		enemy.windup = enemy.windup_total
		enemy.cooldown = 1.3 if is_boss else 1.5


func _enemy_attack(enemy: Dictionary) -> void:
	var is_boss: bool = enemy.kind == "boss"
	var damage := 14.0 if is_boss else 9.0
	if mode == "practice": damage = 5.0
	enemy.recovery = 1.25 if is_boss else 0.75
	enemy.strike_timer = STRIKE_DURATION
	enemy.attack_visual = true
	match str(enemy.attack_kind):
		"shot":
			projectiles.append({"owner": "enemy", "pos": enemy.pos + enemy.attack_dir * 28.0, "velocity": enemy.attack_dir * 245.0, "life": 3.0, "damage": damage, "radius": 12.0, "hit_ids": [], "color": RED})
		"ring":
			_effects.append({"kind": "ring", "pos": enemy.pos, "life": 0.32, "duration": 0.32, "color": RED, "radius": 162.0})
			if enemy.pos.distance_to(player_position) <= 162.0:
				_damage_player(damage, enemy.pos.direction_to(player_position))
		"rush":
			enemy.rush_remaining = 0.42
			enemy.recovery = 1.15
		_:
			var radius := 142.0 if is_boss else 108.0
			_effects.append({"kind": "slash", "pos": enemy.pos, "direction": enemy.attack_dir, "life": 0.24, "duration": 0.24, "color": RED, "radius": radius})
			var offset: Vector2 = player_position - enemy.pos
			if offset.length() <= radius and (offset.length() < 25.0 or offset.normalized().dot(enemy.attack_dir) > 0.30):
				_damage_player(damage, enemy.attack_dir)
	enemy.recovery_total = enemy.recovery


func _sword_impact() -> void:
	var radius := 108.0 if _combo == 3 else 94.0
	var damage := _base_damage() * (1.45 if _combo == 3 else 1.0)
	_effects.append({"kind": "slash", "pos": player_position, "direction": _attack_direction, "life": 0.20, "duration": 0.20, "color": GOLD, "radius": radius})
	for enemy in enemies:
		var difference: Vector2 = enemy.pos - player_position
		if difference.length() <= radius and (difference.length() < 28.0 or difference.normalized().dot(_attack_direction) >= -0.05):
			_hit_enemy(enemy, damage, _attack_direction * (24.0 if _combo == 3 else 11.0))


func _hit_enemy(enemy: Dictionary, damage: float, knockback: Vector2) -> void:
	if not _input_enabled or _resolved or float(enemy.hp) <= 0.0:
		return
	# The examiner's stance is visible on their nameplate. Patient timing
	# during recovery rewards the same opening-reading taught by practice.
	if enemy.kind == "boss" and float(enemy.recovery) <= 0.0:
		damage *= 0.6
	enemy.hp = maxf(0.0, float(enemy.hp) - damage)
	enemy.flash = 0.16
	enemy.hurt_timer = HURT_DURATION
	if enemy.kind != "boss" and float(enemy.windup) <= 0.0:
		enemy.stun = 0.12
	enemy.pos = _clamp_position(enemy.pos + knockback)
	successful_hits += 1
	_floating.append({"text": str(roundi(damage)), "pos": enemy.pos + Vector2(0, -67), "life": 0.65, "duration": 0.65, "color": Color("fff3c8")})
	_effects.append({"kind": "spark", "pos": enemy.pos + Vector2(0, -28), "life": 0.24, "duration": 0.24, "color": GOLD, "radius": 24.0})
	if float(enemy.hp) <= 0.0:
		_corpses.append({"kind": str(enemy.kind), "pos": enemy.pos, "facing": enemy.facing, "age": 0.0})
		_effects.append({"kind": "ring", "pos": enemy.pos, "life": 0.50, "duration": 0.50, "color": Color("a9c7a1"), "radius": 50.0})
		_sound_effect(0.8)


func _damage_player(amount: float, direction: Vector2) -> bool:
	if not _input_enabled or _resolved:
		return false
	if _invulnerability > 0.0:
		if _dodge_timer > 0.0 or _step_timer > 0.0:
			successful_dodges += 1
		return false
	hp = maxf(0.0, hp - amount)
	damage_taken += roundi(amount)
	_invulnerability = 0.62
	_flash = 0.22
	_hurt_timer = HURT_DURATION
	player_position = _clamp_position(player_position + direction.normalized() * 18.0)
	_floating.append({"text": "-%d" % roundi(amount), "pos": player_position + Vector2(0, -76), "life": 0.85, "duration": 0.85, "color": Color("e58c73")})
	_emit_status()
	if hp <= 0.0:
		_settle(false)
	return true


func _update_projectiles(delta: float) -> void:
	for projectile in projectiles:
		projectile.life = float(projectile.life) - delta
		projectile.pos += projectile.velocity * delta
		if projectile.owner == "player":
			for enemy in enemies:
				if int(enemy.id) not in projectile.hit_ids and enemy.pos.distance_to(projectile.pos) < float(projectile.radius) + 23.0:
					projectile.hit_ids.append(int(enemy.id))
					_hit_enemy(enemy, float(projectile.damage), projectile.velocity.normalized() * 20.0)
		elif projectile.pos.distance_to(player_position) < float(projectile.radius) + 19.0:
			_damage_player(float(projectile.damage), projectile.velocity.normalized())
			projectile.life = 0.0
		if _resolved:
			return
	projectiles = projectiles.filter(func(projectile: Dictionary) -> bool: return float(projectile.life) > 0.0 and Rect2(-60, -60, 1200, 760).has_point(projectile.pos))


func _settle_report() -> Dictionary:
	return {"medicine_used": medicine_used, "hits": successful_hits, "dodges": successful_dodges, "damage_taken": damage_taken, "elapsed": snappedf(elapsed, 0.1), "hp": roundi(hp), "max_hp": roundi(max_hp), "mode": mode}


func _settle(won: bool) -> void:
	if _resolved:
		return
	_resolved = true
	_won = won
	_settlement_remaining = DEFEAT_DURATION
	_moving = false
	_emit_status()
	queue_redraw()


func _emit_restored_result(generation: int) -> void:
	if generation == _generation and _resolved and _settlement_remaining <= 0.0 and not _result_emitted:
		_result_emitted = true
		finished.emit(_won, _settle_report())


func _emit_status() -> void:
	if _configured:
		status_changed.emit(status())


func _can_act() -> bool:
	return _configured and _input_enabled and not _resolved and _start_delay <= 0.0


func _base_damage() -> float:
	return 14.0 + float(stats.get("training", 0)) * 1.8 + float(stats.get("insight", 0)) * 0.35


func _movement_or_facing() -> Vector2:
	var movement := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	).normalized()
	return movement if movement.length_squared() > 0.0 else facing


func _clamp_position(point: Vector2) -> Vector2:
	return Vector2(clampf(point.x, FIELD.position.x + 18.0, FIELD.end.x - 18.0), clampf(point.y, FIELD.position.y + 18.0, FIELD.end.y - 18.0))


func _number(value: Variant, fallback: float) -> float:
	if (value is float or value is int) and is_finite(float(value)):
		return float(value)
	return fallback


func _vector(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and value.size() == 2:
		return Vector2(_number(value[0], fallback.x), _number(value[1], fallback.y))
	return fallback


func _point(vector: Vector2) -> Array:
	return [snappedf(vector.x, 0.01), snappedf(vector.y, 0.01)]


func _sound_effect(pitch: float) -> void:
	if is_instance_valid(_sound) and _sound.stream:
		_sound.pitch_scale = pitch
		_sound.play()


func _spawn_ghost(delta: float) -> void:
	_ghost_timer -= delta
	if _ghost_timer <= 0.0:
		_ghost_timer = 0.045
		_ghosts.append({"pos": player_position, "facing": _dodge_direction, "life": 0.28, "animation": player_animation()})


func _update_effects(delta: float) -> void:
	_banner_timer = maxf(0.0, _banner_timer - delta)
	for effect in _effects:
		effect.life = float(effect.life) - delta
	_effects = _effects.filter(func(effect: Dictionary) -> bool: return float(effect.life) > 0.0)
	for text in _floating:
		text.life = float(text.life) - delta
		text.pos += Vector2(0, -28) * delta
	_floating = _floating.filter(func(text: Dictionary) -> bool: return float(text.life) > 0.0)
	for ghost in _ghosts:
		ghost.life = float(ghost.life) - delta
	_ghosts = _ghosts.filter(func(ghost: Dictionary) -> bool: return float(ghost.life) > 0.0)
	for corpse in _corpses:
		corpse.age = float(corpse.age) + delta
	_corpses = _corpses.filter(func(corpse: Dictionary) -> bool: return float(corpse.age) < DEFEAT_DURATION + 0.4)


## Visual state is sampled from simulation time; it never triggers combat hits.
func player_animation() -> Dictionary:
	if hp <= 0.0:
		return _clip_state("defeat", 1.0 - _settlement_remaining / DEFEAT_DURATION)
	# Finish the winning pose while the last foe falls, without advancing any
	# gameplay cooldown, movement, hit or resource value after resolution.
	var presentation_age := DEFEAT_DURATION - _settlement_remaining if _resolved else 0.0
	var step_time := maxf(0.0, _step_timer - presentation_age)
	var dodge_time := maxf(0.0, _dodge_timer - presentation_age)
	var hurt_time := maxf(0.0, _hurt_timer - presentation_age)
	var attack_time := maxf(0.0, _attack_timer - presentation_age)
	if step_time > 0.0:
		return _clip_state("dodge", 1.0 - step_time / 0.32)
	if dodge_time > 0.0:
		return _clip_state("dodge", 1.0 - dodge_time / 0.25)
	if hurt_time > 0.0:
		return _clip_state("hurt", 1.0 - hurt_time / HURT_DURATION)
	if attack_time > 0.0:
		if _attack_style == "qi":
			# Qi is released instantly by the existing skill, so start at contact.
			return _clip_state("attack", (2.0 + (1.0 - attack_time / 0.28) * 4.0) / 6.0)
		var attack_age := maxf(0.0, 0.32 - attack_time)
		var progress := attack_age / 0.11 * (2.0 / 6.0) if not _attack_impacted else (2.0 + maxf(0.0, attack_age - 0.11) / 0.21 * 4.0) / 6.0
		return _clip_state("attack", progress)
	return _loop_state("walk" if _moving else "idle", elapsed)


func enemy_animation(enemy: Dictionary) -> Dictionary:
	if float(enemy.get("hp", 1.0)) <= 0.0:
		return _clip_state("defeat", float(enemy.get("death_age", 0.0)) / DEFEAT_DURATION)
	# Contact is held visibly, even if the foe is struck during the same frame.
	if float(enemy.get("strike_timer", 0.0)) > 0.0 or float(enemy.get("rush_remaining", 0.0)) > 0.0:
		return _clip_state("attack", 2.0 / 6.0)
	if float(enemy.get("hurt_timer", 0.0)) > 0.0:
		return _clip_state("hurt", 1.0 - float(enemy.hurt_timer) / HURT_DURATION)
	if float(enemy.get("windup", 0.0)) > 0.0:
		var anticipation := 1.0 - float(enemy.windup) / maxf(0.01, float(enemy.windup_total))
		return _clip_state("attack", minf(1.999, maxf(0.0, anticipation) * 2.0) / 6.0)
	if bool(enemy.get("attack_visual", false)) and float(enemy.get("recovery", 0.0)) > 0.0:
		var recovery_total := maxf(STRIKE_DURATION + 0.01, float(enemy.get("recovery_total", 0.75)))
		var recovery_age := clampf((recovery_total - float(enemy.recovery) - STRIKE_DURATION) / (recovery_total - STRIKE_DURATION), 0.0, 1.0)
		return _clip_state("attack", (3.0 + recovery_age * 3.0) / 6.0)
	return _loop_state("walk" if bool(enemy.get("moving", false)) else "idle", elapsed + float(enemy.get("id", 0)) * 0.17)


func _clip_state(clip: String, progress: float) -> Dictionary:
	progress = clampf(progress, 0.0, 1.0)
	return {"clip": clip, "progress": progress, "frame": mini(5, floori(progress * 6.0)), "looped": false}


func _loop_state(clip: String, time: float) -> Dictionary:
	var fps := 10.0 if clip == "walk" else 6.0
	var result := _clip_state(clip, fposmod(time * fps, 6.0) / 6.0)
	result.looped = true
	result.elapsed = time
	return result


func _title() -> String:
	return {"practice": "照嶺演武 · 基礎劍式", "spar": "竹影切磋 · 進退有度", "grove": "青篁溪谷 · 清出山徑", "ridge": "望風古道 · 風口交鋒", "exam": "入門選拔 · 請君試劍"}.get(mode, "請君試劍")


func _texture(id: String) -> Texture2D:
	if _textures.has(id):
		return _textures[id] as Texture2D
	if _art == null and ResourceLoader.exists("res://scripts/art.gd"):
		_art = load("res://scripts/art.gd") as Script
	if _art == null:
		return null
	var result: Variant = _art.call("portrait", id)
	if result is Texture2D:
		_textures[id] = result
		return result as Texture2D
	return null


func _draw() -> void:
	_draw_court()
	if not _configured:
		return
	for enemy in enemies:
		if float(enemy.windup) > 0.0:
			_draw_telegraph(enemy)
	for ghost in _ghosts:
		_draw_actor(ghost.pos, "hero", ghost.facing, ghost.get("animation", _clip_state("dodge", 0.0)), Color(0.45, 0.80, 0.71, float(ghost.life) / 0.28 * 0.30), false)
	var figures: Array[Dictionary] = []
	for corpse in _corpses:
		figures.append({"pos": corpse.pos, "corpse": corpse})
	for enemy in enemies:
		if float(enemy.hp) > 0.0:
			figures.append({"pos": enemy.pos, "enemy": enemy})
	figures.append({"pos": player_position, "hero": true})
	figures.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.pos.y < b.pos.y)
	for figure in figures:
		if figure.has("hero"):
			var tint := Color("ffd4c8") if _flash > 0.0 else Color.WHITE
			if _invulnerability > 0.0 and _flash <= 0.0: tint = Color(0.77, 1.0, 0.92, 0.85)
			var direction := _dodge_direction if _step_timer > 0.0 or _dodge_timer > 0.0 else (_attack_direction if _attack_timer > 0.0 else facing)
			_draw_actor(player_position, "hero", direction, player_animation(), tint, true)
		elif figure.has("corpse"):
			var corpse: Dictionary = figure.corpse
			var id := "examiner" if corpse.kind == "boss" else str(corpse.kind)
			var fade := 1.0 - clampf((float(corpse.age) - DEFEAT_DURATION) / 0.4, 0.0, 1.0)
			_draw_actor(corpse.pos, id, corpse.facing, _clip_state("defeat", float(corpse.age) / DEFEAT_DURATION), Color(1, 1, 1, fade), false, 1.20 if corpse.kind == "boss" else 1.0)
		else:
			var enemy: Dictionary = figure.enemy
			var id := "examiner" if enemy.kind == "boss" else str(enemy.kind)
			var direction: Vector2 = enemy.attack_dir if float(enemy.windup) > 0.0 or float(enemy.get("strike_timer", 0.0)) > 0.0 or float(enemy.rush_remaining) > 0.0 else enemy.facing
			_draw_actor(enemy.pos, id, direction, enemy_animation(enemy), Color("ffd3c2") if float(enemy.flash) > 0.0 else Color.WHITE, false, 1.20 if enemy.kind == "boss" else 1.0)
			_draw_enemy_health(enemy)
	for projectile in projectiles:
		var direction: Vector2 = projectile.velocity.normalized()
		var color: Color = projectile.color
		draw_line(projectile.pos - direction * 34.0, projectile.pos + direction * 12.0, Color(color, 0.24), 15.0, true)
		draw_line(projectile.pos - direction * 26.0, projectile.pos + direction * 11.0, color.lightened(0.3), 5.0, true)
		draw_circle(projectile.pos, 5.0, Color("fff4cf"))
	for effect in _effects:
		_draw_effect(effect)
	for entry in _floating:
		var color: Color = entry.color
		color.a = minf(1.0, float(entry.life) / 0.25)
		_label(str(entry.text), entry.pos + Vector2(-70, 0), 140, 19, color, true)
	if _banner_timer > 0.0:
		var alpha := minf(1.0, _banner_timer / 0.35)
		draw_style_box(_panel(Color(INK, 0.88 * alpha), 16), Rect2(300, 68, 480, 47))
		_label(_banner, Vector2(310, 98), 460, 20, Color(PAPER, alpha), true)
	if not _input_enabled and not _resolved:
		draw_rect(Rect2(Vector2.ZERO, SIZE), Color(0.10, 0.18, 0.17, 0.16))


func _draw_court() -> void:
	draw_style_box(_panel(Color("d4ddc6"), 20), Rect2(Vector2.ZERO, SIZE))
	var background: Texture2D
	if _art:
		var location := mode if mode in ["grove", "ridge"] else "wangxi"
		var result: Variant = _art.call("location", location)
		if result is Texture2D: background = result as Texture2D
	if background:
		draw_texture_rect(background, Rect2(Vector2.ZERO, SIZE), false, Color(1, 1, 1, 0.58))
	draw_style_box(_panel(Color(PAPER, 0.91), 10), Rect2(12, 9, 1056, 47))
	draw_style_box(_panel(Color(PAPER, 0.91), 10), Rect2(14, 588, 1052, 40))
	draw_style_box(_panel(Color("496456"), 16, Color("b4c29c"), 3), Rect2(38, 83, 1004, 500))
	var ground := Color("ddd2ac") if mode in ["practice", "spar", "exam"] else Color("abb68d")
	draw_style_box(_panel(ground, 12, Color("ede0b9"), 4), Rect2(53, 98, 974, 470))
	# Soft paving keeps attack telegraphs readable while the margins carry scenery.
	for row in range(7):
		for col in range(14):
			var rect := Rect2(62 + col * 69 + (row % 2) * 12, 106 + row * 64, 61, 55)
			if rect.end.x > 1016: continue
			var tile := ground.lightened(float((row * 7 + col * 3) % 5) * 0.016)
			draw_style_box(_panel(tile, 5, Color(0.44, 0.49, 0.36, 0.10), 1), rect)
	var center := Vector2(540, 332)
	draw_arc(center, 173, 0, TAU, 96, Color(0.42, 0.49, 0.38, 0.16), 3, true)
	draw_arc(center, 168, 0, TAU, 96, Color(0.95, 0.93, 0.77, 0.45), 2, true)
	for offset in [Vector2(-480, -230), Vector2(480, -230), Vector2(-480, 230), Vector2(480, 230)]:
		var point: Vector2 = center + offset
		draw_circle(point, 19, Color("758668"))
		draw_circle(point + Vector2(-8, -7), 15, Color("9cae82"))
		draw_circle(point + Vector2(10, -9), 14, Color("b0bb8d"))
	if mode == "exam":
		for x in [125, 955]:
			draw_line(Vector2(x, 75), Vector2(x, 148), Color("765f45"), 4, true)
			draw_colored_polygon(PackedVector2Array([Vector2(x + 4, 80), Vector2(x + 58, 80), Vector2(x + 44, 105), Vector2(x + 4, 105)]), RED if x == 125 else JADE)
	_label(_title(), Vector2(25, 38), 800, 25, INK)
	_label("即時交鋒不推進日程", Vector2(798, 36), 260, 16, Color("506d62"), true)
	_label("WASD 移動   滑鼠指向 · 左鍵 / J 出劍   空白鍵閃避   Q / E 武功   R 用藥", Vector2(24, 614), 1032, 16, INK, true)


func _frame_texture(actor: String, animation: Dictionary) -> Texture2D:
	if _animation == null and ResourceLoader.exists("res://scripts/animation_bank.gd"):
		_animation = load("res://scripts/animation_bank.gd") as Script
	if _animation != null and bool(_animation.call("has_actor", actor)):
		if bool(animation.get("looped", false)):
			return _animation.call("loop_frame", actor, str(animation.clip), float(animation.elapsed)) as Texture2D
		return _animation.call("frame", actor, str(animation.clip), float(animation.progress)) as Texture2D
	return _texture(actor)


func _draw_actor(point: Vector2, id: String, direction: Vector2, animation: Dictionary, tint: Color, hero: bool, scale_factor: float = 1.0) -> void:
	var portrait_id := str(stats.get("origin", "hero")) if id == "hero" else id
	var texture := _frame_texture(portrait_id, animation)
	var animated := _animation != null and bool(_animation.call("has_actor", portrait_id))
	draw_set_transform(point + Vector2(0, 5), 0, Vector2(1, 0.35))
	draw_circle(Vector2.ZERO, 26 * scale_factor, Color(0.15, 0.25, 0.21, 0.22 * tint.a))
	draw_set_transform(Vector2.ZERO)
	if hero:
		draw_arc(point + Vector2(0, 5), 30, 0.15, PI - 0.15, 24, Color(JADE, tint.a * 0.8), 3, true)
	var mirror := -1.0 if direction.x < -0.12 else 1.0
	draw_set_transform(point, 0, Vector2(mirror, 1.0) * scale_factor)
	if texture:
		if animated:
			var frame_rect: Rect2 = _animation.call("draw_rect", portrait_id, 104.0)
			draw_texture_rect(texture, frame_rect, false, tint)
		else:
			var height := 104.0
			var width := height * texture.get_width() / float(maxi(1, texture.get_height()))
			draw_texture_rect(texture, Rect2(-width / 2.0, -height + 11, width, height), false, tint)
	else:
		var coat := JADE if hero else (RED if id == "bandit" else Color("7187a0"))
		draw_colored_polygon(PackedVector2Array([Vector2(-20, -7), Vector2(-14, -48), Vector2(13, -48), Vector2(22, -7)]), coat * tint)
		draw_circle(Vector2(0, -64), 22, Color("eac6a2") * tint)
		draw_arc(Vector2(0, -68), 23, PI, TAU, 18, Color("3a4541"), 10, true)
		draw_line(Vector2(12, -30), Vector2(47, -60), Color("f2ecce"), 5, true)
		draw_line(Vector2(-12, -2), Vector2(-13, 6), Color("514638"), 9, true)
		draw_line(Vector2(11, -2), Vector2(12, 6), Color("514638"), 9, true)
	draw_set_transform(Vector2.ZERO)
	if hero:
		var dot := point + direction * 35.0 + Vector2(0, -24)
		draw_circle(dot, 3, Color(GOLD, 0.85))


func _draw_enemy_health(enemy: Dictionary) -> void:
	var width := 106.0 if enemy.kind == "boss" else 70.0
	var point: Vector2 = enemy.pos + Vector2(-width / 2.0, -115 if enemy.kind == "boss" else -101)
	draw_style_box(_panel(Color("435849"), 3), Rect2(point, Vector2(width, 7)))
	var percent := clampf(float(enemy.hp) / maxf(1, float(enemy.max_hp)), 0.0, 1.0)
	if percent > 0.0:
		draw_style_box(_panel(GOLD if enemy.kind == "boss" else RED, 3), Rect2(point, Vector2(width * percent, 7)))
	var label := ("教頭 · 破綻" if float(enemy.recovery) > 0.0 else "教頭 · 守式") if enemy.kind == "boss" else ("短刀客" if enemy.kind == "bandit" else "長兵客")
	if mode == "practice": label = "陪練弟子" if enemy.kind == "bandit" else "劍氣陪練"
	_label(label, point + Vector2(-20, -8), width + 40, 14, INK, true)
	if float(enemy.windup) > 0.0:
		_label("!", enemy.pos + Vector2(-14, -142), 28, 27, RED, true)


func _draw_telegraph(enemy: Dictionary) -> void:
	var progress := 1.0 - float(enemy.windup) / maxf(0.01, float(enemy.windup_total))
	var color := Color(0.75, 0.26, 0.20, 0.10 + progress * 0.17)
	var rim := Color(0.82, 0.36, 0.25, 0.5 + progress * 0.4)
	var point: Vector2 = enemy.pos
	var aim: Vector2 = enemy.attack_dir
	match str(enemy.attack_kind):
		"ring":
			draw_circle(point, 162.0, color)
			draw_arc(point, 162.0, 0, TAU, 64, rim, 2.5, true)
			draw_arc(point, 162.0 * progress, 0, TAU, 64, Color(rim, 0.5), 2, true)
		"shot", "rush":
			var length := 370.0 if enemy.attack_kind == "shot" else 240.0
			var perpendicular := aim.orthogonal() * (14.0 if enemy.attack_kind == "shot" else 32.0)
			draw_colored_polygon(PackedVector2Array([point + perpendicular, point + aim * length + perpendicular, point + aim * length - perpendicular, point - perpendicular]), color)
			draw_line(point, point + aim * length, rim, 2.0, true)
		_:
			var radius := 142.0 if enemy.kind == "boss" else 108.0
			var vertices := PackedVector2Array([point])
			for i in range(23):
				vertices.append(point + Vector2.from_angle(aim.angle() - 1.27 + float(i) / 22.0 * 2.54) * radius)
			draw_colored_polygon(vertices, color)
			draw_arc(point, radius, aim.angle() - 1.27, aim.angle() + 1.27, 26, rim, 3, true)


func _draw_effect(effect: Dictionary) -> void:
	var fraction := clampf(float(effect.life) / float(effect.duration), 0.0, 1.0)
	var color: Color = effect.color
	color.a = fraction
	match str(effect.kind):
		"ring":
			draw_arc(effect.pos, float(effect.radius) * (1.0 - fraction * 0.5), 0, TAU, 40, color, 3, true)
		"slash":
			var angle: float = effect.direction.angle()
			var radius := float(effect.radius)
			draw_arc(effect.pos + Vector2(0, -15), radius, angle - 1.35, angle + 1.35, 32, Color(color, fraction * 0.2), 22, true)
			draw_arc(effect.pos + Vector2(0, -15), radius, angle - 1.35, angle + 1.35, 32, color, 5, true)
			draw_arc(effect.pos + Vector2(0, -15), radius - 8, angle - 0.9, angle + 1.1, 28, Color(1, 0.98, 0.82, fraction), 3, true)
		"spark":
			for i in range(6):
				var direction := Vector2.from_angle(float(i) / 6.0 * TAU)
				draw_line(effect.pos + direction * 7.0, effect.pos + direction * float(effect.radius) * (1.3 - fraction), color, 3, true)


func _panel(color: Color, radius: int, border: Color = Color.TRANSPARENT, border_width: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.border_color = border
	style.set_border_width_all(border_width)
	return style


func _label(text: String, point: Vector2, width: float, size: int, color: Color, centered: bool = false) -> void:
	if not _font:
		return
	draw_string(_font, point + Vector2(0, 1), text, HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT, width, size, Color(0.07, 0.13, 0.12, color.a * 0.18))
	draw_string(_font, point, text, HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT, width, size, color)
