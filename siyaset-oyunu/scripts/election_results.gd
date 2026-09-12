extends Control
## Seçim yapılınca (CardManager.election_completed) GameScreen'den
## fade ile buraya geçilir: her partinin çubuk grafiği birkaç kez rastgele
## artıp azalır, sonra gerçek oy oranına "oturur". Kısa bir bekleme sonrası
## otomatik olarak GameScreen'e geri fade ile dönülür.

const MAX_BAR_HEIGHT := 320.0
const BAR_WIDTH := 90.0
const STEP_DURATION := 0.22
const RANDOM_STEPS := 4
const FINAL_DURATION := 0.45
const HOLD_AFTER := 1.5

@onready var chart_area: HBoxContainer = %ChartArea
@onready var title_label: Label = %TitleLabel

func _ready() -> void:
	title_label.text = "%s Sonuçları — %d. Tur" % [
		"Erken Seçim" if CardManager.last_election_was_early else "Seçim",
		maxi(1, CardManager.last_election_round),
	]

	var entries := _build_sorted_entries()
	var columns: Array = []
	for e in entries:
		var col := _build_column(e)
		chart_area.add_child(col["wrapper"])
		columns.append(col)

	for col in columns:
		_animate_column(col["bar"], col["percent_label"], col["target_percent"]) # fire-and-forget, hepsi paralel

	var total_anim_time: float = RANDOM_STEPS * STEP_DURATION + FINAL_DURATION
	await get_tree().create_timer(total_anim_time + HOLD_AFTER).timeout
	SceneTransition.fade_to_scene("res://scenes/GameScreen.tscn")

func _build_sorted_entries() -> Array:
	var ids: Array = CardManager.last_vote_shares.keys()
	ids.sort_custom(func(a, b): return CardManager.last_vote_shares[a] > CardManager.last_vote_shares[b])
	var entries: Array = []
	for peer_id in ids:
		var party: Dictionary = PartyManager.parties.get(peer_id, {})
		var pname: String = party.get("name", MultiplayerManager.players.get(peer_id, {}).get("name", "?"))
		entries.append({
			"name": pname,
			"color": party.get("bg_color", Color(0.5, 0.5, 0.5)),
			"percent": CardManager.last_vote_shares[peer_id],
			"seats": CardManager.last_seats.get(peer_id, 0),
			"below_threshold": not CardManager.passed_threshold.has(peer_id),
		})
	return entries

func _build_column(entry: Dictionary) -> Dictionary:
	var wrapper := VBoxContainer.new()
	wrapper.custom_minimum_size = Vector2(BAR_WIDTH, 0)
	wrapper.alignment = BoxContainer.ALIGNMENT_END
	wrapper.add_theme_constant_override("separation", 6)

	var percent_label := Label.new()
	percent_label.text = "%0.0f" % 0.0
	percent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrapper.add_child(percent_label)

	var bar_area := Control.new()
	bar_area.custom_minimum_size = Vector2(BAR_WIDTH, MAX_BAR_HEIGHT)
	wrapper.add_child(bar_area)

	var bar := ColorRect.new()
	bar.color = entry["color"]
	bar.size = Vector2(BAR_WIDTH, 0)
	bar.position = Vector2(0, MAX_BAR_HEIGHT)
	bar_area.add_child(bar)

	var name_label := Label.new()
	name_label.text = entry["name"]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	wrapper.add_child(name_label)

	var seats_label := Label.new()
	seats_label.text = "%d sandalye%s" % [entry["seats"], " (baraj altı)" if entry["below_threshold"] else ""]
	seats_label.add_theme_font_size_override("font_size", 11)
	seats_label.modulate.a = 0.7
	seats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrapper.add_child(seats_label)

	return {"wrapper": wrapper, "bar": bar, "percent_label": percent_label, "target_percent": entry["percent"]}

func _animate_column(bar: ColorRect, percent_label: Label, target_percent: float) -> void:
	var target_height: float = (target_percent / 100.0) * MAX_BAR_HEIGHT
	for i in RANDOM_STEPS:
		var random_h: float = randf_range(0.1, 1.0) * MAX_BAR_HEIGHT
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(bar, "size:y", random_h, STEP_DURATION)
		tw.parallel().tween_property(bar, "position:y", MAX_BAR_HEIGHT - random_h, STEP_DURATION)
		percent_label.text = "%%%.0f" % (random_h / MAX_BAR_HEIGHT * 100.0)
		await tw.finished
	var final_tw := create_tween()
	final_tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	final_tw.tween_property(bar, "size:y", target_height, FINAL_DURATION)
	final_tw.parallel().tween_property(bar, "position:y", MAX_BAR_HEIGHT - target_height, FINAL_DURATION)
	await final_tw.finished
	percent_label.text = "%%%.1f" % target_percent
