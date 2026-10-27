extends Node2D
## ProvinceMap'in ÇOCUĞU olarak eklenir (bkz. Map.tscn). İllerin üstüne, o
## ildeki milletvekili sandalyelerini noktalar halinde çizer.
##
## Noktalar SVG gibi NET: her nokta düz bir dörtgen, rengini ve dairesini
## ParliamentDiagram.SEAT_SHADER çizer (her piksel daireye uzaklığını kendisi
## hesaplar, kenar ekranda tam 1 piksel yumuşar, kontur en az 1 piksel).
## Harita hareket ettikçe / büyüdükçe (olay logundaki odak yakınlaşması)
## noktalar her karede o anki ekran ölçeğinde YENİDEN çizilir: büyütülmüş eski
## bir çizim gerilip bulanıklaşmaz.
##
## Yerleşim: her il bir "nokta grubu" (n sandalye için satır/sütun ızgarası)
## oluşturur ve grup ilin merkezine (GameMap.center_of) oturur.
##
## TEK GÖRÜNÜM (0.0.269): her vekil her zaman ayrı pul (eskiden parti başına
## içinde sayı yazan tek daire vardı, ayrı pullar yalnız fareyle açılıyordu).
## İl incelemesinde (set_only_province) yalnız o ilin pulları çizilir.

@export var dot_radius: float = 4.6     # nokta yarıçapı (harita/viewBox birimi)
@export var dot_outline_width: float = 2.0  # siyah kontur kalınlığı
@export var dot_outline_color: Color = Color(0.11, 0.12, 0.13) # eksen_projeksiyon: #1c1e21
@export var dot_spacing: float = 4.4    # aynı gruptaki noktalar arası boşluk
## Konturlu kareler arasında EKRANDA bırakılacak en az boşluk (piksel).
## dot_spacing "renkli kare kenarları arası" boşluğu tanımlıyor, ama kontur
## bunun içine taşıyor: varsayılan değerlerde konturlar arasında sadece
## 14.4 - 13.6 = 0.8 harita birimi kalıyor, bu da her ekran ölçeğinde 1
## pikselden AZ ediyor — kareler görsel olarak birbirine yapışıp tek bir
## bulanık lekeye dönüşüyordu. Bu değer, ne olursa olsun kareler arasında
## en az bu kadar gerçek piksel boşluk kalmasını garanti eder.
@export var min_screen_gap_px: int = 1

## Vekil pullarının ölçeği (0.0.268: %10 büyütüldü).
const DETAIL_SCALE := 1.1

## Nokta grupları bölgenin merkezine (GameMap.center_of) çizilir.
var _seat_centers: Dictionary = {}  # province_id -> Vector2 (harita/local birimi)

# province_id -> Array[Color] (o ildeki her sandalye için bir renk, parti rengi)
var _seats: Dictionary = {}
## Array[{"anchor": Vector2, "layout": Array[int], "colors": Array[Color]}]
## _draw() bunları TAM SAYI PİKSEL ızgarasında çizer (bkz. _draw). Nokta
## konumları burada ÖNCEDEN hesaplanmıyor — çünkü doğru piksel hizalaması
## ancak çizim anındaki gerçek ekran ölçeği bilinerek yapılabilir.
var _groups: Array = []

@onready var _province_map = get_parent()

var _white_texture: Texture2D

func _ready() -> void:
	_load_seat_centers()
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	_white_texture = ImageTexture.create_from_image(image)
	var shader := Shader.new()
	shader.code = PAWN_SHADER
	var shader_material := ShaderMaterial.new()
	shader_material.shader = shader
	material = shader_material
	# Harita (ebeveyn) yakınlaşınca/kayınca yeniden çiz: ölçek o anki ekrana göre.
	set_notify_transform(true)
	set_process(false)

var _drawn_key := Vector3(-1, -1, -1)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		# Tam piksellik öteleme (katman kayması) çizimin piksel hizasını bozmaz:
		# yeniden çizmeye gerek yok. Ölçek ya da kesirli kayma değişince çizilir.
		var xform := get_viewport().get_final_transform() * get_global_transform_with_canvas()
		var key := Vector3(xform.get_scale().x, fposmod(xform.origin.x, 1.0), fposmod(xform.origin.y, 1.0))
		if not key.is_equal_approx(_drawn_key):
			_drawn_key = key
			queue_redraw()

