class_name WeiyuanAnimation
extends RefCounted
## Cached frame sampling. Every actor has one crop, scale and ground anchor,
## shared by every frame; changing poses never resizes its visible silhouette.

const DIRECTORY = "res://assets/generated/animation/"
const GRID = Vector2i(6, 6)
const FRAME_COUNT = 6
const ACTORS = ["courier", "herbalist", "performer", "bandit", "lancer", "examiner"]
const NPCS = ["shen", "lu", "tao", "zhou", "xiao", "lin"]
const CLIPS = ["idle", "walk", "attack", "dodge", "hurt", "defeat"]
const DURATIONS = {"idle": 1.0, "walk": 0.6, "attack": 0.32, "dodge": 0.25, "hurt": 0.24, "defeat": 0.65}
const ALIASES = {"hero": "courier", "hero_courier": "courier", "hero_herbalist": "herbalist", "hero_performer": "performer"}

# Some generated sheets have six separated poses per row but uneven row spacing.
# These measured source cells preserve every authored pixel at ONE common scale.
# Atlas margins place them on a shared canvas; there is no per-frame resizing.
# rows are [top, bottom_exclusive, ground_y]; columns are six physical cell edges.
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

# Coordinates are fractions of a whole source cell, never a frame's alpha box.
# body_height describes the actor's nominal standing height within that cell.
# Calibrate an entire actor here after reviewing all clips in AnimationPreview.
# Keep generous weapon margins; original source PNG pixels remain untouched.
const CALIBRATION = {
	"courier": {"crop": Rect2(0, 0, 1, 1), "anchor": Vector2(0.5, 0.90), "body_height": 0.80},
	"herbalist": {"crop": Rect2(0, 0, 1, 1), "anchor": Vector2(0.5, 0.90), "body_height": 0.80},
	"performer": {"crop": Rect2(0, 0, 1, 1), "anchor": Vector2(0.5, 0.90), "body_height": 0.80},
	"bandit": {"crop": Rect2(0, 0, 1, 1), "anchor": Vector2(0.5, 0.90), "body_height": 0.80},
	"lancer": {"crop": Rect2(0, 0, 1, 1), "anchor": Vector2(0.5, 0.90), "body_height": 0.80},
	"examiner": {"crop": Rect2(0, 0, 1, 1), "anchor": Vector2(0.5, 0.90), "body_height": 0.80},
	"shen": {"crop": Rect2(0, 0, 1, 1), "anchor": Vector2(0.5, 0.90), "body_height": 0.80},
	"lu": {"crop": Rect2(0, 0, 1, 1), "anchor": Vector2(0.5, 0.90), "body_height": 0.80},
	"tao": {"crop": Rect2(0, 0, 1, 1), "anchor": Vector2(0.5, 0.90), "body_height": 0.80},
	"zhou": {"crop": Rect2(0, 0, 1, 1), "anchor": Vector2(0.5, 0.90), "body_height": 0.80},
	"xiao": {"crop": Rect2(0, 0, 1, 1), "anchor": Vector2(0.5, 0.90), "body_height": 0.80},
	"lin": {"crop": Rect2(0, 0, 1, 1), "anchor": Vector2(0.5, 0.90), "body_height": 0.80},
}

static var _textures: Dictionary = {}
static var _frames: Dictionary = {}

static func has_actor(actor: String) -> bool:
	var resolved: String = str(ALIASES.get(actor, actor))
	return (resolved in ACTORS or resolved in NPCS) and _texture(_path(resolved)) != null

static func frame(actor: String, clip: String, normalized_progress: float) -> Texture2D:
	var resolved: String = _actor(actor)
	var source: Texture2D = _texture(_path(resolved))
	if source == null:
		return null
	var resolved_clip: String = _clip(clip)
	var row: int = NPCS.find(resolved) if resolved in NPCS else CLIPS.find(resolved_clip)
	var column: int = frame_index(resolved_clip, normalized_progress)
	var cache_key: String = "%s:%d:%d" % [resolved, row, column]
	if _frames.has(cache_key):
		return _frames[cache_key] as Texture2D
	if SOURCE_LAYOUTS.has(resolved):
		var layout: Dictionary = SOURCE_LAYOUTS[resolved]
		var layout_row: int = 0 if resolved in NPCS else row
		var source_cell: Rect2i = _explicit_cell(layout, layout_row, column)
		var region: AtlasTexture = AtlasTexture.new()
		region.atlas = source
		region.region = Rect2(source_cell)
		var offset: Vector2i = _explicit_offset(layout, layout_row, column)
		region.margin = Rect2(Vector2(offset), Vector2(layout.canvas_size - source_cell.size))
		region.filter_clip = true
		_frames[cache_key] = region
		return region
	var crop: Rect2 = CALIBRATION[resolved].crop
	var size: Vector2 = source.get_size()
	# Integer grid edges avoid gaps/overlap even when PNG dimensions aren't /6.
	var left: int = roundi(size.x * float(column) / GRID.x)
	var top: int = roundi(size.y * float(row) / GRID.y)
	var right: int = roundi(size.x * float(column + 1) / GRID.x)
	var bottom: int = roundi(size.y * float(row + 1) / GRID.y)
	var cell: Rect2i = Rect2i(left, top, right - left, bottom - top)
	var start: Vector2i = Vector2i(roundi(cell.size.x * crop.position.x), roundi(cell.size.y * crop.position.y))
	var end: Vector2i = Vector2i(roundi(cell.size.x * crop.end.x), roundi(cell.size.y * crop.end.y))
	var region: AtlasTexture = AtlasTexture.new()
	region.atlas = source
	region.region = Rect2(Rect2i(cell.position + start, end - start).intersection(cell))
	# Clamps linear-filter samples to this region instead of neighboring poses.
	region.filter_clip = true
	_frames[cache_key] = region
	return region

