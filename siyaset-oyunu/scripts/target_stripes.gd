class_name TargetStripes
extends Node2D
## HEDEF ŞERİTLERİ (0.0.334): seçmen haritasında hedef grubun ağırlıklı olduğu
## iller çapraz şeritlerle dolar; her şeridin üstünde sıra yılanındaki gibi
## beyaz ve hedef grubun renginde yılanlar kovalar (aynı süre ve desen, bkz. TurnSnake).
## Harita düğümünün (ProvinceMap) çocuğudur; il üçgenlerini ondan okur.

const SHADER := """
shader_type canvas_item;
uniform vec4 gold : source_color;
uniform vec4 party : source_color;
uniform float unit = 1.0;
uniform float spacing = 12.0;
uniform float width = 3.5;
uniform float dash = 120.0;
uniform float period = 2.6;
varying vec2 p;
varying float seed;
void vertex() { p = VERTEX; seed = COLOR.r; }
void fragment() {
	vec2 s = p / unit;
	float across = (s.x + s.y) * 0.70710678;
	float along = (s.x - s.y) * 0.70710678;
	// Her il kendi fazında ve şerit kaymasında: komşu illerin şeritleri
	// birleşmez, her il ayrı bir kutu gibi okunur.
	across += seed * spacing;
	float k = floor(across / spacing);
	float d = abs(fract(across / spacing) - 0.5) * spacing;
	float line = 1.0 - smoothstep(width * 0.5 - 0.8, width * 0.5 + 0.8, d);
	// TurnSnake deseni: çevrenin %22'si yılan, %28 boşluk; ikinci renk %25 kayık.
	float f = fract(along / dash - TIME / period + k * 0.37 + seed * 0.61);
	float g = fract(f * 2.0);
	vec4 c = vec4(0.1, 0.1, 0.15, 0.35);
	if (g < 0.44) { c = gold; } else if (g >= 0.5 && g < 0.94) { c = party; }
	COLOR = vec4(c.rgb, c.a * line);
}
"""

var _ids: Array = []
var _unit := -1.0
var _material: ShaderMaterial
var _outline: Node2D
var _edge_color := Color.WHITE

func _ready() -> void:
	_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = SHADER
	_material.shader = shader
	_material.set_shader_parameter("gold", Color.WHITE)
	material = _material
	z_index = 1
	set_process(false)
	# İl sınırları ayrı düğümde (gölgelendiricisiz): her il kendi çerçevesinde.
	_outline = Node2D.new()
	_outline.use_parent_material = false
	_outline.material = CanvasItemMaterial.new()
	_outline.draw.connect(_draw_outlines)
	add_child(_outline)

func set_targets(ids: Array, party: Color) -> void:
	party.a = 1.0
	_material.set_shader_parameter("party", party)
	if party != _edge_color:
		_edge_color = party
		_outline.queue_redraw()
	if ids == _ids:
		return
	_ids = ids.duplicate()
	set_process(not _ids.is_empty())
	_unit = -1.0
	queue_redraw()
	# Şerit kalkınca il çerçeveleri de silinsin (vekil haritasında iz kalmasın).
	_outline.queue_redraw()

## Şerit kalınlığı ekran pikseline göre: haritaya yakınlaşınca da aynı kalır.
func _process(_delta: float) -> void:
	# İl yakın plandayken (il paneli) diğer iller çizilmez: şerit de çizilmesin.
	visible = String(get_parent().get("isolated_id")) == ""
	var scale := (get_viewport().get_final_transform() * get_global_transform_with_canvas()).get_scale().x
	var unit := 1.0 / maxf(0.0001, scale)
	if not is_equal_approx(unit, _unit):
		_unit = unit
		_material.set_shader_parameter("unit", unit)
		_outline.queue_redraw()

func _draw() -> void:
	var map := get_parent()
	if map == null or _ids.is_empty():
		return
	var tris_by_id: Dictionary = map.get("_region_tris")
	for id in _ids:
		var tris: PackedVector2Array = tris_by_id.get(id, PackedVector2Array())
		if tris.is_empty():
			continue
		var indices := PackedInt32Array()
		indices.resize(tris.size())
		for i in tris.size():
			indices[i] = i
		var colors := PackedColorArray()
		colors.resize(tris.size())
		# Kırmızı kanal ile ilin fazı (seed) gölgelendiriciye gider.
		colors.fill(Color(fposmod(float(hash(String(id)) % 997) / 997.0, 1.0), 0, 0))
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, tris, colors)
	_outline.queue_redraw()

## Her ilin sınırı: koyu alt çizgi + grubun renginde iç çizgi.
func _draw_outlines() -> void:
	var map := get_parent()
	if map == null:
		return
	var edges: Dictionary = map.get("_edges")
	var px := maxf(_unit, 0.0001) if _unit > 0.0 else 1.0
	for id in _ids:
		for edge in edges.get(id, []):
			_outline.draw_line(edge[0], edge[1], Color(UiTheme.INK, 0.9), 4.0 * px, true)
	for id in _ids:
		for edge in edges.get(id, []):
			_outline.draw_line(edge[0], edge[1], _edge_color.lightened(0.15), 2.0 * px, true)
