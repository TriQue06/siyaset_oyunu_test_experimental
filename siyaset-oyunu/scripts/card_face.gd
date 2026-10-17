class_name CardFace
extends Control
## KART YÜZÜ: kart dokusunun bej gövdesinin üstüne kart türünün renginde bir
## zemin ve büyük, vektörle çizilen bir SİMGE koyar. Simge kartın SOL yarısında
## durur: el kalabalıkken kartlar üst üste bindiğinde her kartın görünen
## şeridinde simgesi ve bedeli kalır, kart başlık okunmadan da tanınır.
## Renk kartın türünü söyler: saldırı (kırmızı), destek (altın), para (yeşil),
## kart (mor), vekil (turuncu).

var card_type: String = ""

const KIND_COLORS := {
	"attack": Color("#c8434f"),
	"boost": Color("#e0a72e"),
	"money": Color("#3fa36b"),
	"cards": Color("#8a63d2"),
	"seats": Color("#e0723a"),
}

static func kind_of(card_type: String) -> String:
	match card_type:
		"karalama", "kaset", "isyan", "parti_ici_karisiklik":
			return "attack"
		"populizm":
			return "boost"
		"bagis_kampanyasi", "bagis_kampanyasi_guclu", "para_cezasi":
			return "money"
		"esnek_hareket", "kart_calma":
			return "cards"
	if card_type.begins_with("steal_"):
		return "seats"
	return "boost"

static func color_of(card_type: String) -> Color:
	return KIND_COLORS.get(kind_of(card_type), Color("#8a8aa8"))

func _draw() -> void:
	if card_type == "" or size.x <= 0.0:
		return
	var color := color_of(card_type)
	var body := Rect2(Vector2.ZERO, size)
	draw_rect(body, color.darkened(0.55), true)
	# Hafif dikey ışık: üst açık, alt koyu (düz, pikselli kimlikle uyumlu iki ton).
	draw_rect(Rect2(0, 0, size.x, size.y * 0.45), Color(color.darkened(0.35), 0.9), true)
	draw_rect(body, color.darkened(0.15), false, 2.0)
	var s := minf(size.y * 0.34, size.x * 0.3)
	var c := Vector2(s * 1.25 + 4.0, size.y * 0.5)
	draw_circle(c, s * 1.15, Color(color, 0.25))
	draw_emblem(self, card_type, c, s, color.lightened(0.55))

