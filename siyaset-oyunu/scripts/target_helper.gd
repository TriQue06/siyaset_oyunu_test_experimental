class_name TargetHelper
extends RefCounted
## HEDEF YARDIMCISI (0.0.334): oyuncunun hedeflediği seçmen grupları. Yalnız bu
## istemcide tutulur (oyun kuralını değiştirmez, ağa gitmez). Hedef gruplar
## grup yasası düğmelerinde, seçmen haritasında ve miting gruplarında sıra
## yılanıyla (TurnSnake; beyaz ve grubun renginde) işaretlenir.

## Haritada ve mitingde "grup ağırlıklı il" eşiği (karşıt çift içinde yüzde).
const THRESHOLD := 50

static var groups: Array = []
## Her değişiklikte artar: ekranlar kendini tazelemek için karşılaştırır.
static var revision := 0

static func has(group: String) -> bool:
	return groups.has(group)

static func toggle(group: String) -> void:
	if groups.has(group):
		groups.erase(group)
	else:
		groups.append(group)
	revision += 1

## Hangi oyun için hedefler kuruldu (oyun ekranı her seçimden sonra yeniden açılır).
static var _game_key := ""

## Oyun ekranı açılışı: yeni oyunsa hedefler çekirdek gruplarla başlar, aynı
## oyunsa oyuncunun seçimi korunur.
static func start_game(key: String, core: Array) -> void:
	if key == _game_key:
		revision += 1
		return
	_game_key = key
	reset(core)

## Hedefler partinin çekirdek grupları (parti kurma ekranı).
static func reset(core: Array) -> void:
	groups = []
	for group in core:
		if VoterGroups.is_group(String(group)) and not groups.has(String(group)):
			groups.append(String(group))
	revision += 1

static func clear() -> void:
	groups = []
	revision += 1

## İlde hedef grup ağırlıklı mı (karşıt çiftinde %50'nin üstünde)?
static func strong_in(profile: Dictionary, group: String) -> bool:
	return has(group) and VoterGroups.percent(profile, group) > THRESHOLD

## Düğmenin çevresine sıra yılanı ekler (düğmenin kendi köşe yarıçapıyla).
static func attach_snake(control: Control, group: String) -> TurnSnake:
	var snake := TurnSnake.new()
	snake.name = "TargetSnake"
	snake.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Beyaz ve hedef grubun renginde iki yılan.
	snake.lead_color = Color.WHITE
	var tint := VoterGroups.color(group)
	tint.a = 1.0
	snake.party_color = tint
	var style := control.get_theme_stylebox("normal") if control is Button else control.get_theme_stylebox("panel")
	if style is BoardBox:
		snake.radius = (style as BoardBox).radius_tl
	elif style is StyleBoxFlat:
		snake.radius = float((style as StyleBoxFlat).corner_radius_top_left)
	control.add_child(snake)
	return snake

## Düğmede yılan olsun / olmasın.
static func set_snake(control: Control, on: bool, group: String) -> void:
	var old := control.get_node_or_null("TargetSnake")
	if on and old == null:
		attach_snake(control, group)
	elif not on and old != null:
		control.remove_child(old)
		old.queue_free()
