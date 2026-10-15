extends Node
## Autoload. Botları (MultiplayerManager.is_bot) İNSAN HIZINDA oynatır: sıra
## gelince biraz düşünür, hamle hamle oynar, yapacak değerli bir şey kalmayınca
## turu bitirir; oyları
## ve hükümet tekliflerini de rastgele birkaç saniye içinde verir. Kararlar
## BotBrain'de. Sadece yetkili tarafta (host ya da ağsız yerel oyun) çalışır.

## Botlar İNSAN HIZINDA ama beklemeli olmayacak kadar hızlı oynar: bu süreler
## bilinçli olarak yarıya indirildi (eskiden 1.4-1.6 / 1.5-4.5 / 3.0-6.0).
const THINK_SECONDS := Vector2(0.7, 0.8)   # sıra gelince -> ilk hamle
const PLAY_SECONDS := Vector2(0.7, 0.8)    # hamleler arası
## Güvenlik sınırı: bir turda en çok bu kadar bot hamlesi.
const MAX_ACTIONS_PER_TURN := 12
const VOTE_SECONDS := Vector2(0.75, 2.25)  # oylama açılınca -> oy
const FORM_SECONDS := Vector2(1.5, 3.0)    # görev gelince -> teklif

var _rng := RandomNumberGenerator.new()
var _turn_key := ""
var _turn_actions := 0
var _turn_due := 0.0
var _vote_key := ""
var _vote_due: Dictionary = {}
var _form_key := ""
var _form_due := 0.0
var _alliance_due: Dictionary = {}

func _ready() -> void:
	_rng.randomize()

func _is_authority() -> bool:
	return MultiplayerManager.room_code == "" or MultiplayerManager.is_host

func _delay(range_seconds: Vector2) -> float:
	return _rng.randf_range(range_seconds.x, range_seconds.y)

func _process(_delta: float) -> void:
	step(Time.get_ticks_msec() / 1000.0)

## Botların tek bir karelik islemi. _process gercek saati verir; testler
## SANAL SAAT verip tum oyunu hizlandirilmis sekilde oynatabilir.
func step(now: float) -> void:
	if not _is_authority() or CardManager.turn_order.is_empty() or CardManager.game_finished:
		_turn_key = ""
		_vote_key = ""
		_form_key = ""
		return
	_handle_alliance_invitations(now)
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
	if MultiplayerManager.is_passive_away(bot):
		CardManager._apply_pass(bot, false)  # pasif: sırası kendiliğinden geçer
		return
	if not MultiplayerManager.is_ai_controlled(bot):
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
	var alliance_decision := BotBrain.choose_alliance_decision(bot)
	if not alliance_decision.is_empty():
		var alliance_id := int(alliance_decision["alliance_id"])
		if String(alliance_decision["type"]) == "join":
			CardManager._apply_join_alliance(bot, alliance_id)
		else:
			CardManager._apply_decline_alliance_invitation(bot, alliance_id)
		_turn_due = now + _delay(PLAY_SECONDS)
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
	var funds_before := CardManager.funds_of(bot)
	# Devletten ödenen hamle (yatırım, partizan miting) kasayı değiştirmez:
	# hazine ve işlem defteri de izlenir.
	var treasury_before := CardManager.state_treasury()
	var ledger_before := int(CardManager.economy.get("next_id", 1))
	var hand_before: int = CardManager.inventories.get(bot, []).size()
	var laws_before := [CardManager.has_proposed_law_this_round(bot, "group"), CardManager.has_proposed_law_this_round(bot, "tax"), CardManager.has_proposed_law_this_round(bot, "constitution")]
	var blocked_before := CardManager.is_turn_blocked()
	var speech_before := CardManager.speech_done
	match String(action["type"]):
		"speech":
			CardManager._apply_speech(bot, String(action["group"]))
		"law":
			CardManager._apply_law(bot, String(action["law"]))
			if CardManager.has_proposed_law_this_round(bot, "tax" if CardPresets.is_tax_law(String(action["law"])) else "group"):
				BotBrain.note_law(bot, String(action["law"]))
		"constitution":
			CardManager._apply_constitution_proposal(bot, action["payload"])
			if CardManager.has_proposed_law_this_round(bot, "constitution"):
				BotBrain.note_constitution(bot)
		"organization":
			CardManager._apply_organization(bot, String(action["province"]))
		"miting":
			CardManager._apply_miting_move(bot, String(action["province"]), BotBrain.miting_state_share(bot), action.get("focus", []))
		"invest":
			CardManager._apply_invest_move(bot, String(action["province"]), BotBrain.invest_state_share(bot))
		"aid":
			CardManager._apply_aid_move(bot, float(action["party"]), float(action["state"]))
		"censure":
			CardManager._apply_censure_move(bot)
		"inquiry":
			CardManager._apply_inquiry(bot, int(action["target"]))
		"congress":
			CardManager._apply_congress(bot)
		"early_election":
			CardManager._apply_early_election_move(bot)
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
	var applied: bool = CardManager.funds_of(bot) != funds_before or CardManager.current_turn_peer_id() != bot \
		or CardManager.state_treasury() != treasury_before or int(CardManager.economy.get("next_id", 1)) != ledger_before \
		or CardManager.inventories.get(bot, []).size() != hand_before \
		or [CardManager.has_proposed_law_this_round(bot, "group"), CardManager.has_proposed_law_this_round(bot, "tax"), CardManager.has_proposed_law_this_round(bot, "constitution")] != laws_before \
		or CardManager.is_turn_blocked() != blocked_before or CardManager.speech_done != speech_before
	return action if applied else {}

