class_name BotBrain
extends RefCounted
## Botların KARARLARI (zamanlaması BotManager'da). Basit fayda puanı: her olası
## hamle oyunun kendi formülleriyle (seçim desteği, miting riski, yasa
## beklentisi...) kabaca puanlanır, en yükseği seçilir. Çok derin değil —
## test ve eksik oyuncuyu doldurmak için "makul" oynaması yeterli.

## En iyi kartın puanı bunun altındaysa bot pas geçer (el doluysa geçmez).
const PASS_THRESHOLD := 0.4

static func _ideology(peer_id: int) -> Dictionary:
	return PartyManager.parties.get(peer_id, {}).get("ideology", IdeologyAxes.default_values())

## İdeolojinin tüm ülkedeki seçmen desteği (milletvekili ağırlıklı, 0..~1).
static func _electoral_strength(ideology: Dictionary) -> float:
	var voters := ElectionModel.load_province_voters()
	var seats: Dictionary = CardManager._province_seat_counts
	var total := 0.0
	var weighted := 0.0
	for province_id in seats.keys():
		var n := float(seats[province_id])
		weighted += ElectionModel.support(ideology, voters.get(province_id, {})) * n
		total += n
	return weighted / maxf(1.0, total)

static func _election_soon() -> bool:
	var next := GameRules.next_election_round(CardManager.round_number)
	return next != -1 and next - CardManager.round_number <= 1

# --- Sıra: hangi kart? ---------------------------------------------------------

## Dönüş: {"index", "peer", "province"} ya da boş sözlük (= pas).
static func choose_play(bot: int) -> Dictionary:
	var hand: Array = CardManager.inventories.get(bot, [])
	var best := {}
	var best_score := PASS_THRESHOLD
	if hand.size() >= CardManager.MAX_HAND_SIZE:
		best_score = -INF  # el dolu: en iyisini oyna, desteyi tıkama
	for i in hand.size():
		var option := _evaluate(bot, String(hand[i]))
		if option.is_empty():
			continue
		if float(option["score"]) > best_score:
			best_score = float(option["score"])
			best = option
			best["index"] = i
	return best

static func _evaluate(bot: int, card_type: String) -> Dictionary:
	if CardPresets.is_ideology_card(card_type):
		return _eval_ideology(bot, card_type)
	if card_type == CardPresets.MITING_CARD_TYPE:
		return _eval_miting(bot)
	if card_type == CardPresets.INVEST_CARD_TYPE:
		return _eval_investment(bot)
	if CardPresets.needs_target(card_type):
		return _eval_steal(bot, card_type)
	if CardPresets.is_censure_card(card_type):
		if not CardManager.can_play_card(bot, card_type):
			return {}
		var passes: bool = GovernmentManager.government_seats() * 2 <= GovernmentManager.total_seats()
		return {"score": 6.0 if passes else 1.0, "peer": -1, "province": ""}
	if CardPresets.is_law_card(card_type):
		return _eval_law(bot, card_type)
	return {}

## Kendi partisini seçmene yaklaştırıyorsa değerli (kart sadece kendi partine).
static func _eval_ideology(bot: int, card_type: String) -> Dictionary:
	var effect: Dictionary = CardPresets.CARD_EFFECTS[card_type]
	var mine := _ideology(bot)
	var moved := mine.duplicate()
	moved[effect["axis"]] = IdeologyAxes.clamp_value(int(mine[effect["axis"]]) + int(effect["delta"]))
	return {"score": (_electoral_strength(moved) - _electoral_strength(mine)) * 40.0, "peer": -1, "province": ""}