## Altıgen haritada merkezler GameMap'ten gelir (bölgenin iç hücresi).
func _load_seat_centers() -> void:
	_seat_centers.clear()

## O ilin sandalye/renk listesini ayarlar ve tüm noktaları yeniden hesaplar.
## seat_colors: her eleman bir Color (o koltuktaki partinin rengi).
func set_seats(province_id: String, seat_colors: Array) -> void:
	_seats[province_id] = seat_colors
	_rebuild()

func clear_province(province_id: String) -> void:
	_seats.erase(province_id)
	_rebuild()

## Tüm illeri tek seferde ayarlar (tek yeniden hesaplama). province_id -> Array[Color]
func set_all(seats_by_province: Dictionary) -> void:
	_seats = seats_by_province.duplicate()
	_rebuild()

## İl incelemesi: yalnız bu ilin noktaları, kalabalık olsa da hep çizilir.
var _only_id := ""

func set_only_province(province_id: String) -> void:
	_only_id = province_id
	_rebuild()

func clear_all() -> void:
	_seats.clear()
	_rebuild()

## Referans web uygulamasındaki getDotLayout(n) ile birebir aynı mantık:
## küçük n'ler için elle ayarlanmış, kompakt (kare-ye yakın) düzenler;
## büyük n'ler için sqrt tabanlı sütun sayısı + satırlara eşit dağıtım.
func _get_dot_layout(n: int) -> Array:
	if n <= 0:
		return []
	match n:
		1: return [1]
		2: return [2]
		3: return [3]
		4: return [2, 2]
		5: return [3, 2]
		6: return [3, 3]
		7: return [2, 3, 2]
		8: return [3, 3, 2]
		9: return [3, 3, 3]

	var cols: int
	if n > 20:
		cols = int(ceil(sqrt(n * 1.2)))
		cols = min(cols, 7)
	else:
		cols = int(ceil(sqrt(n * 1.5)))
		cols = min(cols, 8)

	var rows := int(ceil(float(n) / float(cols)))
	var layout: Array = []
	var remaining := n
	for i in rows:
		var r := int(ceil(float(remaining) / float(rows - i)))
		layout.append(r)
		remaining -= r
	return layout

func _rebuild() -> void:
	_groups.clear()

	if _province_map == null:
		queue_redraw()
		return

	var groups: Array = []
	for province_id in _seats.keys():
		var colors: Array = _seats[province_id]
		if colors.is_empty():
			continue
		# İl incelemesi: yalnız bu il.
		if _only_id != "" and province_id != _only_id:
			continue
		groups.append(_make_group(province_id, colors))

	# Sınır kelepçesi: büyük illerde nokta kümesi haritanın dışına taşmasın.
	var map_size := Vector2.ZERO
	if _province_map != null and _province_map.grid_width > 0:
		map_size = Vector2(_province_map.grid_width, _province_map.grid_height) * _province_map.MAP_UNIT_SCALE
	for g in groups:
		if map_size.x > 0.0 and map_size.y > 0.0:
			if g.half_w * 2.0 <= map_size.x:
				g.pos.x = clampf(g.pos.x, g.half_w, map_size.x - g.half_w)
			if g.half_h * 2.0 <= map_size.y:
				g.pos.y = clampf(g.pos.y, g.half_h, map_size.y - g.half_h)
		g["anchor"] = _centroid_anchor(g.pos, g.layout, g.cell)
		_groups.append(g)

	queue_redraw()

## Bir ilin çizim grubu: her vekil ayrı pul.
func _make_group(province_id: String, colors: Array) -> Dictionary:
	var radius := dot_radius * DETAIL_SCALE
	var cell := radius * 2.0 + dot_spacing
	var dots: Array = colors
	var layout := _get_dot_layout(dots.size())
	var max_cols := 0
	for c in layout:
		max_cols = max(max_cols, c)
	var center: Vector2 = _seat_centers.get(province_id, _province_map.get_province_centroid(province_id))
	return {"pos": center, "layout": layout, "colors": dots, "radius": radius, "cell": cell,
		"half_w": max_cols * cell * 0.5, "half_h": layout.size() * cell * 0.5}

