class_name WeiyuanAnimation
extends RefCounted
## Cached authored frames, with one scale per source bank and one ground anchor.
## Regions follow physical gutters; no frame resizes its own visible silhouette.

const DIRECTORY = "res://assets/generated/animation/"
const Midpoints = preload("res://scripts/animation_midpoints.gd")
const GRID = Vector2i(6, 6)
const SOURCE_FRAME_COUNT = 6
const FRAME_COUNT = 12
const ACTORS = ["courier", "herbalist", "performer", "bandit", "lancer", "examiner"]
const NPCS = ["shen", "lu", "tao", "zhou", "xiao", "lin"]
const CLIPS = ["idle", "walk", "attack", "dodge", "hurt", "defeat"]
const DURATIONS = {"idle": 1.0, "walk": 0.6, "attack": 0.32, "dodge": 0.25, "hurt": 0.24, "defeat": 0.65}
const ALIASES = {"hero": "courier", "hero_courier": "courier", "hero_herbalist": "herbalist", "hero_performer": "performer"}

# Some generated sheets have six separated poses per row but uneven row spacing.
# These measured source cells preserve every authored pixel at ONE common scale.
# Atlas margins place them on a shared canvas; there is no per-frame resizing.
# Rows are [top, bottom_exclusive, ground_y]; seven column edges bound six cells.
const SOURCE_LAYOUTS = {
	"courier": {
		"source_size": Vector2i(1254, 1254), "canvas_size": Vector2i(320, 256),
		"anchor_pixels": Vector2i(128, 224), "body_height_pixels": 148.0,
		"column_centers": [106, 315, 524, 733, 942, 1151],
		"rows": [[96, 253, 247], [311, 474, 467], [512, 692, 686], [741, 897, 891], [935, 1101, 1095], [1117, 1248, 1242]],
		"columns": [
			[0, 214, 427, 623, 822, 1031, 1254],
			[0, 211, 423, 625, 830, 1038, 1254],
			[0, 218, 420, 665, 863, 1040, 1254],
			[0, 214, 429, 631, 838, 1046, 1254],
			[0, 220, 433, 629, 833, 1044, 1254],
			[0, 220, 428, 626, 824, 1048, 1254],
		],
	},
	"herbalist": {
		"source_size": Vector2i(1254, 1254), "canvas_size": Vector2i(320, 256),
		"anchor_pixels": Vector2i(128, 224), "body_height_pixels": 148.0,
		"column_centers": [106, 315, 524, 733, 942, 1151],
		"rows": [[62,219,213],[275,439,433],[477,662,656],[719,874,868],[912,1071,1065],[1111,1240,1234]],
		"columns": [[0,208,414,620,827,1036,1254],[0,207,416,625,837,1046,1254],[0,211,416,657,864,1054,1254],[0,212,423,653,841,1047,1254],[0,218,432,633,842,1053,1254],[0,216,429,634,843,1057,1254]],
	},
	"performer": {
		"source_size": Vector2i(1254, 1254), "canvas_size": Vector2i(320, 256),
		"anchor_pixels": Vector2i(128, 224), "body_height_pixels": 148.0,
		"column_centers": [106, 315, 524, 733, 942, 1151],
		"rows": [[77,234,228],[281,448,442],[495,669,663],[728,878,872],[906,1065,1059],[1098,1227,1221]],
		"columns": [[0,216,418,621,821,1031,1254],[0,221,427,628,829,1034,1254],[0,214,423,666,862,1040,1254],[0,216,427,634,836,1037,1254],[0,224,434,632,835,1043,1254],[0,233,440,638,833,1049,1254]],
	},
	"examiner": {
		"source_size": Vector2i(1254, 1254), "canvas_size": Vector2i(320, 256),
		"anchor_pixels": Vector2i(128, 224), "body_height_pixels": 142.0,
		"column_centers": [106, 315, 524, 733, 942, 1151],
		"rows": [[55,209,203],[254,420,414],[453,630,624],[681,842,836],[885,1047,1041],[1094,1229,1223]],
		"columns": [[0,209,414,627,824,1050,1254],[0,227,436,640,845,1059,1254],[0,200,419,669,850,1055,1254],[0,215,412,630,861,1063,1254],[0,212,422,626,835,1046,1254],[0,218,437,626,840,1046,1254]],
	},
	"shen": {
		"source_size": Vector2i(1254, 1254), "canvas_size": Vector2i(320, 256),
		"anchor_pixels": Vector2i(128, 224), "body_height_pixels": 161.0,
		"column_centers": [106, 315, 524, 733, 942, 1151],
		"rows": [[55,228,222]],
		"columns": [[0,211,418,619,832,1050,1254]],
	},
	"lu": {
		"source_size": Vector2i(1254, 1254), "canvas_size": Vector2i(320, 256),
		"anchor_pixels": Vector2i(128, 224), "body_height_pixels": 162.0,
		"column_centers": [106, 315, 524, 733, 942, 1151],
		"rows": [[270,444,438]],
		"columns": [[0,216,428,632,838,1054,1254]],
	},
	"tao": {
		"source_size": Vector2i(1254, 1254), "canvas_size": Vector2i(320, 256),
		"anchor_pixels": Vector2i(128, 224), "body_height_pixels": 172.0,
		"column_centers": [106, 315, 524, 733, 942, 1151],
		"rows": [[477,661,655]],
		"columns": [[0,204,414,622,830,1044,1254]],
	},
	"zhou": {
		"source_size": Vector2i(1254, 1254), "canvas_size": Vector2i(320, 256),
		"anchor_pixels": Vector2i(128, 224), "body_height_pixels": 163.0,
		"column_centers": [106, 315, 524, 733, 942, 1151],
		"rows": [[693,868,862]],
		"columns": [[0,210,417,626,836,1045,1254]],
	},
	"xiao": {
		"source_size": Vector2i(1254, 1254), "canvas_size": Vector2i(320, 256),
		"anchor_pixels": Vector2i(128, 224), "body_height_pixels": 168.0,
		"column_centers": [106, 315, 524, 733, 942, 1151],
		"rows": [[897,1077,1071]],
		"columns": [[0,213,418,628,849,1039,1254]],
	},
	"lin": {
		"source_size": Vector2i(1254, 1254), "canvas_size": Vector2i(320, 256),
		"anchor_pixels": Vector2i(128, 224), "body_height_pixels": 151.0,
		"column_centers": [106, 315, 524, 733, 942, 1151],
		"rows": [[1086,1249,1243]],
		"columns": [[0,207,418,625,837,1048,1254]],
	},
	"bandit": {
		"source_size": Vector2i(1254, 1254), "canvas_size": Vector2i(320, 256),
		"anchor_pixels": Vector2i(128, 224), "body_height_pixels": 139.0,
		"column_centers": [106, 315, 524, 733, 942, 1151],
		"rows": [[61,212,206],[280,429,423],[499,651,645],[714,859,853],[914,1059,1053],[1097,1228,1222]],
		"columns": [[0,199,413,622,826,1042,1254],[0,204,418,626,835,1051,1254],[0,205,424,631,835,1050,1254],[0,205,412,628,834,1048,1254],[0,204,415,634,834,1046,1254],[0,206,416,629,836,1047,1254]],
	},
	"lancer": {
		"source_size": Vector2i(1254, 1254), "canvas_size": Vector2i(320, 256),
		"anchor_pixels": Vector2i(128, 224), "body_height_pixels": 121.0,
		"column_centers": [106, 315, 524, 733, 942, 1151],
		"rows": [[70,203,197],[270,411,405],[466,618,612],[698,835,829],[899,1037,1031],[1094,1222,1216]],
		"columns": [[0,206,410,625,823,1037,1254],[0,208,420,623,841,1052,1254],[0,201,427,630,852,1058,1254],[0,202,413,626,827,1045,1254],[0,208,424,622,829,1051,1254],[0,195,422,635,838,1053,1254]],
	},
}