## Beklenen il kamuoyu kazancı × ilin vekil sayısı × partinin o ildeki şansı.
static func _eval_miting(bot: int) -> Dictionary:
	var voters := ElectionModel.load_province_voters()
	var ideology := _ideology(bot)
	var best_province := ""
	var best_value := -INF
	for province_id in CardManager._province_seat_counts.keys():
		var risk := CardManager.miting_risk(bot, province_id)
		var seats := float(CardManager.province_seat_count(province_id))
		var closeness := ElectionModel.support(ideology, voters.get(province_id, {}))
		var expected := (1.0 - risk) * PublicOpinion.MITING_LOCAL + risk * PublicOpinion.PROVOCATION_LOCAL
		var value := expected * seats / 6.0 * (0.5 + closeness) \
			+ (1.0 - risk) * PublicOpinion.MITING_NATIONAL + risk * PublicOpinion.PROVOCATION_NATIONAL
		if value > best_value:
			best_value = value
			best_province = province_id
	if best_province == "":
		return {}
	var score := best_value * 0.5 * (1.4 if _election_soon() else 1.0)
	return {"score": score, "peer": -1, "province": best_province}

static func _eval_investment(bot: int) -> Dictionary:
	if not CardManager.is_government_party(bot):
		return {}
	var voters := ElectionModel.load_province_voters()
	var ideology := _ideology(bot)
	var best_province := ""
	var best_value := -INF
	for province_id in CardManager._province_seat_counts.keys():
		var value := float(CardManager.province_seat_count(province_id)) \
			* (0.5 + ElectionModel.support(ideology, voters.get(province_id, {})))
		if value > best_value:
			best_value = value
			best_province = province_id
	return {"score": 1.5 + best_value / 12.0, "peer": -1, "province": best_province}

## İktidardaysa en büyük muhalefetten, muhalefetteyse hükümetten çal.
static func _eval_steal(bot: int, card_type: String) -> Dictionary:
	var in_gov := CardManager.is_government_party(bot)
	var target := -1
	for peer_id in CardManager.turn_order:
		if not CardManager.is_valid_steal_target(bot, peer_id):
			continue
		if GovernmentManager.has_government() and CardManager.is_government_party(peer_id) == in_gov:
			continue
		if target == -1 or GovernmentManager.seats_of(peer_id) > GovernmentManager.seats_of(target):
			target = peer_id
	if target == -1:
		for peer_id in CardManager.turn_order:
			if CardManager.is_valid_steal_target(bot, peer_id) \
					and (target == -1 or GovernmentManager.seats_of(peer_id) > GovernmentManager.seats_of(target)):
				target = peer_id
	if target == -1:
		return {}
	var r: Dictionary = CardPresets.STEAL_RANGES[card_type]
	var score := 1.5 + (float(r["min"]) + float(r["max"])) / 8.0
	# Muhalefetten hükümeti azınlığa düşürebilecek hamle çok değerli (gensoru yolu).
	if not in_gov and GovernmentManager.has_majority() and CardManager.is_government_party(target):
		var after: float = GovernmentManager.government_seats() - (float(r["min"]) + float(r["max"])) / 2.0
		if after * 2.0 <= GovernmentManager.total_seats():
			score += 3.0
	return {"score": score, "peer": target, "province": ""}

## Tabanı destekliyorsa ve geçme ihtimali varsa getir.
static func _eval_law(bot: int, card_type: String) -> Dictionary:
	if not CardManager.can_play_card(bot, card_type):
		return {}
	var law: Dictionary = CardPresets.law_data(card_type)
	var factor: float = float(law["factor"])
	# Yasa, getiren partinin görüşünü kaydırır: seçmene yaklaştırıyor mu?
	var mine := _ideology(bot)
	var moved := mine.duplicate()
	moved[law["axis"]] = IdeologyAxes.clamp_value(int(mine[law["axis"]]) + int(law["dir"]) * int(law["shift"]))
	var shift_gain := (_electoral_strength(moved) - _electoral_strength(mine)) * 40.0
	if GovernmentManager.voter_ids().is_empty():
		return {"score": shift_gain + PublicOpinion.LAW_BASE_REWARD * factor, "peer": -1, "province": ""}
	var expectation := CardManager.law_expectation(bot, card_type)
	if expectation < 0 and shift_gain <= 0.0:
		return {}
	var yes := 0
	var no := 0
	for peer_id in GovernmentManager.voter_ids():
		var other := CardManager.law_expectation(peer_id, card_type)
		if peer_id == bot or other > 0:
			yes += GovernmentManager.seats_of(peer_id)
		elif other < 0:
			no += GovernmentManager.seats_of(peer_id)
	var in_gov := CardManager.is_government_party(bot)
	var score: float
	if yes > no:
		score = PublicOpinion.LAW_PASSED_GOVERNMENT if in_gov else PublicOpinion.LAW_PASSED_OPPOSITION
	else:
		score = PublicOpinion.LAW_REJECTED
	score = score * factor + PublicOpinion.vote_base_delta(expectation, true) * factor + shift_gain
	return {"score": score, "peer": -1, "province": ""}

