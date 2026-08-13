extends Node2D
## ProvinceMap'in çocuğu. Artık polygon triangulation YOK (bkz. province_map.gd
## başlığındaki not) — bir partinin/kazananın rengiyle bir ili "boyamak",
## piksel ızgarasında o ile ait her hücreyi bir Image üzerinde renklendirip
## bunu tek bir ImageTexture olarak (NEAREST filtre ile, pixel-art netliğinde)
## arka planın üstüne çizmek anlamına geliyor. Bu yaklaşım hem çok daha basit
## hem de eski vektör yaklaşımındaki "bazı illerin çok girintili kıyı
## şeridi ear-clipping triangülasyonunu kırıyor" sorununu kökten ortadan
## kaldırıyor (artık triangülasyon diye bir şey yok).

var colors: Dictionary = {}  # province_id -> Color

var _map = null  # ProvinceMap (parent)
var _image: Image = null
var _texture: ImageTexture = null
var _dirty: bool = true

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func setup(map) -> void:
	_map = map
	if map.grid_width > 0 and map.grid_height > 0:
		_image = Image.create(map.grid_width, map.grid_height, false, Image.FORMAT_RGBA8)
	mark_dirty()

func mark_dirty() -> void:
	_dirty = true
	queue_redraw()

func _draw() -> void:
	if _map == null or _image == null:
		return
	if _dirty:
		_rebuild_image()
		_dirty = false
	if _texture == null:
		return
	var rect := Rect2(Vector2.ZERO, Vector2(_map.grid_width, _map.grid_height) * _map.MAP_UNIT_SCALE)
	draw_texture_rect(_texture, rect, false)

func _rebuild_image() -> void:
	_image.fill(Color(0, 0, 0, 0))
	if not colors.is_empty():
		var grid_w: int = _map.grid_width
		var grid_h: int = _map.grid_height
		var grid: PackedInt32Array = _map._grid
		var ids: Array = _map.ids
		# province_id -> Color, hızlı erişim için index bazlı bir diziye çevir.
		var color_by_index: Array = []
		color_by_index.resize(ids.size())
		for province_id in colors.keys():
			var idx: int = _map._id_to_index.get(province_id, -1)
			if idx >= 0:
				color_by_index[idx] = colors[province_id]
		for y in grid_h:
			for x in grid_w:
				var idx: int = grid[y * grid_w + x]
				if idx < 0:
					continue
				var c = color_by_index[idx]
				if c != null:
					_image.set_pixel(x, y, c)
	_texture = ImageTexture.create_from_image(_image)