static var _textures: Dictionary = {}
static var _frames: Dictionary = {}

static func has_actor(actor: String) -> bool:
	var resolved: String = str(ALIASES.get(actor, actor))
	if resolved not in ACTORS and resolved not in NPCS:
		return false
	# Never advertise twelve frames while substituting repeated original poses.
	return not _layout(resolved, 1).is_empty() and _texture(_path(resolved, 0)) != null and _texture(_path(resolved, 1)) != null

static func frame(actor: String, clip: String, normalized_progress: float) -> Texture2D:
	var resolved: String = _actor(actor)
	var resolved_clip: String = "idle" if resolved in NPCS else _clip(clip)
	var index: int = frame_index(resolved_clip, normalized_progress)
	var cache_key: String = "%s:%s:%d" % [resolved, resolved_clip, index]
	if _frames.has(cache_key):
		return _frames[cache_key] as Texture2D
	var info: Dictionary = frame_metadata(resolved, resolved_clip, index)
	if not bool(info.available):
		return null
	var source: Texture2D = _texture(str(info.path))
	var region: AtlasTexture = AtlasTexture.new()
	region.atlas = source
	region.region = Rect2(info.region)
	region.margin = Rect2(info.offset, info.canvas_size - Vector2(info.region.size))
	region.filter_clip = true
	_frames[cache_key] = region
	return region

