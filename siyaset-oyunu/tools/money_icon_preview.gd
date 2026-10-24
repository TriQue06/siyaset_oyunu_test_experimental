extends SceneTree
## PARA SİMGESİ önizlemesi: yazı içi simge (farklı yazı tipi / punto / renk) ve
## tek başına CoinIcon. Görüntü user://money_icon.png.
##   godot --resolution 900x400 --path . --script res://tools/money_icon_preview.gd

func _initialize() -> void:
	await process_frame
	var bg := ColorRect.new()
	bg.color = Color("1a1530")
	bg.size = Vector2(900, 400)
	root.add_child(bg)
	var box := VBoxContainer.new()
	box.position = Vector2(20, 20)
	root.add_child(box)
	var ok := true
	for spec in [[11, false, Color.WHITE], [15, true, UiTheme.GOLD], [20, true, Color("31C440")], [26, false, Color.WHITE]]:
		var label := UiTheme.mono_label(L.t("%s milyon ¤") % "150" + "  ·  " + L.t("Parti kasası yetmiyor (%s gerekir).") % GameRules.cost_text(15.0), int(spec[0]), spec[2], bool(spec[1]))
		box.add_child(label)
		ok = ok and not label.text.contains("¤")
	var plain := Label.new()
	plain.text = L.t("%s milyon ¤") % "40" + " (varsayılan yazı tipi)"
	box.add_child(plain)
	var row := HBoxContainer.new()
	box.add_child(row)
	for c in [UiTheme.BLUE, UiTheme.GOLD, Color("31C440")]:
		row.add_child(CoinIcon.make(48, c))
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("user://money_icon.png")
	print("[OK] metinde para karakteri yok" if ok else "[HATA] metinde para karakteri kaldi")
	quit()
