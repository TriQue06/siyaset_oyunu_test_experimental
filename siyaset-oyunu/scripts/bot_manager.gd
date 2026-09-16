extends Node
## Autoload. Botları (MultiplayerManager.is_bot) İNSAN HIZINDA oynatır: sıra
## gelince biraz düşünür, hamle hamle oynar, yapacak değerli bir şey kalmayınca
## turu bitirir; oyları
## ve hükümet tekliflerini de rastgele birkaç saniye içinde verir. Kararlar
## BotBrain'de. Sadece yetkili tarafta (host ya da ağsız yerel oyun) çalışır.

const THINK_SECONDS := Vector2(1.5, 3.0)   # sıra gelince -> ilk hamle
const PLAY_SECONDS := Vector2(1.0, 2.2)    # hamleler arası
## Güvenlik sınırı: bir turda en çok bu kadar bot hamlesi.
const MAX_ACTIONS_PER_TURN := 12
const VOTE_SECONDS := Vector2(1.5, 4.5)    # oylama açılınca -> oy
const FORM_SECONDS := Vector2(3.0, 6.0)    # görev gelince -> teklif

var _rng := RandomNumberGenerator.new()
var _turn_key := ""
var _turn_actions := 0
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
		_turn_actions = 0
		_turn_due = now + _delay(THINK_SECONDS)
		return
	if now < _turn_due:
		return
	# Hamle sınırı yok: bot her hamleden sonra biraz düşünüp devam eder,
	# yapacak değerli bir şey kalmayınca turu bitirir.
	_turn_due = now + _delay(PLAY_SECONDS)
	_turn_actions += 1
	if _turn_actions > MAX_ACTIONS_PER_TURN or do_action(bot).is_empty():
		CardManager._apply_pass(bot, true)

## Botun bir hamlesini uygular (testler ve simülasyon da kullanır). Uygulanan
## hamle {"type", "card"?, "peer"?, "province"?} döner; bot turu bitirmek
## istiyorsa ya da hamle reddedildiyse boş sözlük.
static func do_action(bot: int) -> Dictionary:
	var action := BotBrain.choose_action(bot)
	var mana_before := CardManager.mana_of(bot)
	var hand_before: int = CardManager.inventories.get(bot, []).size()
	var laws_before := CardManager.has_proposed_law_this_round(bot)
	var blocked_before := CardManager.is_turn_blocked()
	match String(action["type"]):
		"law":
			CardManager._apply_law(bot, String(action["law"]))
		"organization":
			CardManager._apply_organization(bot, String(action["province"]))
		"scout":
			CardManager._apply_scout_move(bot, String(action["province"]))
		"miting":
			CardManager._apply_miting_move(bot, String(action["province"]))
		"draw":
			CardManager._apply_draw(bot)
		"card":
			var play := BotBrain.choose_play(bot)
			if play.is_empty():
				return {}
			action["card"] = String(CardManager.inventories[bot][int(play["index"])])
			action["peer"] = int(play["peer"])
			action["province"] = String(play["province"])
			CardManager._apply_play(bot, int(play["index"]), int(play["peer"]), String(play["province"]))
		_:
			return {}
	# Hamle gerçekten uygulandı mı? (Reddedilen hamlede döngüye girmesin.)
	var applied: bool = CardManager.mana_of(bot) != mana_before \
		or CardManager.inventories.get(bot, []).size() != hand_before \
		or CardManager.has_proposed_law_this_round(bot) != laws_before \
		or CardManager.is_turn_blocked() != blocked_before
	return action if applied else {}

func _handle_votes(now: float) -> void:
	var key := "%s:%d:%s:%d:%d:%d" % [GovernmentManager.proposal_kind, GovernmentManager.proposal_peer_id,
		GovernmentManager.proposal_law, GovernmentManager.mandate_index, GovernmentManager.attempts_used,
		GovernmentManager.proposal_stage]
	if key != _vote_key:
		_vote_key = key
		_vote_due.clear()
	for bot in GovernmentManager.eligible_voter_ids():
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
