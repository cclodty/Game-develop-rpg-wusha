extends SceneTree
## Checks actual imported sprites, fixed pivots, frame timing and atlas isolation.

const Bank = preload("res://scripts/animation_bank.gd")
const ORIGINAL_HASHES = {
	"bandit": "bae1af501838c027ccce3a961a72fef9aa7e4b132d8da41dc4a2335750ca68c4",
	"courier": "c69955932af95e440b2a0c6468fc0cca3d87f5d0e444d6c53cbf8f6de8327ce5",
	"examiner": "6f598a95cc3faf9eb955eb7f71435a03c36ae4b171f4d966195718504c05b0c4",
	"herbalist": "72d4aba08d431f1cba5048f83ec23756595c8cd6dfb30a07caa1c0ca5b51bf42",
	"lancer": "632d0d443ebec6a1ae7f2a97a7d25122c1d8d868222f56f9c1e63480e00a9ad7",
	"npcs": "f72b1447775ca8e0eb7f8036a64a1283b1ee687c762b61d5ab949f32ec5d9ec2",
	"performer": "15da5865d3721c24c9991966403c34d011511fb2803c759f65bf15ceac69eeb8",
}
var passed: int = 0
var failed: int = 0
var _unique_frames: Dictionary = {}
var _checked_frames: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_timing()
	_test_fallback_and_metadata()
	_test_original_sources()
	for actor in Bank.ACTORS + Bank.NPCS:
		_test_actual_actor(str(actor))
	_check(_checked_frames == 504, "all 504 original and new authored frames were inspected")
	_check(_unique_frames.size() == 504, "all 504 authored frame contents are distinct; no repeated filler")
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
		_check(Bank.frame_index(clip, 1.0) == 11 and Bank.frame_index(clip, 20.0) == 11, "nonloop clip holds final midpoint frame: " + clip)
		_check(Bank.frame_index(clip, NAN) == 0 and Bank.frame_index(clip, INF) == 11 and Bank.frame_index(clip, -INF) == 0, "nonfinite phase is bounded: " + clip)
		var sequence: Array = []
		for index in range(12):
			sequence.append(Bank.frame_index(clip, (index + 0.5) / 12.0))
		_check(sequence == range(12), "every authored frame is reachable: " + clip)
		_check(is_finite(Bank.clip_duration(clip)) and Bank.clip_duration(clip) > 0.0, "duration supports a finite simulation clock: " + clip)
	_check(Bank.frame_index("attack", 0.109 / 0.32) == 4 and Bank.frame_index("attack", 0.11 / 0.32) == 4, "existing 0.11s impact retains original contact pose at frame 4")
	_check(Bank.frame_index("hurt", 0.7499999999999999) == 9 and Bank.frame_index("hurt", 0.75) == 9, "JSON round-trip cannot shift an exact frame boundary")
	_check(Bank.frame_index("hurt", 0.74999) == 8, "boundary snapping does not advance a genuinely earlier phase")
	_check(is_equal_approx(Bank.get_fps("idle"), 12.0) and Bank.clip_duration("idle") == 1.0, "12 fps idle retains its one-second cycle")
	_check(is_equal_approx(Bank.get_fps("walk"), 20.0) and Bank.clip_duration("walk") == 0.6, "20 fps walk retains its 0.6-second cycle")
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
		_check(info.grid == Vector2i(6, 6) and info.source_frame_count == 6 and info.frame_count == 12, "physical 6×6 sheets interleave into 12 logical frames: " + actor)
		_check(info.crop.has_area() and Rect2(0, 0, 1, 1).encloses(info.crop), "fixed crop lies within each cell: " + actor)
		_check(info.body_height > 0.0 and info.body_height <= 1.0, "nominal height is actor-wide: " + actor)
		var bounds: Rect2 = Bank.draw_rect(actor, 80.0)
		var anchor_in_crop: Vector2 = (info.anchor - info.crop.position) / info.crop.size
		_check((bounds.position + anchor_in_crop * bounds.size).is_equal_approx(Vector2.ZERO), "ground pivot stays at actor origin: " + actor)
		_check(Bank.draw_rect(actor, 160.0).position.is_equal_approx(bounds.position * 2.0) and Bank.draw_rect(actor, 160.0).size.is_equal_approx(bounds.size * 2.0), "requested size scales one actor-wide rectangle: " + actor)
		_check(Bank.draw_rect(actor, NAN).size == Vector2.ZERO and Bank.draw_rect(actor, INF).size == Vector2.ZERO and Bank.draw_rect(actor, -3).size == Vector2.ZERO, "invalid draw size is finite and empty: " + actor)
		if actor in Bank.NPCS:
			_check(info.row == Bank.NPCS.find(actor) and info.clips == ["idle"], "NPC row belongs to the correct person: " + actor)