## Grubun "çapası": öyle bir nokta ki, ızgara oradan kurulduğunda noktaların
## GERÇEK AĞIRLIK MERKEZİ tam olarak istenen `center`a düşsün. Son satır
## genelde eksik dolduğu için (bkz. _get_dot_layout) bounding-box merkezi ile
## ağırlık merkezi aynı değildir; kullanıcı isteği "konum her zaman tüm
## vekillerin tam ortası olsun" olduğu için farkı burada telafi ediyoruz.
func _centroid_anchor(center: Vector2, layout: Array, cell: float) -> Vector2:
	var rows := layout.size()
	var sum := Vector2.ZERO
	var total := 0
	for row in rows:
		var cols: int = layout[row]
		for col in cols:
			sum += Vector2(col - (cols - 1) * 0.5, row - (rows - 1) * 0.5) * cell
			total += 1
	if total == 0:
		return center
	return center - sum / float(total)

## Vekiller DAİRE olarak çiziliyor: önce biraz daha büyük koyu bir daire (kontur),
## üstüne parti renginde asıl daire (eksen_projeksiyon'daki stroke="#1c1e21" karşılığı).
##
## PİKSEL IZGARASI (bu fonksiyonun asıl işi): harita kesirli bir ölçekle
## (fit_scale, ör. 0.678) büyütülüyor. Nokta konumları harita biriminde
## hesaplanıp sonra tek tek ekran pikseline yuvarlanırsa, matematiksel olarak
## EŞİT aralıklı noktalar ekranda eşit aralıklı ÇIKMAZ (ör. adımlar
## 10,10,9,10,10 olur) — "bazı noktalar arası boşluk bir iki piksel farklı"
## şikayetinin sebebi buydu. Burada bunun yerine tüm ızgara doğrudan TAM SAYI
## piksel adımlarıyla kuruluyor: bir kez grup çapası yuvarlanıyor, sonra her
## satır/sütun sabit `step_px` tam sayı adımıyla ilerliyor. Böylece hem yatay
## hem dikey tüm boşluklar birbirinin AYNISI oluyor. Ayrıca `step_px`,
## konturlu kareler arasında en az `min_screen_gap_px` gerçek piksel boşluk
## kalacak şekilde taban değerle sınırlanıyor (bkz. min_screen_gap_px notu).
func _draw() -> void:
	if _groups.is_empty():
		return
	# GERÇEK ekran pikseli: düğümün kendi global dönüşümü, projenin
	# "canvas_items" esnetme ölçeğini İÇERMİYOR. Pencere temel çözünürlükten
	# farklı boyuttayken bu kesirli ölçek yüzünden "tam piksele hizalı" sanılan
	# kareler gerçekte piksel sınırlarına farklı düşüyor, bazı karelerin
	# konturu kalın bazılarınınki ince görünüyordu. Viewport'un nihai
	# (esnetme) dönüşümünü de katınca hizalama gerçek piksellerde yapılıyor.
	var xform := get_viewport().get_final_transform() * get_global_transform_with_canvas()
	var scale: float = maxf(0.0001, xform.get_scale().x)
	var inv := xform.affine_inverse()

	var shader_material: ShaderMaterial = null
	for g in _groups:
		var radius: float = g["radius"]
		var cell: float = g["cell"]
		var dot_half_px: int = maxi(1, int(roundf(radius * scale)))
		# Kontur kalınlığı AYRI yuvarlanıyor (ölçeğe göre 1 piksel oynamasın).
		var outline_half_px: int = dot_half_px + maxi(1, int(roundf(dot_outline_width * scale)))
		var step_px: int = maxi(outline_half_px * 2 + min_screen_gap_px, int(roundf(cell * scale)))
		if shader_material != null:
			shader_material.set_shader_parameter("outline_color", dot_outline_color)
			shader_material.set_shader_parameter("inner_ratio", float(dot_half_px) / float(outline_half_px))
		var alpha := 1.0
		var layout: Array = g["layout"]
		var colors: Array = g["colors"]
		var rows: int = layout.size()
		var anchor_px: Vector2 = (xform * g["anchor"]).round()
		var first_row_dy: int = int(roundf(-(rows - 1) * 0.5 * cell * scale))
		var idx := 0
		for row in rows:
			var cols: int = layout[row]
			var y_px: float = anchor_px.y + first_row_dy + row * step_px
			var x0_px: float = anchor_px.x + roundf(-(cols - 1) * 0.5 * cell * scale)
			for col in cols:
				if idx >= colors.size():
					break
				var color: Color = colors[idx]
				var center_px := Vector2(x0_px + col * step_px, y_px)
				_draw_pawn(inv, scale, center_px, outline_half_px, color, alpha)
				idx += 1