static func loop_frame(actor: String, clip: String, elapsed: float) -> Texture2D:
	var resolved_clip: String = "idle" if _actor(actor) in NPCS else _clip(clip)
	var duration: float = clip_duration(resolved_clip)
	var progress: float = fposmod(elapsed, duration) / duration if is_finite(elapsed) else 0.0
	return frame(actor, resolved_clip, progress)

static func draw_rect(actor: String, height: float) -> Rect2:
	var resolved: String = _actor(actor)
	var requested_height: float = maxf(0.0, height) if is_finite(height) else 0.0
	if SOURCE_LAYOUTS.has(resolved):
		var layout: Dictionary = SOURCE_LAYOUTS[resolved]
		var scale: float = requested_height / float(layout.body_height_pixels)
		return Rect2(-Vector2(layout.anchor_pixels) * scale, Vector2(layout.canvas_size) * scale)
	var calibration: Dictionary = CALIBRATION[resolved]
	var crop: Rect2 = calibration.crop
	var anchor: Vector2 = calibration.anchor
	var source: Texture2D = _texture(_path(resolved))
	var cell_size: Vector2 = source.get_size() / Vector2(GRID) if source != null else Vector2.ONE
	var scale: float = requested_height / (cell_size.y * float(calibration.body_height))
	return Rect2((crop.position - anchor) * cell_size * scale, crop.size * cell_size * scale)

static func frame_index(clip: String, normalized_progress: float) -> int:
	# A closed interval makes a non-looping action hold frame 5 at/past its end.
	# 0.11/0.32 of the attack is frame 2, matching the existing damage instant.
	var progress: float = normalized_progress
	if is_nan(progress):
		progress = 0.0
	elif is_inf(progress):
		progress = 1.0 if progress > 0.0 else 0.0
	return mini(FRAME_COUNT - 1, floori(clampf(progress, 0.0, 1.0) * FRAME_COUNT))

static func clip_duration(clip: String) -> float:
	return float(DURATIONS[_clip(clip)])

static func metadata(actor: String) -> Dictionary:
	var resolved: String = _actor(actor)
	var source: Texture2D = _texture(_path(resolved))
	var info: Dictionary = CALIBRATION[resolved].duplicate(true)
	info.merge({
		"actor": resolved, "path": _path(resolved), "grid": GRID,
		"frame_count": FRAME_COUNT, "anchor_space": "normalized_cell",
		"cell_size": source.get_size() / Vector2(GRID) if source != null else Vector2.ZERO,
		"sheet_size": source.get_size() if source != null else Vector2.ZERO,
		"row": NPCS.find(resolved) if resolved in NPCS else -1,
		"clips": ["idle"] if resolved in NPCS else CLIPS.duplicate(),
		"clip_durations": DURATIONS.duplicate(),
		"fps": {"idle": 6.0, "walk": 10.0},
		"looping": ["idle"] if resolved in NPCS else ["idle", "walk"],
		"filter_clip": true, "mipmaps": false, "available": source != null,
		"layout": "uniform_grid", "source_cells": [], "frame_offsets": [],
	})
	if SOURCE_LAYOUTS.has(resolved):
		var layout: Dictionary = SOURCE_LAYOUTS[resolved]
		info.layout = "explicit_cells_fixed_canvas"
		info.source_size = layout.source_size
		info.cell_size = Vector2(layout.canvas_size)
		info.anchor = Vector2(layout.anchor_pixels) / Vector2(layout.canvas_size)
		info.body_height = float(layout.body_height_pixels) / float(layout.canvas_size.y)
		for row in range(layout.rows.size()):
			for column in range(FRAME_COUNT):
				info.source_cells.append(_explicit_cell(layout, row, column))
				info.frame_offsets.append(_explicit_offset(layout, row, column))
	return info

static func _explicit_cell(layout: Dictionary, row: int, column: int) -> Rect2i:
	var edges: Array = layout.columns[row]
	var row_info: Array = layout.rows[row]
	return Rect2i(int(edges[column]), int(row_info[0]), int(edges[column + 1]) - int(edges[column]), int(row_info[1]) - int(row_info[0]))

static func _explicit_offset(layout: Dictionary, row: int, column: int) -> Vector2i:
	var cell: Rect2i = _explicit_cell(layout, row, column)
	var source_anchor: Vector2i = Vector2i(int(layout.column_centers[column]), int(layout.rows[row][2]))
	return layout.anchor_pixels - (source_anchor - cell.position)

static func _actor(actor: String) -> String:
	var resolved: String = str(ALIASES.get(actor, actor))
	return resolved if resolved in ACTORS or resolved in NPCS else "courier"

static func _clip(clip: String) -> String:
	return clip if clip in CLIPS else "idle"

static func _path(actor: String) -> String:
	return DIRECTORY + ("npcs" if actor in NPCS else actor) + ".png"

static func _texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path] as Texture2D
	if not ResourceLoader.exists(path):
		return null
	var texture: Texture2D = load(path) as Texture2D
	if texture != null:
		_textures[path] = texture
	return texture