static func loop_frame(actor: String, clip: String, elapsed: float) -> Texture2D:
	var resolved_clip: String = "idle" if _actor(actor) in NPCS else _clip(clip)
	var duration: float = clip_duration(resolved_clip)
	var progress: float = fposmod(elapsed, duration) / duration if is_finite(elapsed) else 0.0
	return frame(actor, resolved_clip, progress)

static func draw_rect(actor: String, height: float) -> Rect2:
	# The destination never changes between the original and midpoint bank.
	# Proportional source canvases supply any one-time bank scale correction.
	var layout: Dictionary = SOURCE_LAYOUTS[_actor(actor)]
	var requested_height: float = maxf(0.0, height) if is_finite(height) else 0.0
	var scale: float = requested_height / float(layout.body_height_pixels)
	return Rect2(-Vector2(layout.anchor_pixels) * scale, Vector2(layout.canvas_size) * scale)

static func frame_index(_clip_name: String, normalized_progress: float) -> int:
	# The endpoint holds new frame 11. Original contact frame 2 is now frame 4,
	# still reached at 0.11s in the unchanged 0.32s player attack.
	var progress: float = normalized_progress
	if is_nan(progress):
		progress = 0.0
	elif is_inf(progress):
		progress = 1.0 if progress > 0.0 else 0.0
	var scaled: float = clampf(progress, 0.0, 1.0) * FRAME_COUNT
	var nearest: float = roundf(scaled)
	# JSON round-trips may move an exact frame boundary by one floating ULP.
	if absf(scaled - nearest) <= 0.00000001:
		scaled = nearest
	return mini(FRAME_COUNT - 1, floori(scaled))

static func clip_duration(clip: String) -> float:
	return float(DURATIONS[_clip(clip)])

static func get_fps(clip: String) -> float:
	return float(FRAME_COUNT) / clip_duration(clip)

static func frame_metadata(actor: String, clip: String, index: int) -> Dictionary:
	var resolved: String = _actor(actor)
	var bounded: int = clampi(index, 0, FRAME_COUNT - 1)
	var bank: int = bounded % 2
	var column: int = bounded / 2
	var row: int = 0 if resolved in NPCS else CLIPS.find(_clip(clip))
	var layout: Dictionary = _layout(resolved, bank)
	var path: String = _path(resolved, bank)
	var info: Dictionary = {
		"actor": resolved, "index": bounded, "bank": bank, "column": column,
		"row": NPCS.find(resolved) if resolved in NPCS else row, "path": path,
		"available": false, "region": Rect2i(), "offset": Vector2.ZERO,
		"canvas_size": Vector2.ZERO, "anchor_pixels": Vector2.ZERO,
		"source_size": Vector2i.ZERO, "source_scale": 1.0,
		"body_height_pixels": 0.0,
	}
	if layout.is_empty():
		return info
	var reference: Dictionary = SOURCE_LAYOUTS[resolved]
	var ratio: float = float(layout.body_height_pixels) / float(reference.body_height_pixels)
	var canvas: Vector2 = Vector2(reference.canvas_size) * ratio
	var anchor: Vector2 = Vector2(reference.anchor_pixels) * ratio
	var cell: Rect2i = _explicit_cell(layout, row, column)
	var source_anchor: Vector2 = Vector2(float(layout.column_centers[column]), float(layout.rows[row][2]))
	info.available = _texture(path) != null
	info.region = cell
	info.offset = anchor - (source_anchor - Vector2(cell.position))
	info.canvas_size = canvas
	info.anchor_pixels = anchor
	info.source_size = layout.source_size
	info.source_scale = 1.0 / ratio
	info.body_height_pixels = float(layout.body_height_pixels)
	return info