# --- Oylama --------------------------------------------------------------------

static func choose_vote(bot: int) -> int:
	match GovernmentManager.proposal_kind:
		GovernmentManager.KIND_GOVERNMENT:
			if bot == GovernmentManager.proposal_peer_id or GovernmentManager.proposal_partner_ids().has(bot):
				return GovernmentManager.VOTE_YES
			var pm := int(GovernmentManager.proposal_assignments.get(GovernmentPresets.POST_PM, GovernmentManager.proposal_peer_id))
			var d := ElectionModel.distance(_ideology(bot), _ideology(pm))
			if d < 2.5:
				return GovernmentManager.VOTE_YES
			if d < 5.0:  # HAYIR puan kaybettirir: sadece çok uzak hükümete
				return GovernmentManager.VOTE_ABSTAIN
			return GovernmentManager.VOTE_NO
		GovernmentManager.KIND_CENSURE:
			if CardManager.is_government_party(bot):
				return GovernmentManager.VOTE_NO
			if ElectionModel.distance(_ideology(bot), _ideology(GovernmentManager.main_gov_peer_id)) < 2.0:
				return GovernmentManager.VOTE_ABSTAIN
			return GovernmentManager.VOTE_YES
		GovernmentManager.KIND_LAW:
			if bot == GovernmentManager.proposal_peer_id:
				return GovernmentManager.VOTE_YES
			var best := GovernmentManager.VOTE_YES
			var best_value := -INF
			for choice in [GovernmentManager.VOTE_YES, GovernmentManager.VOTE_ABSTAIN, GovernmentManager.VOTE_NO]:
				var value := CardManager.preview_law_vote(bot, choice)
				if value > best_value + 0.001:
					best_value = value
					best = choice
			return best
	return GovernmentManager.VOTE_ABSTAIN

# --- Hükümet kurma -------------------------------------------------------------

## İdeolojik olarak en yakın partilerle salt çoğunluğa ulaşana kadar koalisyon;
## bakanlıklar sandalyeyle orantılı. Reddedilince sonraki teklifte aday sırası
## kaydırılır (aynı teklifi tekrar tekrar sunmasın).
static func build_government(bot: int) -> Dictionary:
	var total := GovernmentManager.total_seats()
	var mine := _ideology(bot)
	var candidates: Array = GovernmentManager.voter_ids()
	candidates.erase(bot)
	candidates.sort_custom(func(a, b):
		return ElectionModel.distance(mine, _ideology(a)) < ElectionModel.distance(mine, _ideology(b)))
	var shift := GovernmentManager.attempts_used % maxi(1, candidates.size())
	candidates = candidates.slice(shift) + candidates.slice(0, shift)

	var partners: Array = []
	var seats := GovernmentManager.seats_of(bot)
	for peer_id in candidates:
		if seats * 2 > total:
			break
		partners.append(peer_id)
		seats += GovernmentManager.seats_of(peer_id)

	var assignments := {}
	var ministries: Array = []
	for post in GovernmentPresets.POSTS:
		assignments[post["id"]] = bot
		if post["id"] != GovernmentPresets.POST_PM and post["id"] != GovernmentPresets.POST_DEPUTY_PM:
			ministries.append(post["id"])
	if partners.is_empty():
		return assignments
	assignments[GovernmentPresets.POST_DEPUTY_PM] = partners[0]
	var slot := 0
	for peer_id in partners:
		var share := maxi(1, int(round(ministries.size() * float(GovernmentManager.seats_of(peer_id)) / float(seats))))
		for i in share:
			if slot >= ministries.size() - 1:  # görevli parti en az bir bakanlık tutsun
				break
			assignments[ministries[slot]] = peer_id
			slot += 1
	return assignments