func _test_original_sources() -> void:
	for name in ORIGINAL_HASHES:
		var path: String = Bank.DIRECTORY + name + ".png"
		_check(FileAccess.get_sha256(path) == ORIGINAL_HASHES[name], "original PNG remains byte-for-byte unchanged: " + name)
	for actor in Bank.ACTORS + Bank.NPCS:
		var info: Dictionary = Bank.metadata(actor)
		for clip in info.clips:
			for column in range(6):
				var index: int = column * 2
				var entry: Dictionary = Bank.frame_metadata(actor, clip, index)
				var texture: AtlasTexture = Bank.frame(actor, clip, (index + 0.5) / 12.0) as AtlasTexture
				_check(entry.bank == 0 and entry.column == column and entry.path == info.path, "even frame preserves original source order: %s/%s/%d" % [actor, clip, index])
				_check(texture != null and texture.region == Rect2(entry.region) and entry.source_scale == 1.0, "original authored pixels remain directly sampled: %s/%s/%d" % [actor, clip, index])

func _test_actual_actor(actor: String) -> void:
	var failures_before: int = failed
	if not Bank.has_actor(actor):
		_check(false, "required original or midpoint bank missing/uncalibrated: " + actor)
		return
	var info: Dictionary = Bank.metadata(actor)
	var idle: AtlasTexture = Bank.frame(actor, "idle", 0.0) as AtlasTexture
	_check(idle != null, "authored frame is an AtlasTexture: " + actor)
	if idle == null:
		return
	var source_images: Dictionary = {}
	var source_textures: Dictionary = {}
	for bank in range(2):
		var texture: AtlasTexture = Bank.frame(actor, "idle", (bank + 0.5) / 12.0) as AtlasTexture
		var source_image: Image = texture.atlas.get_image()
		var bank_info: Dictionary = info.banks[bank]
		_check(source_image != null and not source_image.is_empty(), "real source bank pixels are readable: %s/%d" % [actor, bank])
		if source_image == null or source_image.is_empty():
			return
		source_image.convert(Image.FORMAT_RGBA8)
		source_images[bank_info.path] = source_image
		source_textures[bank_info.path] = texture.atlas
		_check(source_image.detect_alpha() != Image.ALPHA_NONE, "source keeps transparency: %s/%d" % [actor, bank])
		_check(not source_image.has_mipmaps(), "mipmap sampling cannot bleed between sprites: %s/%d" % [actor, bank])
		_check(source_image.get_size() == bank_info.source_size, "measured regions match source dimensions: %s/%d" % [actor, bank])
		_check(bank_info.available and bank_info.source_scale > 0.0, "source bank has one valid standing scale: %s/%d" % [actor, bank])
		var bank_cells: Array = []
		for flat_index in range(bank, info.source_cells.size(), 2):
			bank_cells.append(info.source_cells[flat_index])
		if actor in Bank.ACTORS:
			_check(_uncovered_opaque_pixels(source_image, bank_cells) == 0, "measured cells preserve all opaque source pixels: %s/%d" % [actor, bank])
		elif actor == "shen":
			var npc_cells: Array = []
			for npc in Bank.NPCS:
				var npc_info: Dictionary = Bank.metadata(npc)
				for flat_index in range(bank, npc_info.source_cells.size(), 2):
					npc_cells.append(npc_info.source_cells[flat_index])
			_check(_uncovered_opaque_pixels(source_image, npc_cells) == 0, "all six NPC rows preserve opaque source pixels: bank%d" % bank)
	_check(source_textures[info.paths[0]] != source_textures[info.paths[1]], "midpoints use a genuinely separate authored PNG: " + actor)
	_check(Bank.frame(actor, "idle", 0.0) == idle and Bank.frame(actor, "unknown", 0.0) == idle, "identical and fallback requests use cached frame: " + actor)
	_check(Bank.loop_frame(actor, "idle", 0.0) == Bank.loop_frame(actor, "idle", 1.0), "idle wraps at its unchanged full cycle: " + actor)
	_check(Bank.loop_frame(actor, "idle", -0.05) == Bank.frame(actor, "idle", 0.95), "negative elapsed uses positive modulo: " + actor)
	_check(Bank.loop_frame(actor, "idle", NAN) == idle and Bank.loop_frame(actor, "idle", INF) == idle, "nonfinite elapsed returns a stable first frame: " + actor)
	if actor == "courier":
		_check(Bank.frame("hero", "idle", 0) == idle and Bank.frame("unknown", "idle", 0) == idle, "unknown actor and hero share courier cache")
	var fixed_rect: Rect2 = Bank.draw_rect(actor, 80)
	_check(info.source_cells.size() == info.clips.size() * 12 and info.source_paths.size() == info.source_cells.size(), "every output frame exposes its own source attribution: " + actor)
	for clip in info.clips:
		var fingerprints: Array = []
		var row: int = 0 if actor in Bank.NPCS else Bank.CLIPS.find(clip)
		for index in range(12):
			var entry: Dictionary = Bank.frame_metadata(actor, clip, index)
			var atlas: AtlasTexture = Bank.frame(actor, clip, (index + 0.5) / 12.0) as AtlasTexture
			var flat_index: int = row * 12 + index
			var expected_cell: Rect2i = info.source_cells[flat_index]
			var source_image: Image = source_images[entry.path]
			_check(entry.bank == index % 2 and entry.column == index / 2, "logical order interleaves old/new without repeats: %s/%s/%d" % [actor, clip, index])
			_check(atlas.atlas == source_textures[entry.path] and atlas.filter_clip, "frame samples its declared source with clipped filtering: %s/%s/%d" % [actor, clip, index])
			_check(Rect2(expected_cell).encloses(atlas.region) and atlas.region.has_area() and Rect2(Vector2.ZERO, Vector2(source_image.get_size())).encloses(atlas.region), "sample remains inside its isolated source cell: %s/%s/%d" % [actor, clip, index])
			_check(atlas.region.position.x == floorf(atlas.region.position.x) and atlas.region.position.y == floorf(atlas.region.position.y), "pixel-aligned source region: %s/%s/%d" % [actor, clip, index])
			_check(Bank.draw_rect(actor, 80) == fixed_rect, "interleaving cannot move the destination pivot or resize its rectangle: %s/%s/%d" % [actor, clip, index])
			_check((atlas.region.size + atlas.margin.size).is_equal_approx(entry.canvas_size), "padding creates the bank's proportional virtual canvas: %s/%s/%d" % [actor, clip, index])
			_check(Rect2(Vector2.ZERO, entry.canvas_size).encloses(Rect2(atlas.margin.position, atlas.region.size)), "all source pixels fit the virtual canvas: %s/%s/%d" % [actor, clip, index])
			_check(atlas.margin.position.is_equal_approx(info.frame_offsets[flat_index]) and entry.path == info.source_paths[flat_index], "per-frame source and padding are inspectable: %s/%s/%d" % [actor, clip, index])
			_check(is_equal_approx(entry.source_scale, info.banks[entry.bank].source_scale) and (entry.canvas_size * entry.source_scale).is_equal_approx(info.cell_size), "one uniform scale applies to the entire source bank: %s/%s/%d" % [actor, clip, index])
			_check((entry.anchor_pixels / entry.canvas_size).is_equal_approx(info.anchor), "old and new banks share exactly the same ground pivot: %s/%s/%d" % [actor, clip, index])
			var frame_image: Image = source_image.get_region(Rect2i(atlas.region))
			var fingerprint: String = _content_fingerprint(frame_image)
			_check(not fingerprint.is_empty(), "frame contains a visible authored character: %s/%s/%d" % [actor, clip, index])
			if fingerprint not in fingerprints:
				fingerprints.append(fingerprint)
			_unique_frames[fingerprint] = "%s/%s/%d" % [actor, clip, index]
			_checked_frames += 1
			var edge_pixels: int = _opaque_edge_pixels(source_image.get_region(expected_cell))
			_check(edge_pixels == 0, "transparent gutter prevents cropped weapons or neighbor fragments: %s/%s/%d (%d opaque edge pixels)" % [actor, clip, index, edge_pixels])
		_check(fingerprints.size() == 12, "twelve distinct authored contents, not six duplicated textures: " + actor + "/" + clip)
		_check(Bank.frame(actor, clip, 1.0) == Bank.frame(actor, clip, 2.0), "one-shot endpoint holds its last new settle pose: " + actor + "/" + clip)
	if failed == failures_before:
		print("ART VERIFIED: %s; %d distinct authored frames; unchanged original bank" % [actor, info.clips.size() * 12])
	else:
		print("ART NEEDS CORRECTION: %s; %d failed pixel/layout checks" % [actor, failed - failures_before])

