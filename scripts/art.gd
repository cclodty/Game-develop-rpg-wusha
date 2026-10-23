class_name WeiyuanArt
extends RefCounted
## Original generated illustrations, sampled without modifying their source PNGs.

const CHARACTER_PATH := "res://assets/generated/characters.png"
const PORTRAITS := ["hero", "herbalist", "performer", "shen", "lu", "tao", "zhou", "xiao", "lin", "bandit", "lancer", "examiner"]
const LOCATION_PATHS := {
	"wangxi": "res://assets/generated/wangxi.png",
	"grove": "res://assets/generated/grove.png",
	"ridge": "res://assets/generated/ridge.png",
}
static var _textures: Dictionary = {}
static var _regions: Dictionary = {}

static func portrait(id: String) -> Texture2D:
	var resolved := "hero" if id == "courier" else id
	var index := PORTRAITS.find(resolved)
	if index < 0:
		index = 0
	return _region(CHARACTER_PATH, Vector2i(4, 3), index)

static func location(id: String) -> Texture2D:
	return _texture(String(LOCATION_PATHS.get(id, LOCATION_PATHS["wangxi"])))

static func title_background() -> Texture2D:
	var title := _texture("res://assets/generated/title.png")
	return title if title != null else location("wangxi")

static func icon(id: String) -> Texture2D:
	# Character tokens can also label a compact activity card.
	return portrait(id)

static func available() -> bool:
	return ResourceLoader.exists(CHARACTER_PATH)

static func _texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path] as Texture2D
	if not ResourceLoader.exists(path):
		return null
	var texture := load(path) as Texture2D
	if texture != null:
		_textures[path] = texture
	return texture

static func _region(path: String, grid: Vector2i, index: int) -> Texture2D:
	var key := path + ":" + str(index)
	if _regions.has(key):
		return _regions[key] as Texture2D
	var source := _texture(path)
	if source == null:
		return null
	var size := source.get_size()
	var x0 := roundi(size.x * float(index % grid.x) / float(grid.x))
	var y0 := roundi(size.y * float(index / grid.x) / float(grid.y))
	var x1 := roundi(size.x * float(index % grid.x + 1) / float(grid.x))
	var y1 := roundi(size.y * float(index / grid.x + 1) / float(grid.y))
	var frame := Rect2i(x0, y0, x1 - x0, y1 - y0)
	var region := AtlasTexture.new()
	region.atlas = source
	var used := _visible_bounds(source.get_image().get_region(frame))
	if used.has_area():
		used = used.grow(5).intersection(Rect2i(Vector2i.ZERO, frame.size))
		region.region = Rect2(frame.position + used.position, used.size)
	else:
		region.region = Rect2(frame)
	region.filter_clip = true
	_regions[key] = region
	return region

static func _visible_bounds(frame: Image) -> Rect2i:
	frame.convert(Image.FORMAT_RGBA8)
	var bytes := frame.get_data()
	var minimum := Vector2i(frame.get_width(), frame.get_height())
	var maximum := Vector2i(-1, -1)
	for offset in range(3, bytes.size(), 4):
		if bytes[offset] <= 32:
			continue
		var pixel := floori(float(offset) / 4.0)
		var point := Vector2i(pixel % frame.get_width(), floori(float(pixel) / float(frame.get_width())))
		minimum.x = mini(minimum.x, point.x)
		minimum.y = mini(minimum.y, point.y)
		maximum.x = maxi(maximum.x, point.x)
		maximum.y = maxi(maximum.y, point.y)
	if maximum.x < 0:
		return Rect2i()
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE)
