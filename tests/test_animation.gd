extends SceneTree
## Checks actual imported sprites, fixed pivots, frame timing and atlas isolation.

const Bank = preload("res://scripts/animation_bank.gd")
var passed: int = 0
var failed: int = 0
var _allow_pending: bool = OS.get_environment("WEIYUAN_ALLOW_PENDING_ANIMATION") == "1"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_timing()
	_test_fallback_and_metadata()
	for actor in Bank.ACTORS + Bank.NPCS:
		_test_actual_actor(str(actor))
	print("TESTS COMPLETE: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		printerr("FAIL: " + message)

func _test_timing() -> void:
	for clip in Bank.CLIPS:
		_check(Bank.frame_index(clip, -1.0) == 0 and Bank.frame_index(clip, 0.0) == 0, "clip starts at first frame: " + clip)
		_check(Bank.frame_index(clip, 1.0) == 5 and Bank.frame_index(clip, 20.0) == 5, "nonloop clip holds final frame: " + clip)
		_check(Bank.frame_index(clip, NAN) == 0 and Bank.frame_index(clip, INF) == 5 and Bank.frame_index(clip, -INF) == 0, "nonfinite phase is bounded: " + clip)
		var sequence: Array = []
		for index in range(6):
			sequence.append(Bank.frame_index(clip, (index + 0.5) / 6.0))
		_check(sequence == [0, 1, 2, 3, 4, 5], "every authored frame is reachable: " + clip)
		_check(is_finite(Bank.clip_duration(clip)) and Bank.clip_duration(clip) > 0.0, "duration supports a finite simulation clock: " + clip)
	_check(Bank.frame_index("attack", 0.109 / 0.32) == 2 and Bank.frame_index("attack", 0.11 / 0.32) == 2, "existing0.11s impact aligns with attackframe2")
	_check(is_equal_approx(6.0 / Bank.clip_duration("idle"), 6.0), "idle default6fps")
	_check(is_equal_approx(6.0 / Bank.clip_duration("walk"), 10.0), "walk default10fps")
	_check(Bank.clip_duration("unknown") == Bank.clip_duration("idle"), "unknown clip uses idle duration")

func _test_fallback_and_metadata() -> void:
	_check(not Bank.has_actor("unknown"), "unknown actor advertises no authored sheet")
	_check(Bank.metadata("unknown").actor == "courier", "unknown actor rendering falls back to courier")
	_check(Bank.metadata("hero").actor == "courier" and Bank.metadata("hero_herbalist").actor == "herbalist" and Bank.metadata("hero_performer").actor == "performer", "portrait and origin aliases resolve consistently")
	var copy: Dictionary = Bank.metadata("courier")
	copy.anchor = Vector2.ZERO
	copy.clip_durations.idle = 100.0
	_check(Bank.metadata("courier").anchor != Vector2.ZERO and Bank.clip_duration("idle") == 1.0, "QA metadata cannot mutate runtime calibration")
	for actor in Bank.ACTORS + Bank.NPCS:
		var info: Dictionary = Bank.metadata(actor)
		_check(info.grid == Vector2i(6, 6) and info.frame_count == 6, "declared grid and frame count: " + actor)
		_check(info.crop.has_area() and Rect2(0, 0, 1, 1).encloses(info.crop), "fixed crop lies within each cell: " + actor)
		_check(info.body_height > 0.0 and info.body_height <= 1.0, "nominal height is actor-wide: " + actor)
		var bounds: Rect2 = Bank.draw_rect(actor, 80.0)
		var anchor_in_crop: Vector2 = (info.anchor - info.crop.position) / info.crop.size
		_check((bounds.position + anchor_in_crop * bounds.size).is_equal_approx(Vector2.ZERO), "ground pivot stays at actor origin: " + actor)
		_check(Bank.draw_rect(actor, 160.0).position.is_equal_approx(bounds.position * 2.0) and Bank.draw_rect(actor, 160.0).size.is_equal_approx(bounds.size * 2.0), "requested size scales one actor-wide rectangle: " + actor)
		_check(Bank.draw_rect(actor, NAN).size == Vector2.ZERO and Bank.draw_rect(actor, INF).size == Vector2.ZERO and Bank.draw_rect(actor, -3).size == Vector2.ZERO, "invalid draw size is finite and empty: " + actor)
		if actor in Bank.NPCS:
			_check(info.row == Bank.NPCS.find(actor) and info.clips == ["idle"], "NPC row belongs to the correct person: " + actor)

func _test_actual_actor(actor: String) -> void:
	var failures_before: int = failed
	if not Bank.has_actor(actor):
		if _allow_pending:
			print("PENDING ART: %s (actual atlas checks deferred; final run must omit WEIYUAN_ALLOW_PENDING_ANIMATION)" % actor)
		else:
			_check(false, "required imported animation sheet missing: " + actor)
		return
	var info: Dictionary = Bank.metadata(actor)
	var idle: AtlasTexture = Bank.frame(actor, "idle", 0.0) as AtlasTexture
	_check(idle != null, "authored frame is an AtlasTexture: " + actor)
	if idle == null:
		return
	var source_image: Image = idle.atlas.get_image()
	_check(source_image != null and not source_image.is_empty(), "real imported pixels are readable: " + actor)
	if source_image == null or source_image.is_empty():
		return
	source_image.convert(Image.FORMAT_RGBA8)
	_check(source_image.detect_alpha() != Image.ALPHA_NONE, "source keeps transparency: " + actor)
	_check(not source_image.has_mipmaps(), "mipmap sampling cannot bleed between sprites: " + actor)
	_check(Bank.frame(actor, "idle", 0.0) == idle and Bank.frame(actor, "unknown", 0.0) == idle, "identical and fallback requests use cached frame: " + actor)
	_check(Bank.loop_frame(actor, "idle", 0.0) == Bank.loop_frame(actor, "idle", 1.0), "idle wraps at a full cycle: " + actor)
	_check(Bank.loop_frame(actor, "idle", -0.05) == Bank.frame(actor, "idle", 0.95), "negative elapsed uses positive modulo: " + actor)
	_check(Bank.loop_frame(actor, "idle", NAN) == idle and Bank.loop_frame(actor, "idle", INF) == idle, "nonfinite elapsed returns a stable first frame: " + actor)
	if actor == "courier":
		_check(Bank.frame("hero", "idle", 0) == idle and Bank.frame("unknown", "idle", 0) == idle, "unknown actor and hero share courier cache")
	var fixed_rect: Rect2 = Bank.draw_rect(actor, 80)
	if info.layout == "explicit_cells_fixed_canvas":
		_check(Vector2i(source_image.get_size()) == info.source_size, "measured regions match original source dimensions: " + actor)
		_check(info.source_cells.size() == info.clips.size() * 6, "every authored pose has measured source metadata: " + actor)
		if actor in Bank.ACTORS:
			_check(_uncovered_opaque_rows(source_image, info.source_cells) == 0, "fixed source rows preserve all opaque character pixels: " + actor)
		elif actor == "shen":
			var npc_cells: Array = []
			for npc in Bank.NPCS:
				npc_cells.append_array(Bank.metadata(npc).source_cells)
			_check(_uncovered_opaque_rows(source_image, npc_cells) == 0, "six measured NPC rows preserve all opaque character pixels")
	for clip in info.clips:
		var fingerprints: Array = []
		var row: int = int(info.row) if actor in Bank.NPCS else Bank.CLIPS.find(clip)
		for index in range(6):
			var atlas: AtlasTexture = Bank.frame(actor, clip, (index + 0.5) / 6.0) as AtlasTexture
			var flat_index: int = index if actor in Bank.NPCS else row * 6 + index
			var expected_cell: Rect2i = info.source_cells[flat_index] if info.layout == "explicit_cells_fixed_canvas" else _cell_rect(source_image.get_size(), row, index)
			_check(atlas.atlas == idle.atlas and atlas.filter_clip, "all frames share source with clipped filtering: %s/%s/%d" % [actor, clip, index])
			_check(Rect2(expected_cell).encloses(atlas.region) and atlas.region.has_area(), "sample never crosses a source cell: %s/%s/%d" % [actor, clip, index])
			_check(atlas.region.position.x == floorf(atlas.region.position.x) and atlas.region.position.y == floorf(atlas.region.position.y), "pixel-aligned source region: %s/%s/%d" % [actor, clip, index])
			_check(Bank.draw_rect(actor, 80) == fixed_rect, "frame selection cannot resize body or move pivot: %s/%s/%d" % [actor, clip, index])
			if info.layout == "explicit_cells_fixed_canvas":
				_check(atlas.get_size().is_equal_approx(info.cell_size), "variable source crop has a fixed virtual frame size: %s/%s/%d" % [actor, clip, index])
				_check(Rect2(Vector2.ZERO, info.cell_size).encloses(Rect2(atlas.margin.position, atlas.region.size)), "all source pixels fit fixed canvas without clipping: %s/%s/%d" % [actor, clip, index])
				_check(atlas.margin.position == Vector2(info.frame_offsets[flat_index]), "padding uses measured pixel offset, never independent scale: %s/%s/%d" % [actor, clip, index])
			var frame_image: Image = source_image.get_region(Rect2i(atlas.region))
			var fingerprint: int = hash(frame_image.get_data())
			if fingerprint not in fingerprints:
				fingerprints.append(fingerprint)
			_check(frame_image.get_used_rect().has_area(), "authored frame contains visible character: %s/%s/%d" % [actor, clip, index])
			var edge_pixels: int = _opaque_edge_pixels(source_image.get_region(expected_cell))
			_check(edge_pixels == 0, "transparent cell gutter prevents cropped weapons/neighbor fragments: %s/%s/%d (%d opaque edge pixels)" % [actor, clip, index, edge_pixels])
		_check(fingerprints.size() == 6, "six separately authored frame contents: " + actor + "/" + clip)
		_check(Bank.frame(actor, clip, 1.0) == Bank.frame(actor, clip, 2.0), "action endpoint cannot wrap to first pose: " + actor + "/" + clip)
	if failed == failures_before:
		print("ART VERIFIED: %s; %d authored frames, fixed ground pivot" % [actor, info.clips.size() * 6])
	else:
		print("ART NEEDS CORRECTION: %s; %d failed pixel/layout checks" % [actor, failed - failures_before])

func _cell_rect(size: Vector2i, row: int, column: int) -> Rect2i:
	var begin: Vector2i = Vector2i(roundi(size.x * float(column) / 6.0), roundi(size.y * float(row) / 6.0))
	var end: Vector2i = Vector2i(roundi(size.x * float(column + 1) / 6.0), roundi(size.y * float(row + 1) / 6.0))
	return Rect2i(begin, end - begin)

func _opaque_edge_pixels(frame_image: Image) -> int:
	# Half-opaque pixels on a cell boundary indicate actual drawn art crossing it;
	# ignore near-transparent antialiasing specks. Artwork needs source padding.
	var count: int = 0
	for x in range(frame_image.get_width()):
		if frame_image.get_pixel(x, 0).a > 0.5:
			count += 1
		if frame_image.get_pixel(x, frame_image.get_height() - 1).a > 0.5:
			count += 1
	for y in range(1, frame_image.get_height() - 1):
		if frame_image.get_pixel(0, y).a > 0.5:
			count += 1
		if frame_image.get_pixel(frame_image.get_width() - 1, y).a > 0.5:
			count += 1
	return count

func _uncovered_opaque_rows(source: Image, cells: Array) -> int:
	var covered_rows: PackedByteArray = []
	covered_rows.resize(source.get_height())
	covered_rows.fill(0)
	for cell in cells:
		for y in range(cell.position.y, cell.end.y):
			covered_rows[y] = 1
	var bytes: PackedByteArray = source.get_data()
	var count: int = 0
	for y in range(source.get_height()):
		if covered_rows[y] != 0:
			continue
		for x in range(source.get_width()):
			if bytes[(y * source.get_width() + x) * 4 + 3] > 128:
				count += 1
	return count
