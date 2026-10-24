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
	# TUR BAŞI (0.0.231): önce kart çekilir, sonra varsa afet kararı verilir.
	if CardManager.needs_turn_draw(bot):
		CardManager._apply_draw(bot)
		_turn_due = now + _delay(PLAY_SECONDS)
		return
	if CardManager.aid_pending(bot):
		var aid := BotBrain.choose_aid(bot)
		if aid.is_empty():
			CardManager._apply_skip_aid(bot)
		else:
			CardManager._apply_aid_move(bot, float(aid["party"]), float(aid["state"]))
			if CardManager.aid_pending(bot):
				CardManager._apply_skip_aid(bot)  # reddedildiyse karar yine kapanır
		_turn_due = now + _delay(PLAY_SECONDS)
		return
	var alliance_move := BotBrain.choose_alliance_move(bot)
	if not alliance_move.is_empty():
		match String(alliance_move["type"]):
			"request":
				CardManager._apply_request_alliance(bot, int(alliance_move["alliance_id"]))
			"create":
				CardManager._apply_create_alliance(bot, String(alliance_move["name"]), alliance_move["color"])
			"invite":
				CardManager._apply_invite_alliance_party(bot, int(alliance_move["alliance_id"]), int(alliance_move["party"]))
			"leave":
				CardManager._apply_leave_alliance(bot)
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
	# Devletten ödenen hamle (yatırım) kasayı değiştirmez: hazine de izlenir.
	var treasury_before := CardManager.state_treasury()
	var hand_before: int = CardManager.inventories.get(bot, []).size()
	var laws_before := [CardManager.has_proposed_law_this_round(bot, "group"), CardManager.has_proposed_law_this_round(bot, "tax"), CardManager.has_proposed_law_this_round(bot, "constitution")]
	var blocked_before := CardManager.is_turn_blocked()
	var speech_before := CardManager.speech_done
	var closed_before := CardManager.parliament_closed_stages(bot).size()
	var mitings_before := CardManager.miting_count(bot)
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
			var tier := int(action.get("tier", CardManager.DEFAULT_TIER))
			var smear := int(action.get("smear", -1))
			CardManager._apply_miting_move(bot, String(action["province"]), 0.0,
				action.get("focus", []), tier, smear)
		"invest":
			var invest_tier := int(action.get("tier", CardManager.DEFAULT_TIER))
			CardManager._apply_invest_move(bot, String(action["province"]), 1.0, invest_tier)
		"parl_pass":
			CardManager._apply_parl_pass(bot, String(action["stage"]))
		"aid":
			CardManager._apply_aid_move(bot, float(action["party"]), float(action["state"]))
		"censure":
			CardManager._apply_censure_move(bot)
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
		or CardManager.state_treasury() != treasury_before \
		or CardManager.inventories.get(bot, []).size() != hand_before \
		or [CardManager.has_proposed_law_this_round(bot, "group"), CardManager.has_proposed_law_this_round(bot, "tax"), CardManager.has_proposed_law_this_round(bot, "constitution")] != laws_before \
		or CardManager.is_turn_blocked() != blocked_before or CardManager.speech_done != speech_before \
		or CardManager.parliament_closed_stages(bot).size() != closed_before or CardManager.miting_count(bot) != mitings_before
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

## İTTİFAK BAŞVURULARI (0.0.225): bot olan davet edilen parti ya da oylayan
## üye, düşünme süresinden sonra sıra beklemeden yanıt verir.
func _handle_alliance_invitations(now: float) -> void:
	var pending := {}
	for rid in CardManager.alliance_requests.keys():
		var req: Dictionary = CardManager.alliance_requests.get(rid, {})
		var waiting: Array = []
		if String(req.get("kind", "")) == "invite" and not bool(req.get("accepted", false)):
			waiting.append(int(req["party"]))
		for voter in req.get("voters", []):
			if not (req.get("votes", {}) as Dictionary).has(int(voter)):
				waiting.append(int(voter))
		for pid in waiting:
			if not MultiplayerManager.is_ai_controlled(pid):
				continue
			var key := "%d:%d" % [int(rid), pid]
			pending[key] = true
			if not _alliance_due.has(key):
				_alliance_due[key] = now + _delay(VOTE_SECONDS)
			elif now >= float(_alliance_due[key]):
				_alliance_due.erase(key)
				CardManager._apply_answer_alliance(pid, int(rid), BotBrain.alliance_answer(pid, int(rid)))
				return
	for key in _alliance_due.keys():
		if not pending.has(key):
			_alliance_due.erase(key)