func _handle_votes(now: float) -> void:
	var key := "%s:%d:%s:%d:%d:%d" % [GovernmentManager.proposal_kind, GovernmentManager.proposal_peer_id,
		GovernmentManager.proposal_law, GovernmentManager.mandate_index, GovernmentManager.attempts_used,
		GovernmentManager.proposal_stage]
	if key != _vote_key:
		_vote_key = key
		_vote_due.clear()
	for bot in GovernmentManager.eligible_voter_ids():
		if MultiplayerManager.is_passive_away(bot) and not GovernmentManager.has_voted(bot):
			# Pasif: çekimser (koalisyon görüşmesinde çekimser olunamaz: HAYIR).
			GovernmentManager._apply_vote(bot, GovernmentManager.VOTE_NO if GovernmentManager.is_coalition_stage() else GovernmentManager.VOTE_ABSTAIN)
			return
		if not MultiplayerManager.is_ai_controlled(bot) or GovernmentManager.has_voted(bot):
			continue
		if not _vote_due.has(bot):
			_vote_due[bot] = now + _delay(VOTE_SECONDS)
		elif now >= float(_vote_due[bot]):
			GovernmentManager._apply_vote(bot, BotBrain.choose_vote(bot))
			# OY GERÇEKTEN İŞLENDİ Mİ? Reddedilen oyu "verilmiş" sayarsak bot bir
			# daha hiç oy vermez ve oylama boşuna süre dolana kadar bekler.
			_vote_due[bot] = INF if GovernmentManager.has_voted(bot) else now + _delay(VOTE_SECONDS)
			return  # oylama çözülmüş olabilir; kalanlar sonraki karede

func _handle_formation(now: float) -> void:
	var bot := GovernmentManager.mandate_peer_id()
	if not MultiplayerManager.is_ai_controlled(bot):
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
		GovernmentManager._apply_government_proposal(bot, BotBrain.build_government(bot))
		# TEKLİF GERÇEKTEN VERİLDİ Mİ? Geçersiz bir kabine sessizce reddedilirse
		# bot bir daha denemez ve kurma süresi boşuna yanar.
		_form_due = INF if GovernmentManager.phase == GovernmentManager.Phase.VOTING \
			else now + _delay(FORM_SECONDS)

func _handle_alliance_invitations(now: float) -> void:
	var pending := {}
	for alliance_id in CardManager.alliances:
		for pid in CardManager.alliances[alliance_id].get("invitations", []):
			if not MultiplayerManager.is_ai_controlled(int(pid)) or CardManager.alliance_of(int(pid)) >= 0:
				continue
			var key := "%d:%d" % [int(alliance_id), int(pid)]
			pending[key] = true
			if not _alliance_due.has(key):
				_alliance_due[key] = now + _delay(VOTE_SECONDS)
			elif now >= float(_alliance_due[key]):
				var decision := BotBrain.choose_alliance_decision(int(pid), true)
				if not decision.is_empty():
					if decision["type"] == "join":
						CardManager._apply_join_alliance(int(pid), int(decision["alliance_id"]), true)
					else:
						CardManager._apply_decline_alliance_invitation(int(pid), int(decision["alliance_id"]))
				_alliance_due.erase(key)
				return
	for key in _alliance_due.keys():
		if not pending.has(key):
			_alliance_due.erase(key)
