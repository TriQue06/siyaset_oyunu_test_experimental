extends Node2D
## ProvinceMap'in çocuğu. İlleri boyamak GPU'da yapılır:
##   - İNDEKS dokusu (bir kez üretilir): her piksel hangi ile aitse o ilin
##     indeksi+1'i R/G kanallarına yazılır (0 = deniz/il dışı).
##   - PALET dokusu (il sayısı+1 genişliğinde, 1 piksel yüksekliğinde): her
##     ilin rengi. Renk değişince SADECE bu küçük doku güncellenir.
##   - Shader her pikselde indeksi okuyup paletten rengi alır.
## Böylece her karede (ör. seçim gecesi canlı sayımında) tüm iller yeniden
## boyansa bile maliyet ~80 piksellik bir doku güncellemesidir; eskiden tüm
## harita ızgarası CPU'da piksel piksel yeniden boyanıyordu.

const SHADER_CODE := """
shader_type canvas_item;
uniform sampler2D palette : filter_nearest;
uniform float palette_size = 1.0;
void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float idx = floor(t.r * 255.0 + 0.5) + floor(t.g * 255.0 + 0.5) * 256.0;
	if (idx < 0.5) {
		discard;
	}
	COLOR = texture(palette, vec2((idx + 0.5) / palette_size, 0.5));
}
"""

var colors: Dictionary = {}  # province_id -> Color

var _map = null  # ProvinceMap (parent)
var _index_texture: ImageTexture = null
var _palette_image: Image = null
var _palette_texture: ImageTexture = null
var _dirty: bool = true

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func setup(map) -> void:
	_map = map
	if map.grid_width <= 0 or map.grid_height <= 0:
		return
	var grid_w: int = map.grid_width
	var grid_h: int = map.grid_height
	var grid: PackedInt32Array = map._grid
	var index_image := Image.create(grid_w, grid_h, false, Image.FORMAT_RGBA8)
	for y in grid_h:
		for x in grid_w:
			var idx: int = grid[y * grid_w + x]
			if idx < 0:
				continue
			var v := idx + 1
			index_image.set_pixel(x, y, Color8(v & 255, (v >> 8) & 255, 0, 255))
	_index_texture = ImageTexture.create_from_image(index_image)

	var palette_size: int = map.ids.size() + 1
	_palette_image = Image.create(palette_size, 1, false, Image.FORMAT_RGBA8)
	_palette_texture = ImageTexture.create_from_image(_palette_image)
	var shader := Shader.new()
	shader.code = SHADER_CODE
	var shader_material := ShaderMaterial.new()
	shader_material.shader = shader
	shader_material.set_shader_parameter("palette", _palette_texture)
	shader_material.set_shader_parameter("palette_size", float(palette_size))
	material = shader_material
	mark_dirty()

func mark_dirty() -> void:
	_dirty = true
	queue_redraw()

func _draw() -> void:
	if _map == null or _index_texture == null:
		return
	if _dirty:
		_update_palette()
		_dirty = false
	var rect := Rect2(Vector2.ZERO, Vector2(_map.grid_width, _map.grid_height) * _map.MAP_UNIT_SCALE)
	draw_texture_rect(_index_texture, rect, false)

func _update_palette() -> void:
	_palette_image.fill(Color(0, 0, 0, 0))
	for province_id in colors.keys():
		var idx: int = _map._id_to_index.get(province_id, -1)
		if idx >= 0:
			_palette_image.set_pixel(idx + 1, 0, colors[province_id])
	_palette_texture.update(_palette_image)
