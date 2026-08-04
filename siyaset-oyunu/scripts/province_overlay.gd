extends Node2D
## ProvinceMap'in çocuğu. Draws filled polygons per province on top of the
## SVG background, so parties can be shown "painted" over a province without
## touching the underlying vector artwork.

var polygons_by_province: Dictionary = {}  # province_id -> Array[PackedVector2Array]
var colors: Dictionary = {}                # province_id -> Color

func _draw() -> void:
	for province_id in colors.keys():
		if not polygons_by_province.has(province_id):
			continue
		var color: Color = colors[province_id]
		for polygon in polygons_by_province[province_id]:
			draw_colored_polygon(polygon, color)