## Kart türünün simgesi (merkez c, yarı boy s).
static func draw_emblem(canvas: CanvasItem, card_type: String, c: Vector2, s: float, ink: Color) -> void:
	var w := maxf(1.5, s * 0.16)
	var dark := Color(0, 0, 0, 0.35)
	match card_type:
		"karalama":
			# Megafon: gövde üçgen + ağız + ses dalgası.
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.8, -s * 0.25), c + Vector2(s * 0.35, -s * 0.75),
				c + Vector2(s * 0.35, s * 0.75), c + Vector2(-s * 0.8, s * 0.25)]), ink)
			canvas.draw_rect(Rect2(c + Vector2(-s * 0.95, -s * 0.28), Vector2(s * 0.25, s * 0.56)), ink, true)
			canvas.draw_arc(c + Vector2(s * 0.35, 0), s * 0.5, -PI * 0.3, PI * 0.3, 10, ink, w, true)
			canvas.draw_arc(c + Vector2(s * 0.35, 0), s * 0.85, -PI * 0.3, PI * 0.3, 12, ink, w, true)
		"kaset":
			# Kaset: gövde, iki makara, bant penceresi.
			canvas.draw_rect(Rect2(c + Vector2(-s, -s * 0.62), Vector2(s * 2.0, s * 1.24)), ink, true)
			canvas.draw_rect(Rect2(c + Vector2(-s * 0.7, -s * 0.38), Vector2(s * 1.4, s * 0.5)), dark, true)
			canvas.draw_circle(c + Vector2(-s * 0.4, -s * 0.13), s * 0.18, ink)
			canvas.draw_circle(c + Vector2(s * 0.4, -s * 0.13), s * 0.18, ink)
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.55, s * 0.62), c + Vector2(-s * 0.4, s * 0.32),
				c + Vector2(s * 0.4, s * 0.32), c + Vector2(s * 0.55, s * 0.62)]), dark)
		"isyan":
			# Şimşek: parti içindeki çatlak.
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.15, -s), c + Vector2(-s * 0.55, s * 0.1),
				c + Vector2(-s * 0.05, s * 0.1), c + Vector2(-s * 0.25, s), c + Vector2(s * 0.55, -s * 0.15),
				c + Vector2(s * 0.05, -s * 0.15)]), ink)
		"populizm":
			# Yıldız.
			var pts := PackedVector2Array()
			for i in 10:
				var r := s if i % 2 == 0 else s * 0.42
				var a := -PI / 2.0 + PI * float(i) / 5.0
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			canvas.draw_colored_polygon(pts, ink)
		"bagis_kampanyasi", "bagis_kampanyasi_guclu":
			# Madeni para yığını (güçlüde üç para).
			var count := 3 if card_type.ends_with("guclu") else 2
			for i in count:
				var y := s * 0.55 - float(i) * s * 0.42
				canvas.draw_rect(Rect2(c + Vector2(-s * 0.75, y - s * 0.12), Vector2(s * 1.5, s * 0.3)), ink, true)
				canvas.draw_line(c + Vector2(-s * 0.75, y + s * 0.18), c + Vector2(s * 0.75, y + s * 0.18), dark, w * 0.8, true)
			canvas.draw_circle(c + Vector2(0, -s * 0.55), s * 0.38, ink)
			canvas.draw_circle(c + Vector2(0, -s * 0.55), s * 0.2, dark)
		"esnek_hareket":
			# İki kart + artı (iki kat hamle).
			canvas.draw_rect(Rect2(c + Vector2(-s * 0.85, -s * 0.7), Vector2(s * 0.95, s * 1.3)), Color(ink, 0.55), true)
			canvas.draw_rect(Rect2(c + Vector2(-s * 0.45, -s * 0.5), Vector2(s * 0.95, s * 1.3)), ink, true)
			canvas.draw_line(c + Vector2(s * 0.03, s * 0.15), c + Vector2(s * 0.03, -s * 0.15) + Vector2(0, -s * 0.0), dark, w, true)
			canvas.draw_line(c + Vector2(-s * 0.15, 0), c + Vector2(s * 0.21, 0), dark, w, true)
			canvas.draw_line(c + Vector2(s * 0.03, -s * 0.18), c + Vector2(s * 0.03, s * 0.18), dark, w, true)
		"kart_calma":
			# Kart + kapan el oku.
			canvas.draw_rect(Rect2(c + Vector2(-s * 0.2, -s * 0.75), Vector2(s * 0.95, s * 1.3)), ink, true)
			canvas.draw_line(c + Vector2(-s * 1.0, s * 0.55), c + Vector2(-s * 0.05, s * 0.55), ink, w * 1.4, true)
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 1.05, s * 0.55), c + Vector2(-s * 0.7, s * 0.25),
				c + Vector2(-s * 0.7, s * 0.85)]), ink)
		_:
			if card_type.begins_with("steal_"):
				# Vekil silüeti + çeken ok.
				canvas.draw_circle(c + Vector2(s * 0.3, -s * 0.5), s * 0.3, ink)
				canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.15, s * 0.75), c + Vector2(-s * 0.05, -s * 0.1),
					c + Vector2(s * 0.65, -s * 0.1), c + Vector2(s * 0.75, s * 0.75)]), ink)
				canvas.draw_line(c + Vector2(-s * 1.0, s * 0.2), c + Vector2(-s * 0.35, s * 0.2), ink, w * 1.3, true)
				canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 1.05, s * 0.2), c + Vector2(-s * 0.72, -s * 0.08),
					c + Vector2(-s * 0.72, s * 0.48)]), ink)
				if card_type == "steal_strong":
					canvas.draw_circle(c + Vector2(-s * 0.55, -s * 0.6), s * 0.18, ink)
			else:
				canvas.draw_circle(c, s * 0.6, ink)