## VEKİL PULU (0.0.274, konsept "krem kenarlı"): içi parti renginde dolu, krem halkalı;
## (0.0.266: krem pul, parti renginin koyusunda kenar,
## altında ahşap rengi sert gölge ve hafif yumuşak gölge. 0.0.267: dört
## yumuşatılmış daire yerine pul başına TEK dörtgen; katmanları PAWN_SHADER
## çizer (harita kayarken her karede yüzlerce daire çizmek kareyi 30-50 ms
## uzatıyordu).
const PAWN_LIP := 0.24
const PAWN_SHADER := """
shader_type canvas_item;
float disc(vec2 p, vec2 c, float aa) {
	return clamp((1.0 - length(p - c)) / aa + 0.5, 0.0, 1.0);
}
void fragment() {
	// UV -> pul yarıçapı birimi; merkez (0,0), dörtgen alta gölge kadar uzun.
	vec2 p = vec2(UV.x * 2.0 - 1.0, UV.y * (2.0 + 1.6 * %f) - 1.0);
	float aa = max(fwidth(p.x), 0.0001);
	// 0.0.274 KREM KENARLI DOLU PUL: altta parti renginin koyusu kalınlık,
	// krem halka, içi partinin renginde dolu.
	vec4 col = vec4(0.0, 0.0, 0.0, 0.16 * disc(p, vec2(0.0, 1.6 * %f), aa));
	col = mix(col, vec4(COLOR.rgb * 0.5, 1.0), disc(p, vec2(0.0, %f), aa));
	col = mix(col, vec4(1.0, 0.98, 0.941, 1.0), disc(p, vec2(0.0), aa));
	col = mix(col, vec4(COLOR.rgb, 1.0), disc(p / 0.82, vec2(0.0), aa / 0.82));
	COLOR = vec4(col.rgb, col.a * COLOR.a);
}
""" % [PAWN_LIP, PAWN_LIP, PAWN_LIP]

func _draw_pawn(inv: Transform2D, screen_scale: float, center_px: Vector2, half_px: int, color: Color, alpha: float) -> void:
	var c: Vector2 = inv * center_px
	var r := float(half_px) / screen_scale
	draw_texture_rect(_white_texture, Rect2(c - Vector2(r, r), Vector2(2.0 * r, r * (2.0 + 1.6 * PAWN_LIP))),
		false, Color(color, alpha))

## Ekran piksel uzayında (tam sayı merkez, tam sayı yarıçap) antialiased daire;
## yerel uzaya geri çevrilerek çizilir. Bütün dairelerin merkezi ve yarıçapı
## ekranda aynı tam sayılara oturduğu için kenar yumuşatması her birinde birebir
## aynı görünür; adım konturlu çapın üstünde olduğundan daireler değmez.
func _draw_circle_at_screen_px(inv: Transform2D, screen_scale: float, center_px: Vector2, half_px: int, color: Color) -> void:
	var half_local := float(half_px) / screen_scale
	var center: Vector2 = inv * center_px
	draw_texture_rect(_white_texture, Rect2(center - Vector2(half_local, half_local), Vector2(half_local, half_local) * 2.0),
		false, color)
