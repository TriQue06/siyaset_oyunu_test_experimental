class_name AxisVisual
extends RefCounted
## Eksen değerlerinin (-3..+3) görselini üretir.
##
## ŞİMDİLİK: her eksen/değer kombinasyonu için 7 renkli hücreden oluşan basit
## bir "sallamasyon" şerit çiziyoruz (gerçek görsel yok).
##
## SEN PIXEL ART PNG'LERİ HAZIRLAYINCA: sadece get_axis_texture()'ın içini
## aşağıdaki gibi değiştirmen yeterli, dışarıdan çağıran hiçbir kod
## değişmeyecek:
##
##   static func get_axis_texture(axis: String, value: int) -> Texture2D:
##       return load("res://assets/axis/%s_%d.png" % [axis, value])
##
## (örn. dosya adları: economic_-3.png, economic_-2.png, ..., economic_3.png,
## aynı şekilde social_*.png ve administrative_*.png — 3 eksen x 7 değer = 21 PNG)

const IMG_SIZE := Vector2i(154, 22)
const CELL_GAP := 2

static func get_axis_texture(axis: String, value: int) -> Texture2D:
	var image := Image.create(IMG_SIZE.x, IMG_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	var cell_count := IdeologyAxes.AXIS_MAX - IdeologyAxes.AXIS_MIN + 1  # 7 (-3..3)
	var cell_w := float(IMG_SIZE.x - CELL_GAP * (cell_count - 1)) / cell_count
	var active_idx: int = clampi(value - IdeologyAxes.AXIS_MIN, 0, cell_count - 1)

	for i in cell_count:
		var x := int(i * (cell_w + CELL_GAP))
		var rect := Rect2i(x, 0, int(cell_w), IMG_SIZE.y)
		var color: Color
		if i == active_idx:
			color = Color(1.0, 0.82, 0.2, 1.0)
		elif i == cell_count / 2:
			color = Color(1, 1, 1, 0.28)  # nötr (0) işareti hafif belirgin
		else:
			color = Color(1, 1, 1, 0.12)
		image.fill_rect(rect, color)

	return ImageTexture.create_from_image(image)
