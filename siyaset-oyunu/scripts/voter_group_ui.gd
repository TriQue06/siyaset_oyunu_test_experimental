class_name VoterGroupUI
extends RefCounted
## Seçmen gruplarının ORTAK arayüz parçaları (il paneli, parti kartı, yasa ve
## toplantı ekranları aynı görsel dili kullansın). Grup adı her yerde TAM
## yazılır (kısaltma yok, gerekirse yazı küçülür); renk her zaman simge ve
## metinle birlikte kullanılır.

const FS_NAME := 11
const FS_VALUE := 12
const BAR_HEIGHT := 7.0

## [simge] Grup adı ............ değer   (adın rengi grubun rengi, açık tonda)
static func name_row(group: String, value_text: String = "", value_color: Color = UiTheme.TEXT,
		font_size: int = FS_NAME, icon_size: float = 16.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := VoterGroupIcon.make(group, icon_size)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var name := PopupKit.label(VoterGroups.title(group), font_size, VoterGroups.color(group).lightened(0.35))
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.clip_text = false
	name.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(name)
	if value_text != "":
		var value := UiTheme.mono_label(value_text, font_size + 1, value_color, true)
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
## bonus: geçici toplantı bonusu (çubukta açık renkle, metinde ayrıca).
static func affinity_row(group: String, value: float, bonus: float = 0.0, delta: float = 0.0) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var text := VoterGroups.percent_text(value)
	if bonus > 0.0:
		text += " +%d" % int(round(bonus))
	if absf(delta) >= 0.5:
		text += " %s%d" % ["▲" if delta > 0.0 else "▼", int(round(absf(delta)))]
	box.add_child(name_row(group, text, UiTheme.TEXT))
	box.add_child(bar(value / 100.0, VoterGroups.color(group), BAR_HEIGHT, bonus / 100.0, VoterGroups.color(group).lightened(0.55)))
	box.tooltip_text = "%s: partinin bu gruptaki ulusal desteği %s%s.\nBu, grubun ülkedeki nüfus payı DEĞİLDİR." % [
		VoterGroups.title(group), VoterGroups.percent_text(value),
		(" (+%d geçici toplantı desteği)" % int(round(bonus))) if bonus > 0.0 else ""]
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
	box.add_child(name_row(a, "%%%d" % pa, UiTheme.TEXT))
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
	box.add_child(name_row(b, "%%%d" % (100 - pa), UiTheme.TEXT))
	box.tooltip_text = "Bu ilde %s %%%d, %s %%%d (iki taraf toplam %%100)." % [
		VoterGroups.title(a), pa, VoterGroups.title(b), 100 - pa]
	return box

## Etki satırı (önizlemeler için): [simge] Grup adı  +3,5 / −1,2
static func effect_row(group: String, amount: float, font_size: int = FS_NAME) -> Control:
	var color := UiTheme.GREEN if amount > 0.0 else UiTheme.RED
	var text := ("+" if amount > 0.0 else "−") + String.num(snappedf(absf(amount), 0.1), 1).replace(".", ",")
	return name_row(group, text, color, font_size, 14.0)
