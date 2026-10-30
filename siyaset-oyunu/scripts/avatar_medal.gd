class_name AvatarMedal
extends Control
## AVATAR MADALYONU (0.0.302, konsept A "Logonun yerine avatar", bkz.
## konseptler/avatar_yerlesim_konseptleri.html): siyasetçinin avatarı parti
## renginde halkalı yuvarlak madalyonun içinde (yuvarlak kırpılır, alttan
## taşar gibi oturur); partinin logosu sağ altta küçük pul. Parti listesi,
## üst banttaki sıra kartı, hükümet paneli ve puan tablosunda logonun yerini alır.

## Logo pulunun madalyona oranı (konsept 20/44; 0.0.302 isteği: bir iki px büyük).
const BADGE_RATIO := 0.52
## Halka kalınlığı ve alt kalınlık (konsept: inset 3 px, alt gölge 3 px).
const RING := 3.0
const LIP := 3.0
## Avatar tuvalinin madalyona oranı (yüz çizimi tuvalin ~%58'i).
const FACE_ZOOM := 1.2

var _color := Color.GRAY

## politician: PoliticianPresets verisi; party: PartyManager.data_of(...).
static func make(politician: Dictionary, party: Dictionary, side: float, with_badge: bool = true) -> AvatarMedal:
	var medal := AvatarMedal.new()
	medal._build(politician, party, side, with_badge)
	return medal

func _build(politician: Dictionary, party: Dictionary, side: float, with_badge: bool) -> void:
	_color = party.get("bg_color", Color.GRAY)
	# Siyasetçi verisi yoksa (eski kayıt, test) yüz parti adından üretilir.
	if String(politician.get("name", "")) == "" and not politician.has("appearance"):
		politician = {"name": String(party.get("name", "?")), "gender": "m", "portrait": ""}
	custom_minimum_size = Vector2(side, side)
	size = Vector2(side, side)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Yuvarlak maske: zemin dairesi çizilir, avatar bu dairenin içine kırpılır.
	var mask := _Mask.new()
	mask.color = _color
	mask.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(mask)
	# Konsept: yüz madalyonu doldurur, omuzlar alttan taşar. Avatar çiziminin
	# kenarlarında boşluk var: tuval madalyondan büyük tutulur, baş üste oturur.
	var canvas := side * FACE_ZOOM
	var face := PoliticianPortrait.make(politician, _color, canvas)
	face.position = Vector2((side - canvas) * 0.5, side * 0.1 - canvas * 0.115)
	face.size = Vector2(canvas, canvas)
	mask.add_child(face)
	# Ağaca girmeden verilen boyut "resized" yaymaz: avatar katmanları elle yerleşir.
	face.call_deferred("_layout_avatar")
	var ring := _Ring.new()
	ring.color = _color
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(ring)
	if with_badge and not party.is_empty():
		var b := roundf(side * BADGE_RATIO)
		var holder := _BadgeHolder.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.size = Vector2(b, b)
		holder.position = Vector2(side - b + side * 0.09, side - b + side * 0.07)
		add_child(holder)
		var badge := PartyBadge.build(party, Vector2(b, b), 64)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(badge)

func _draw() -> void:
	# Alt kalınlık: madalyonun altında parti renginin koyusu.
	var r := minf(size.x, size.y) * 0.5
	draw_circle(size * 0.5 + Vector2(0, LIP), r, _color.lerp(Color.BLACK, 0.5), true, -1.0, true)

class _Mask extends Control:
	var color := Color.GRAY
	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		var c := size * 0.5
		# Konsept: açık (üstte) → orta tonda radyal zemin.
		draw_circle(c, r, color.lerp(Color.WHITE, 0.45), true, -1.0, true)
		draw_circle(c - Vector2(0, r * 0.3), r * 0.62, Color(color.lerp(Color.WHITE, 0.75), 0.6), true, -1.0, true)

class _Ring extends Control:
	var color := Color.GRAY
	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		draw_arc(size * 0.5, r - AvatarMedal.RING * 0.5, 0.0, TAU, 48, color, AvatarMedal.RING, true)

## Logonun çevresinde kart renginde ince boşluk (konsept: 0 0 0 2px var(--card)).
class _BadgeHolder extends Control:
	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		draw_circle(size * 0.5, r + 2.0, Color("fffaf0"), true, -1.0, true)
