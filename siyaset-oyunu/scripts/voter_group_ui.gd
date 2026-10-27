class_name VoterGroupUI
extends RefCounted
## Seçmen gruplarının ORTAK arayüz parçaları (il paneli, parti kartı ve yasa
## ekranları aynı görsel dili kullansın). Grup adı her yerde TAM
## yazılır (kısaltma yok, gerekirse yazı küçülür); renk her zaman simge ve
## metinle birlikte kullanılır.

const FS_NAME := 13
const FS_VALUE := 15
## 0.0.186: karo simgeler ve yüzdeler büyüdü (eskiden 16 px simge, 11 px yazı).
const ICON_SIZE := 24.0
const BAR_HEIGHT := 9.0

## [simge] Grup adı ............ değer   (adın rengi grubun rengi, açık tonda)
static func name_row(group: String, value_text: String = "", value_color: Color = UiTheme.TEXT,
		font_size: int = FS_NAME, icon_size: float = ICON_SIZE, words: bool = false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := VoterGroupIcon.make(group, icon_size)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var name := PopupKit.label(VoterGroups.title(group), font_size, VoterGroups.color(group).darkened(0.3))
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.clip_text = false
	name.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(name)
	if value_text != "":
		# Sayılar mono (hizalı), nitel sözcükler normal yazı tipiyle.
		var value: Label = PopupKit.label(value_text, font_size + 1, value_color) if words 			else UiTheme.mono_label(value_text, font_size + 2, value_color, true)
		value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(value)
	return row

## Yatay dolum çubuğu (0..1), grubun renginde. marker: 0..1 arası ince çizgi (-1 yok).
static func bar(fill: float, color: Color, height: float = BAR_HEIGHT, extra: float = 0.0, extra_color: Color = Color.WHITE) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, height)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.draw.connect(func():
		var w := holder.size.x
		holder.draw_rect(Rect2(Vector2.ZERO, holder.size), UiTheme.SLOT, true)
		var f := clampf(fill, 0.0, 1.0)
		holder.draw_rect(Rect2(0, 0, w * f, holder.size.y), color, true)
		if extra > 0.0:
			var e := clampf(fill + extra, 0.0, 1.0)
			holder.draw_rect(Rect2(w * f, 0, w * (e - f), holder.size.y), extra_color, true)
		# Orta çizgi (50): nötrün yeri.
		holder.draw_line(Vector2(w * 0.5, 0), Vector2(w * 0.5, holder.size.y), Color(0, 0, 0, 0.45), 1.0))
	return holder

## Partinin bir gruptaki ULUSAL desteği: ad + değer satırı, altında çubuk.
static func affinity_row(group: String, value: float, delta: float = 0.0) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Değer: destek oranı; değişim sadece yön oku (büyüklüğü ipucunda).
	var text := VoterGroups.percent_text(value)
	if absf(delta) >= 0.5:
		text += " " + ("+" if delta > 0.0 else "−")
	box.add_child(name_row(group, text, UiTheme.TEXT))
	box.add_child(bar(value / 100.0, VoterGroups.color(group), BAR_HEIGHT))
	return box

## İl profilinde bir ÇİFT: üstte ilk grup ve yüzdesi, ortada iki renkli
## çubuk (toplam %100), altta ikinci grup ve yüzdesi.
static func pair_rows(pair: String, profile: Dictionary) -> Control:
	var groups: Array = VoterGroups.PAIRS[pair]
	var a := String(groups[0])
	var b := String(groups[1])
	var pa := VoterGroups.percent(profile, a)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_row(a, L.t("%%%d") % pa, UiTheme.TEXT))
	var split := Control.new()
	split.custom_minimum_size = Vector2(0, BAR_HEIGHT + 1.0)
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.mouse_filter = Control.MOUSE_FILTER_IGNORE
	split.draw.connect(func():
		var w := split.size.x
		var cut := w * float(pa) / 100.0
		split.draw_rect(Rect2(0, 0, cut, split.size.y), VoterGroups.color(a), true)
		split.draw_rect(Rect2(cut, 0, w - cut, split.size.y), VoterGroups.color(b), true)
		split.draw_line(Vector2(cut, -1), Vector2(cut, split.size.y + 1), UiTheme.INK, 2.0))
	box.add_child(split)
	box.add_child(name_row(b, L.t("%%%d") % (100 - pa), UiTheme.TEXT))
	return box

## Etki satırı (önizlemeler için): [simge] Grup adı   hafif artış / orta kayıp
static func effect_row(group: String, amount: float, font_size: int = FS_NAME) -> Control:
	var color := UiTheme.GREEN if amount > 0.0 else UiTheme.RED
	var text := "%s %s" % [EffectWords.adjective(amount, "group"), L.t("artış") if amount > 0.0 else L.t("kayıp")]
	# İki satır: grup adı tam, altında sağa yaslı etki (uzun çeviri paneli genişletmesin).
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_row(group, "", color, font_size, 20.0))
	var value := PopupKit.label(text, font_size, color)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.custom_minimum_size = Vector2(80, 0)
	box.add_child(value)
	return box
