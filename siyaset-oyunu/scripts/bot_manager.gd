extends Node
## Autoload. Botları (MultiplayerManager.is_bot) İNSAN HIZINDA oynatır: sıra
## gelince biraz düşünür, kart çeker, biraz daha bekler, sonra oynar; oyları
## ve hükümet tekliflerini de rastgele birkaç saniye içinde verir. Kararlar
## BotBrain'de. Sadece yetkili tarafta (host ya da ağsız yerel oyun) çalışır.

const THINK_SECONDS := Vector2(1.5, 3.0)   # sıra gelince -> kart çekme
const PLAY_SECONDS := Vector2(1.0, 2.2)    # kart çekme -> oynama/pas
const VOTE_SECONDS := Vector2(1.5, 4.5)    # oylama açılınca -> oy
const FORM_SECONDS := Vector2(3.0, 6.0)    # görev gelince -> teklif

var _rng := RandomNumberGenerator.new()
var _turn_key := ""
var _turn_drawn := false
var _turn_due := 0.0
var _vote_key := ""
var _vote_due: Dictionary = {}
var _form_key := ""
var _form_due := 0.0

func _ready() -> void:
	_rng.randomize()

func _is_authority() -> bool:
	return MultiplayerManager.room_code == "" or MultiplayerManager.is_host

func _delay(range_seconds: Vector2) -> float:
	return _rng.randf_range(range_seconds.x, range_seconds.y)

func _process(_delta: float) -> void:
	if not _is_authority() or CardManager.turn_order.is_empty() or CardManager.game_finished:
		_turn_key = ""
		_vote_key = ""
		_form_key = ""
		return
	var now := Time.get_ticks_msec() / 1000.0
	if GovernmentManager.phase == GovernmentManager.Phase.VOTING:
		_handle_votes(now)
	else:
		_vote_key = ""
	if GovernmentManager.phase == GovernmentManager.Phase.FORMING:
		_handle_formation(now)
	else:
		_form_key = ""
	if CardManager.is_turn_blocked():
		_turn_key = ""
	else:
		_handle_turn(now)

func _handle_turn(now: float) -> void:
	var bot := CardManager.current_turn_peer_id()
	if not MultiplayerManager.is_bot(bot):
		_turn_key = ""
		return
	var key := "%d:%d:%d" % [CardManager.round_number, CardManager.current_turn_index, bot]
	if key != _turn_key:
		_turn_key = key
		_turn_drawn = false
		_turn_due = now + _delay(THINK_SECONDS)
		return
	if now < _turn_due:
		return
	if not _turn_drawn:
		_turn_drawn = true
		_turn_due = now + _delay(PLAY_SECONDS)
		if CardManager.inventories.get(bot, []).size() < CardManager.MAX_HAND_SIZE:
			CardManager._apply_draw(bot)
			return
	_turn_due = INF
	var play := BotBrain.choose_play(bot)
	if play.is_empty():
		CardManager._apply_pass(bot)
		return
	var hand_size: int = CardManager.inventories.get(bot, []).size()
	CardManager._apply_play(bot, int(play["index"]), int(play["peer"]), String(play["province"]))
	# Kart reddedildiyse (beklenmedik bir kural) sırayı tıkamamak için pas geç.
	if CardManager.inventories.get(bot, []).size() == hand_size and CardManager.current_turn_peer_id() == bot \
			and not CardManager.is_turn_blocked():
		CardManager._apply_pass(bot)

func _handle_votes(now: float) -> void:
	var key := "%s:%d:%s:%d:%d" % [GovernmentManager.proposal_kind, GovernmentManager.proposal_peer_id,
		GovernmentManager.proposal_law, GovernmentManager.mandate_index, GovernmentManager.attempts_used]
	if key != _vote_key:
		_vote_key = key
		_vote_due.clear()
	for bot in GovernmentManager.voter_ids():
		if not MultiplayerManager.is_bot(bot) or GovernmentManager.has_voted(bot):
			continue
		if not _vote_due.has(bot):
			_vote_due[bot] = now + _delay(VOTE_SECONDS)
		elif now >= float(_vote_due[bot]):
			_vote_due[bot] = INF
			GovernmentManager._apply_vote(bot, BotBrain.choose_vote(bot))
			return  # oylama çözülmüş olabilir; kalanlar sonraki karede

func _handle_formation(now: float) -> void:
	var bot := GovernmentManager.mandate_peer_id()
	if not MultiplayerManager.is_bot(bot):
		_form_key = ""
		return
	# Seçim gecesi yayını sürüyor (süreye eklenen pay): herkes izlerken teklif gelmesin.
	if GovernmentManager.phase_seconds_left() > GameRules.FORMATION_TIMEOUT:
		_form_key = ""
		return
	var key := "%d:%d:%d" % [bot, GovernmentManager.mandate_index, GovernmentManager.attempts_used]
	if key != _form_key:
		_form_key = key
		_form_due = now + _delay(FORM_SECONDS)
	elif now >= _form_due:
		_form_due = INF
		GovernmentManager._apply_government_proposal(bot, BotBrain.build_government(bot))