static func metadata(actor: String) -> Dictionary:
	var resolved: String = _actor(actor)
	var reference: Dictionary = SOURCE_LAYOUTS[resolved]
	var source: Texture2D = _texture(_path(resolved, 0))
	var clips: Array = ["idle"] if resolved in NPCS else CLIPS.duplicate()
	var info: Dictionary = {
		"actor": resolved, "path": _path(resolved, 0), "paths": [_path(resolved, 0), _path(resolved, 1)],
		"grid": GRID, "source_frame_count": SOURCE_FRAME_COUNT, "frame_count": FRAME_COUNT,
		"anchor_space": "normalized_canvas", "crop": Rect2(0, 0, 1, 1),
		"cell_size": Vector2(reference.canvas_size), "source_size": reference.source_size,
		"sheet_size": source.get_size() if source != null else Vector2.ZERO,
		"row": NPCS.find(resolved) if resolved in NPCS else -1, "clips": clips,
		"clip_durations": DURATIONS.duplicate(), "fps": {"idle": get_fps("idle"), "walk": get_fps("walk")},
		"looping": ["idle"] if resolved in NPCS else ["idle", "walk"],
		"filter_clip": true, "mipmaps": false, "available": has_actor(resolved),
		"layout": "interleaved_explicit_cells_fixed_canvas",
		"anchor": Vector2(reference.anchor_pixels) / Vector2(reference.canvas_size),
		"body_height": float(reference.body_height_pixels) / float(reference.canvas_size.y),
		"source_cells": [], "source_paths": [], "frame_offsets": [], "frame_canvas_sizes": [],
		"frame_scales": [], "frame_banks": [], "banks": [],
	}
	for bank in range(2):
		var entry: Dictionary = frame_metadata(resolved, "idle", bank)
		info.banks.append({
			"path": entry.path, "source_size": entry.source_size, "canvas_size": entry.canvas_size,
			"anchor_pixels": entry.anchor_pixels, "source_scale": entry.source_scale,
			"body_height_pixels": entry.body_height_pixels, "available": entry.available,
		})
	for clip in clips:
		for index in range(FRAME_COUNT):
			var entry: Dictionary = frame_metadata(resolved, clip, index)
			info.source_cells.append(entry.region)
			info.source_paths.append(entry.path)
			info.frame_offsets.append(entry.offset)
			info.frame_canvas_sizes.append(entry.canvas_size)
			info.frame_scales.append(entry.source_scale)
			info.frame_banks.append(entry.bank)
	return info

static func _explicit_cell(layout: Dictionary, row: int, column: int) -> Rect2i:
	var edges: Array = layout.columns[row]
	var row_info: Array = layout.rows[row]
	return Rect2i(int(edges[column]), int(row_info[0]), int(edges[column + 1]) - int(edges[column]), int(row_info[1]) - int(row_info[0]))

static func _layout(actor: String, bank: int) -> Dictionary:
	return SOURCE_LAYOUTS.get(actor, {}) if bank == 0 else Midpoints.LAYOUTS.get(actor, {})

static func _actor(actor: String) -> String:
	var resolved: String = str(ALIASES.get(actor, actor))
	return resolved if resolved in ACTORS or resolved in NPCS else "courier"

static func _clip(clip: String) -> String:
	return clip if clip in CLIPS else "idle"

static func _path(actor: String, bank: int = 0) -> String:
	return DIRECTORY + ("inbetweens/" if bank == 1 else "") + ("npcs" if actor in NPCS else actor) + ".png"

static func _texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path] as Texture2D
	if not ResourceLoader.exists(path):
		return null
	var texture: Texture2D = load(path) as Texture2D
	if texture != null:
		_textures[path] = texture
	return texture
