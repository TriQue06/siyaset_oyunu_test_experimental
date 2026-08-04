extends Node2D
## Pixel-art il haritası: görsel katman + görünmez id-map katmanından
## il tespiti (tıklama/hover) ve il boyama (parti rengiyle overlay).
##
## Kaynak PNG'ler düşük çözünürlükte (örn. 48x48) hazırlanır; bu script
## onları "upscale_factor" oranında (varsayılan 5 => 240x240) nearest-neighbor
## ile CPU tarafında büyütür. Böylece görsel katman, id-map ve bu node'un
## local koordinat uzayı (tıklama/centroid hesapları dahil) TEK bir pixel
## ızgarasında hizalı kalır — ayrı node scale'leriyle uğraşmaya gerek kalmaz.
##
## id-map formatı: her il düz bir renkle doldurulur (kaynak, küçük çözünürlükte).
## province_id = round(r*255) + round(g*255)*256   (b ve alpha kullanılmaz)
## id 0 (siyah/şeffaf) = "il değil" (deniz, sınır boşluğu vb.)

signal province_clicked(province_id: int)
signal province_hovered(province_id: int)  # -1 = hover boşa çıktı

@export var upscale_factor: int = 5

@export var visual_texture: Texture2D:
	set(value):
		visual_texture = value
		if is_inside_tree():
			_apply_visual_texture()

@export var id_map_texture: Texture2D:
	set(value):
		id_map_texture = value
		if is_inside_tree():
			_load_id_map()

var _id_image: Image
var _overlay_image: Image
var _overlay_texture: ImageTexture
var _last_hovered_id: int = -1
# province_id -> Vector2 (bu node'un local piksel uzayında ağırlık merkezi)
var _centroids: Dictionary = {}

@onready var visual_sprite: Sprite2D = $Visual
@onready var overlay_sprite: Sprite2D = $Overlay

func _ready() -> void:
	_apply_visual_texture()
	_load_id_map()
	set_process_unhandled_input(true)

func _upscaled_image(tex: Texture2D) -> Image:
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	if upscale_factor != 1:
		img.resize(img.get_width() * upscale_factor, img.get_height() * upscale_factor, Image.INTERPOLATE_NEAREST)
	return img

func _apply_visual_texture() -> void:
	if not visual_sprite:
		return
	visual_sprite.centered = false
	overlay_sprite.centered = false
	visual_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	overlay_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if visual_texture == null:
		visual_sprite.texture = null
		return
	var img := _upscaled_image(visual_texture)
	visual_sprite.texture = ImageTexture.create_from_image(img)

func _load_id_map() -> void:
	if id_map_texture == null:
		_id_image = null
		return
	_id_image = _upscaled_image(id_map_texture)
	# Overlay boş şeffaf başlar, boyanmış iller burada tutulur.
	_overlay_image = Image.create(_id_image.get_width(), _id_image.get_height(), false, Image.FORMAT_RGBA8)
	_overlay_image.fill(Color(0, 0, 0, 0))
	_overlay_texture = ImageTexture.create_from_image(_overlay_image)
	overlay_sprite.texture = _overlay_texture
	_compute_centroids()

func _compute_centroids() -> void:
	_centroids.clear()
	var sums: Dictionary = {}   # id -> Vector2 (piksel koordinat toplamı)
	var counts: Dictionary = {} # id -> piksel sayısı
	var w := _id_image.get_width()
	var h := _id_image.get_height()
	for y in h:
		for x in w:
			var pid := _decode_province_id(_id_image.get_pixel(x, y))
			if pid == 0:
				continue
			sums[pid] = sums.get(pid, Vector2.ZERO) + Vector2(x + 0.5, y + 0.5)
			counts[pid] = counts.get(pid, 0) + 1
	for pid in sums.keys():
		_centroids[pid] = sums[pid] / counts[pid]

## Bu node'un LOCAL koordinatında bir nokta (px,py — büyütülmüş uzayda).
## Karşılık gelen il id'sini döner (yoksa 0).
func get_province_id_at(local_pos: Vector2) -> int:
	if _id_image == null:
		return 0
	var x := int(local_pos.x)
	var y := int(local_pos.y)
	if x < 0 or y < 0 or x >= _id_image.get_width() or y >= _id_image.get_height():
		return 0
	var c := _id_image.get_pixel(x, y)
	return _decode_province_id(c)

func _decode_province_id(c: Color) -> int:
	var r := int(round(c.r * 255.0))
	var g := int(round(c.g * 255.0))
	return r + g * 256

func _unhandled_input(event: InputEvent) -> void:
	if _id_image == null:
		return
	if event is InputEventMouseMotion:
		var local := to_local(event.global_position)
		var pid := get_province_id_at(local)
		if pid != _last_hovered_id:
			_last_hovered_id = pid
			province_hovered.emit(pid)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local := to_local(event.global_position)
		var pid := get_province_id_at(local)
		if pid != 0:
			province_clicked.emit(pid)

## Bir ili verilen renkle (alpha dahil) boyar. color.a = 0 verirsen o il temizlenir.
func set_province_color(province_id: int, color: Color) -> void:
	if _id_image == null:
		return
	var w := _id_image.get_width()
	var h := _id_image.get_height()
	for y in h:
		for x in w:
			if _decode_province_id(_id_image.get_pixel(x, y)) == province_id:
				_overlay_image.set_pixel(x, y, color)
	_overlay_texture.update(_overlay_image)

## Tüm boyamaları temizler.
func clear_overlay() -> void:
	if _overlay_image == null:
		return
	_overlay_image.fill(Color(0, 0, 0, 0))
	_overlay_texture.update(_overlay_image)

## Birden fazla ili tek seferde boyayıp texture'ı bir kez günceller (performans için).
func set_province_colors(province_to_color: Dictionary) -> void:
	if _id_image == null:
		return
	var w := _id_image.get_width()
	var h := _id_image.get_height()
	for y in h:
		for x in w:
			var pid := _decode_province_id(_id_image.get_pixel(x, y))
			if province_to_color.has(pid):
				_overlay_image.set_pixel(x, y, province_to_color[pid])
	_overlay_texture.update(_overlay_image)

## İlin (bu node'un local piksel uzayındaki) ağırlık merkezini döner.
## SeatMarkers gibi Map'in çocuğu olan node'lar bu koordinatı doğrudan kullanabilir.
func get_province_centroid(province_id: int) -> Vector2:
	return _centroids.get(province_id, Vector2.ZERO)

func get_all_province_ids() -> Array:
	return _centroids.keys()
