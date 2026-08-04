extends CanvasLayer
## Autoload. Sahneler arası geçişte ekranı karartıp yeni sahneyi o karanlıkken
## açan, sonra tekrar aydınlatan basit fade efekti. Sahneden bağımsız
## (autoload) yaşadığı için her yerden çağrılabilir.

const FADE_DURATION := 0.4

@onready var fade_rect: ColorRect = %FadeRect

func _ready() -> void:
	layer = 200  # SettingsOverlay'in (100) bile üstünde kalsın
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

## Ekranı karartır, sahneyi değiştirir, tekrar aydınlatır.
func fade_to_scene(path: String, duration: float = FADE_DURATION) -> void:
	fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var out_tween := create_tween()
	out_tween.tween_property(fade_rect, "color:a", 1.0, duration)
	await out_tween.finished

	get_tree().change_scene_to_file(path)
	await get_tree().process_frame

	var in_tween := create_tween()
	in_tween.tween_property(fade_rect, "color:a", 0.0, duration)
	await in_tween.finished
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