func _content_fingerprint(frame_image: Image) -> String:
	# Analyze visible content independently of differing transparent cell padding.
	# This only reads the image; no sprite pixels are edited or synthesized.
	var bytes: PackedByteArray = frame_image.get_data()
	var width: int = frame_image.get_width()
	var minimum: Vector2i = Vector2i(width, frame_image.get_height())
	var maximum: Vector2i = Vector2i(-1, -1)
	for offset in range(3, bytes.size(), 4):
		if bytes[offset] <= 16:
			continue
		var pixel: int = offset / 4
		var point: Vector2i = Vector2i(pixel % width, pixel / width)
		minimum.x = mini(minimum.x, point.x)
		minimum.y = mini(minimum.y, point.y)
		maximum.x = maxi(maximum.x, point.x)
		maximum.y = maxi(maximum.y, point.y)
	if maximum.x < 0:
		return ""
	var visible: Image = frame_image.get_region(Rect2i(minimum, maximum - minimum + Vector2i.ONE))
	var visible_bytes: PackedByteArray = visible.get_data()
	# Ignore invisible RGB (one source keeps RGB beneath alpha zero). The hash
	# must distinguish visible drawings, not hidden background color or padding.
	for offset in range(0, visible_bytes.size(), 4):
		if visible_bytes[offset + 3] <= 16:
			visible_bytes[offset] = 0
			visible_bytes[offset + 1] = 0
			visible_bytes[offset + 2] = 0
			visible_bytes[offset + 3] = 0
	var digest: HashingContext = HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(("%d,%d:" % [visible.get_width(), visible.get_height()]).to_utf8_buffer())
	digest.update(visible_bytes)
	return digest.finish().hex_encode()

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

func _uncovered_opaque_pixels(source: Image, cells: Array) -> int:
	var width: int = source.get_width()
	var covered: PackedByteArray = []
	covered.resize(width * source.get_height())
	covered.fill(0)
	for cell in cells:
		for y in range(cell.position.y, cell.end.y):
			for x in range(cell.position.x, cell.end.x):
				covered[y * width + x] = 1
	var bytes: PackedByteArray = source.get_data()
	var count: int = 0
	for pixel in range(covered.size()):
		if covered[pixel] == 0 and bytes[pixel * 4 + 3] > 128:
			count += 1
	return count
