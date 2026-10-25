class_name VoteTugBar
extends VBoxContainer
## MECLİS OYLAMA GÖSTERGESİ (0.0.257): meclis diyagramının altında, oylama
## sürerken. EVET soldan (yeşil), HAYIR sağdan (kırmızı) dolar; ortada
## henüz oy vermeyenler (gri) ve çekimserler (sarı, ortada). Anayasa
## oylamasında 2/3 eşiği altın çizgiyle. Altta tek satır durum: kim önde.
## Boyutlar diyagramın genişliğiyle orantılı (oylama büyütmesinde büyür).

## Olağan boyda (sağ sütun) yayın genişliği: puntolar buna göre ölçeklenir.
const BAR_REF_WIDTH := 202.0
## Çubuk bu diyagramın yayıyla aynı genişlikte, ortalı.
var diagram: Control
const COLOR_YES := Color("2E9E4F")
const COLOR_NO := Color("C4303C")
const COLOR_ABSTAIN := Color("B59A1E")
const COLOR_PENDING := Color("2A2F52")

var _bar: Control
var _status: Label
var _yes := 0
var _no := 0
var _abstain := 0
var _total := 0
var _threshold := -1

func _init() -> void:
	add_theme_constant_override("separation", 3)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar = Control.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.custom_minimum_size = Vector2(0, 14)
	_bar.draw.connect(_draw_bar)
	add_child(_bar)
	_status = Label.new()
	_status.add_theme_font_override("font", UiTheme.mono(true))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER

## Oylamanın anlık durumu (GovernmentManager'dan).
func refresh() -> void:
	var totals := GovernmentManager.vote_seat_totals()
	_yes = totals.x
	_no = totals.y
	_abstain = GovernmentManager.abstain_seats()
	_total = maxi(1, GovernmentManager.total_seats())
	_threshold = GovernmentManager.constitution_threshold_seats() if GovernmentManager.proposal_kind == GovernmentManager.KIND_CONSTITUTION else -1
	var lead := _yes - _no
	var text := ""
	var color := UiTheme.TEXT
	if _threshold > 0:
		if _yes >= _threshold:
			text = L.t("2/3 sağlandı · kabul")
			color = UiTheme.GREEN
		else:
			text = L.t("kabul için %d oy daha (2/3 = %d)") % [_threshold - _yes, _threshold]
			color = UiTheme.GOLD
	elif lead > 0:
		text = L.t("EVET önde · +%d") % lead
		color = UiTheme.GREEN
	elif lead < 0:
		text = L.t("HAYIR önde · +%d") % -lead
		color = UiTheme.RED
	else:
		text = L.t("berabere · %d – %d") % [_yes, _no]
		color = UiTheme.TEXT_MUTED
	_status.text = "%s   %s" % [L.t("EVET %d · HAYIR %d") % [_yes, _no], text]
	_status.add_theme_color_override("font_color", color)
	_bar.queue_redraw()

func _process(_delta: float) -> void:
	if visible:
		_fit()

func _fit() -> void:
	var width: float = diagram.arc_width() if diagram != null and diagram.has_method("arc_width") else size.x
	if width <= 0.0:
		return
	var ratio := width / BAR_REF_WIDTH
	if not is_equal_approx(custom_minimum_size.x, width):
		custom_minimum_size.x = width
		_bar.custom_minimum_size.y = clampf(roundf(10.0 * ratio), 8.0, 22.0)
		_status.add_theme_font_size_override("font_size", clampi(roundi(10.0 * ratio), 9, 18))

func _draw_bar() -> void:
	var r := Rect2(Vector2.ZERO, _bar.size)
	if r.size.x <= 2.0:
		return
	var edge := maxf(1.0, roundf(r.size.y / 7.0))
	_bar.draw_rect(r, UiTheme.INK)
	var inner := r.grow(-edge)
	_bar.draw_rect(inner, COLOR_PENDING)
	var w := inner.size.x
	var yes_w := w * float(_yes) / float(_total)
	var no_w := w * float(_no) / float(_total)
	var ab_w := w * float(_abstain) / float(_total)
	_bar.draw_rect(Rect2(inner.position, Vector2(yes_w, inner.size.y)), COLOR_YES)
	_bar.draw_rect(Rect2(Vector2(inner.end.x - no_w, inner.position.y), Vector2(no_w, inner.size.y)), COLOR_NO)
	if ab_w > 0.0:
		# Çekimserler boşluğun ortasında.
		var gap_start := inner.position.x + yes_w
		var gap := w - yes_w - no_w
		_bar.draw_rect(Rect2(Vector2(gap_start + (gap - ab_w) * 0.5, inner.position.y), Vector2(ab_w, inner.size.y)), COLOR_ABSTAIN)
	# Orta çizgi (yasada EVET ile HAYIR'ın karşılaştığı yer) ya da anayasa 2/3 eşiği.
	var mark_x := inner.position.x + (w * float(_threshold) / float(_total) if _threshold > 0 else w * 0.5)
	var mark_w := maxf(2.0, edge * 1.5)
	_bar.draw_rect(Rect2(mark_x - mark_w * 0.5, r.position.y - edge, mark_w, r.size.y + edge * 2.0), UiTheme.GOLD)
