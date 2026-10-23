extends SceneTree
## Exercise real scene replacement, not a preview inserted into a test parent.
## run_tests.sh also rejects engine errors: a failed post-close viewport access
## can still finish the scene transition, so its SCRIPT ERROR must fail the gate.

var passed: int = 0
var failed: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error("FAIL preview lifecycle: " + description)


func _frames(count: int = 3) -> void:
	for _frame in range(count):
		await process_frame


func _key(code: int, pressed: bool = true) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _is_title() -> bool:
	return current_scene != null and current_scene.get_script().resource_path == "res://scripts/main.gd" and current_scene._screen == "title"


func _run() -> void:
	change_scene_to_file("res://scenes/animation_preview.tscn")
	await _frames()
	var preview: Control = current_scene
	_check(preview.name == "AnimationPreview" and preview._standalone, "standalone preview identifies its scene ownership")
	# Esc removes this Control immediately. Its handler must consume the event
	# before the scene change, while get_viewport() still returns a live node.
	_key(KEY_ESCAPE)
	_key(KEY_ESCAPE, false)
	await _frames()
	_check(_is_title(), "standalone Escape safely returns to the main title")

	change_scene_to_file("res://scenes/animation_preview.tscn")
	await _frames()
	preview = current_scene
	_check(preview._standalone, "reopened standalone scene is initialized correctly")
	preview.action_buttons.preview_back.pressed.emit()
	await _frames()
	_check(_is_title(), "standalone back button safely replaces the scene")

	var app: Control = current_scene
	for cycle in range(4):
		app._show_animation_preview()
		await _frames()
		preview = app.animation_preview
		_check(not preview._standalone and app._overlay_kind == "animation_preview", "integrated preview becomes an overlay on open %d" % cycle)
		_key(KEY_SPACE)
		_key(KEY_SPACE, false)
		await _frames()
		_check(not preview.playing, "Space reaches the preview once without activating a focused button")
		preview.select_frame(11)
		_key(KEY_RIGHT)
		_key(KEY_RIGHT, false)
		await _frames()
		_check(preview.frame_index == 0, "Right wraps from the twelfth drawn frame to the first")
		_key(KEY_LEFT)
		_key(KEY_LEFT, false)
		await _frames()
		_check(preview.frame_index == 11, "Left wraps back to the twelfth drawn frame")
		_key(KEY_ESCAPE)
		_key(KEY_ESCAPE, false)
		await _frames()
		_check(app._overlay_kind.is_empty() and app.animation_preview == null, "Escape closes the integrated preview once")
		_check(not app.action_buttons.has("preview_pause") and app.action_buttons.has("new_game"), "overlay cleanup removes stale preview buttons and preserves the title")

	current_scene = null
	app.free()
	await _frames()
	await create_timer(0.2).timeout
	print("TESTS COMPLETE: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
