class_name BotBrain
extends RefCounted
## Botların KARARLARI (zamanlaması BotManager'da). Basit fayda puanı: her olası
## hamle oyunun kendi formülleriyle (seçim desteği, il gücü, miting riski,
## yasanın il etkileri...) kabaca puanlanır, en yükseği seçilir.
##
## BİLGİ KISITI: botlar da insanlar gibi illerin görüşünü BİLMEZ. Sadece gözcü
## gönderdikleri illerde her eksenin hangi uçta ya da ortada olduğunu bilirler
## (bkz. _known_centers); anketlerden de önde olan partilerin görüşüne bakıp
## kaba bir tahmin çıkarırlar, bilmedikleri illeri nötr (0) sayarlar. Önce
## kimliklerini güçlendiren yasalar sunar, öğrendikçe yasalarını illere göre
## seçerler. Bu yüzden gözcü hamlesi botlar için de değerlidir. Miting riski
## ise insanlara da gösterilen bir ipucu olduğu için doğrudan kullanılır.
##
## HAMLE SINIRI YOK: BotManager, choose_action "pass" (turu bitir) diyene kadar
## hamle yaptırır. Her seçeneğin puanından mana bedeli × MANA_VALUE düşülür;
## böylece bot ucuz ama değersiz hamlelere manasını dağıtmaz, biriktirir.

## En iyi kartın puanı bunun altındaysa bot kart oynamaz (el doluysa oynar).
const PASS_THRESHOLD := 0.4
## Ana hamlelerin taban puanları.
const PASS_ACTION_SCORE := 0.7
## Bir mananın puan karşılığı (hamle puanından bedel × bu değer düşülür).
const MANA_VALUE := 0.3
## Elde bu kadar kart yoksa kart çekmek cazip.
const DRAW_HAND_TARGET := 3
## Gözcü bilgisinden tahmin edilen eksen değeri (uç biliniyor, büyüklük değil).
const LEANING_ESTIMATE := 2.0
## Anketteki pay-ağırlıklı parti görüşünü il görüşü tahminine çeviren çarpan.
const POLL_INFERENCE_SCALE := 2.0

static func _ideology(peer_id: int) -> Dictionary:
	return PartyManager.parties.get(peer_id, {}).get("ideology", IdeologyAxes.default_values())

static func _seats() -> Dictionary:
	return CardManager._province_seat_counts

static func _total_seats() -> float:
	return float(maxi(1, CardManager.TOTAL_SEATS))

## Botun bildiği il görüşleri: province_id -> tahmini merkez. Gözcü gönderilmemiş
## iller boş sözlük (= nötr) döner.
static func _known_centers(bot: int) -> Dictionary:
	var result := {}
	for province_id in _seats().keys():
		if not CardManager.has_scouted(bot, province_id):
			result[province_id] = _infer_from_poll(bot, province_id)
			continue
		var center := CardManager.province_center(province_id)
		var estimate := {}
		for axis in IdeologyAxes.AXES:
			estimate[axis] = signf(float(center.get(axis, 0.0))) * LEANING_ESTIMATE
		result[province_id] = estimate
	return result

## Anketten kaba çıkarım: ilde önde olan partilerin görüşü ilin görüşüne
## yakındır. Oy payıyla ağırlıklı parti görüşlerinin ortalaması; partiler hâlâ
## nötrse bilgi vermez (boş sözlük).
static func _infer_from_poll(bot: int, province_id: String) -> Dictionary:
	var poll := CardManager.poll_of(bot, province_id)
	if poll.is_empty():
		return {}
	var shares: Dictionary = poll.get("shares", {})
	var estimate := {}
	var informative := false
	for axis in IdeologyAxes.AXES:
		var sum := 0.0
		for peer_id in shares.keys():
			sum += float(shares[peer_id]) / 100.0 * float(_ideology(int(peer_id)).get(axis, 0))
		estimate[axis] = sum * POLL_INFERENCE_SCALE
		if absf(sum) > 0.05:
			informative = true
	return estimate if informative else {}

## İdeolojinin tüm ülkedeki (bilinen) seçmen desteği (milletvekili ağırlıklı).
static func _electoral_strength(ideology: Dictionary, known: Dictionary) -> float:
	var seats := _seats()
	var weighted := 0.0
	for province_id in seats.keys():
		weighted += ElectionModel.support(ideology, known.get(province_id, {})) * float(seats[province_id])
	return weighted / _total_seats()

static func _election_soon() -> bool:
	var next := GameRules.next_election_round(CardManager.round_number)
	return next != -1 and next - CardManager.round_number <= 1

# --- Ana hamle ------------------------------------------------------------------

## Manası bol olan bot için mana ucuzdur (birikip boşa durmasın), azsa değerlidir.
static func _mana_value(bot: int) -> float:
	return MANA_VALUE * clampf(4.0 / maxf(1.0, float(CardManager.mana_of(bot))), 0.2, 1.5)

## Dönüş: {"type": "card"} | {"type": "law", "law"} | {"type": "organization",
## "province"} | {"type": "scout", "province"} | {"type": "draw"} | {"type": "pass"}
static func choose_action(bot: int) -> Dictionary:
	var known := _known_centers(bot)
	var best := {"type": "pass"}
	var best_score := PASS_ACTION_SCORE
	var mana_value := _mana_value(bot)

	var hand: Array = CardManager.inventories.get(bot, [])
	var play := choose_play(bot)
	if not play.is_empty():
		var card: String = hand[int(play["index"])]
		var card_score := float(play["score"]) - CardPresets.card_cost(card) * mana_value
		if card_score > best_score:
			best = {"type": "card"}
			best_score = card_score

	if CardManager.can_propose_law(bot):
		var law := _best_law(bot, known)
		if not law.is_empty() and float(law["score"]) - GameRules.LAW_MANA_COST * mana_value > best_score:
			best = {"type": "law", "law": law["law"]}
			best_score = float(law["score"]) - GameRules.LAW_MANA_COST * mana_value

	var org := _best_organization(bot, known)
	if not org.is_empty() and float(org["score"]) - GameRules.ORG_MANA_COST * mana_value > best_score:
		best = {"type": "organization", "province": org["province"]}
		best_score = float(org["score"]) - GameRules.ORG_MANA_COST * mana_value

	var scout := _best_scout(bot)
	if not scout.is_empty() and float(scout["score"]) - GameRules.SCOUT_MANA_COST * mana_value > best_score:
		best = {"type": "scout", "province": scout["province"]}
		best_score = float(scout["score"]) - GameRules.SCOUT_MANA_COST * mana_value

	if CardManager.can_draw_for(bot):
		# Elde oynanabilir kart azsa çek; kalan mana bir kart oynamaya yetmeli.
		var draw_score := 0.0
		if hand.size() < DRAW_HAND_TARGET:
			draw_score = 1.6 - 0.4 * hand.size()
		if CardManager.mana_of(bot) - GameRules.DRAW_MANA_COST < 2:
			draw_score *= 0.5
		if draw_score - GameRules.DRAW_MANA_COST * mana_value > best_score:
			best = {"type": "draw"}
	return best

## Seçim desteğini en çok artıracak yasa: bilinen illerdeki etkiler (geçme
## ihtimaliyle) + partinin görüş kaymasının seçmene yaklaştırması.
static func _best_law(bot: int, known: Dictionary) -> Dictionary:
	var seats := _seats()
	var in_parliament := not CardManager.last_seats.is_empty()
	var mine := _ideology(bot)
	var best := {}
	# Sadece gözcü gönderilmiş illerden çıkarım yapılır: ortalama etki × güven
	# (bilinen vekil oranı arttıkça bot yasaya daha çok güvenir).
	var known_seats := 0.0
	for province_id in seats.keys():
		if not (known.get(province_id, {}) as Dictionary).is_empty():
			known_seats += float(seats[province_id])
	if known_seats <= 0.0:
		return _exploration_law(bot, mine)
	var confidence := clampf(known_seats / 60.0, 0.3, 1.0)
	for axis in IdeologyAxes.AXES:
		for dir in [-1, 1]:
			var law_type := CardPresets.law_type(axis, dir)
			var sum := 0.0
			for province_id in seats.keys():
				if (known.get(province_id, {}) as Dictionary).is_empty():
					continue
				var alignment := PublicOpinion.law_alignment(known[province_id], axis, dir)
				sum += float(seats[province_id]) * PublicOpinion.law_proposer_delta(alignment, false)
			var value := sum / known_seats * confidence
			if in_parliament:
				value *= 1.0 + _law_pass_chance(bot, law_type, known) * (PublicOpinion.LAW_PASSED_MULT - 1.0)
			var moved := mine.duplicate()
			moved[axis] = IdeologyAxes.clamp_value(float(mine.get(axis, 0)) + IdeologyAxes.LAW_PROPOSE_SHIFT * dir)
			value += (_electoral_strength(moved, known) - _electoral_strength(mine, known)) * 20.0
			var score := 1.7 + value * 5.0
			if best.is_empty() or score > float(best["score"]):
				best = {"law": law_type, "score": score}
	# Az il biliniyorken tahmin gürültülü: kimlik yasası daha iyiyse o sunulur.
	if known_seats < 60.0:
		var exploration := _exploration_law(bot, mine)
		if float(exploration["score"]) > float(best["score"]):
			return exploration
	return best

## Hiç il bilinmiyorken: parti kimliğini güçlendiren (en belirgin ekseninde)
## yasa; kimlik yoksa bota ve tura göre bir eksen. Çok iyi bir kart (ör. büyük
## ilde gözcü) varsa o önce gelir. Yasa partiyi kaydırdıkça kimlik oluşur.
static func _exploration_law(bot: int, mine: Dictionary) -> Dictionary:
	var best_axis := ""
	var best_dir := 1
	var strength := 0.0
	for axis in IdeologyAxes.AXES:
		var v := float(mine.get(axis, 0))
		if absf(v) > strength:
			strength = absf(v)
			best_axis = axis
			best_dir = 1 if v > 0 else -1
	if best_axis == "":
		var seed_value := absi(bot) + CardManager.round_number
		best_axis = IdeologyAxes.AXES[seed_value % IdeologyAxes.AXES.size()]
		best_dir = 1 if (absi(bot) / 7) % 2 == 0 else -1
	return {"law": CardPresets.law_type(best_axis, best_dir), "score": 1.5}

## Kaba geçme ihtimali: diğer partilerin oyu, botun kendi bilgisiyle tahmin edilir.
static func _law_pass_chance(bot: int, law_type: String, known: Dictionary) -> float:
	var gov_ids := GovernmentManager.government_party_ids()
	var yes := GovernmentManager.seats_of(bot)
	var no := 0
	for peer_id in GovernmentManager.voter_ids():
		if peer_id == bot:
			continue
		match _best_law_vote(peer_id, law_type, bot, gov_ids, known):
			GovernmentManager.VOTE_YES:
				yes += GovernmentManager.seats_of(peer_id)
			GovernmentManager.VOTE_NO:
				no += GovernmentManager.seats_of(peer_id)
	return 0.85 if yes > no else 0.15

## Bir partinin bir yasaya EVET/HAYIR demesinin (bilinen) il etkilerinin vekil
## ağırlıklı toplamı.
static func _law_vote_value(voter: int, law_type: String, choice: int, proposer: int, gov_ids: Array, known: Dictionary) -> float:
	var law := CardPresets.law_data(law_type)
	if law.is_empty() or choice == GovernmentManager.VOTE_ABSTAIN:
		return 0.0
	var seats := _seats()
	var sum := 0.0
	for province_id in seats.keys():
		var alignment := PublicOpinion.law_alignment(known.get(province_id, {}), law["axis"], int(law["dir"]))
		sum += float(seats[province_id]) * PublicOpinion.law_vote_delta(alignment, choice, gov_ids.has(voter), gov_ids.has(proposer))
	return sum / _total_seats()

static func _best_law_vote(voter: int, law_type: String, proposer: int, gov_ids: Array, known: Dictionary) -> int:
	var best := GovernmentManager.VOTE_ABSTAIN
	var best_value := 0.0
	for choice in [GovernmentManager.VOTE_YES, GovernmentManager.VOTE_NO]:
		var value := _law_vote_value(voter, law_type, choice, proposer, gov_ids, known)
		if value > best_value + 0.01:
			best_value = value
			best = choice
	# İktidar muhalefetin yasasını genelde reddeder: yasa geçerse getiren 2 kat güçlenir.
	if gov_ids.has(voter) and not gov_ids.has(proposer) and best == GovernmentManager.VOTE_ABSTAIN:
		best = GovernmentManager.VOTE_NO
	return best

## Vekili çok, partiye (bilindiği kadarıyla) yakın ve henüz teşkilatı zayıf il.
static func _best_organization(bot: int, known: Dictionary) -> Dictionary:
	var seats := _seats()
	var mine := _ideology(bot)
	var best := {}
	for province_id in seats.keys():
		if not CardManager.can_build_organization(bot, province_id):
			continue
		var level := CardManager.organization_level(province_id, bot)
		# 2 mana: kalıcı ama pahalı — büyük illerde bile yasa/kartla yarışacak kadar.
		var center: Dictionary = known.get(province_id, {})
		# Bilinmeyen il: yakınlık orta varsayılır (nötr merkez parti için aldatıcı derecede yakın görünürdü).
		var closeness := ElectionModel.support(mine, center) if not center.is_empty() else 0.5
		var value := float(seats[province_id]) * (0.5 + closeness) / 30.0 * (1.0 - 0.3 * level)
		var score := 0.6 + value * (1.3 if _election_soon() else 1.0)
		if best.is_empty() or score > float(best["score"]):
			best = {"province": province_id, "score": score}
	return best

# --- Sıra: hangi kart? ---------------------------------------------------------

## Dönüş: {"index", "peer", "province", "score"} ya da boş sözlük (= oynama).
static func choose_play(bot: int) -> Dictionary:
	var known := _known_centers(bot)
	var hand: Array = CardManager.inventories.get(bot, [])
	var best := {}
	var best_score := PASS_THRESHOLD
	if hand.size() >= CardManager.MAX_HAND_SIZE:
		best_score = -INF  # el dolu: en iyisini oyna, desteyi tıkama
	for i in hand.size():
		var option := _evaluate(bot, String(hand[i]), known)
		if option.is_empty():
			continue
		if float(option["score"]) > best_score:
			best_score = float(option["score"])
			best = option
			best["index"] = i
	return best

static func _evaluate(bot: int, card_type: String, known: Dictionary) -> Dictionary:
	if CardManager.mana_of(bot) < CardPresets.card_cost(card_type):
		return {}
	match card_type:
		CardPresets.MITING_CARD_TYPE:
			return _eval_miting(bot, known)
		CardPresets.INVEST_CARD_TYPE:
			return _eval_investment(bot, known)
		CardPresets.PROPAGANDA_CARD_TYPE:
			return _eval_propaganda(bot, known)
		CardPresets.POLL_CARD_TYPE:
			return _eval_poll(bot)
	if CardPresets.needs_target(card_type):
		return _eval_steal(bot, card_type)
	if CardPresets.is_censure_card(card_type):
		if not CardManager.can_play_card(bot, card_type):
			return {}
		var passes: bool = GovernmentManager.government_seats() * 2 <= GovernmentManager.total_seats()
		# Reddedilen gensoru getirene ulusal eksi yazar: geçmeyecekse elde tut.
		return {"score": 6.0 if passes else 0.05, "peer": -1, "province": ""}
	return {}

## Beklenen il gücü kazancı × ilin vekil sayısı × partinin o ildeki (bilinen) şansı.
static func _eval_miting(bot: int, known: Dictionary) -> Dictionary:
	var ideology := _ideology(bot)
	var best_province := ""
	var best_value := -INF
	for province_id in _seats().keys():
		var risk := CardManager.miting_risk(bot, province_id)
		var seats := float(CardManager.province_seat_count(province_id))
		var closeness := ElectionModel.support(ideology, known.get(province_id, {}))
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

static func _eval_investment(bot: int, known: Dictionary) -> Dictionary:
	if not CardManager.is_government_party(bot):
		return {}
	var ideology := _ideology(bot)
	var best_province := ""
	var best_value := -INF
	for province_id in _seats().keys():
		var value := float(CardManager.province_seat_count(province_id)) \
			* (0.5 + ElectionModel.support(ideology, known.get(province_id, {})))
		if value > best_value:
			best_value = value
			best_province = province_id
	return {"score": 1.5 + best_value / 12.0, "peer": -1, "province": best_province}

## En büyük rakibi, en çok vekilli ve onun zayıf, botun güçlü olduğu ilde karala.
static func _eval_propaganda(bot: int, known: Dictionary) -> Dictionary:
	var best := {}
	var best_value := -INF
	for province_id in _seats().keys():
		var seats := float(CardManager.province_seat_count(province_id))
		var center: Dictionary = known.get(province_id, {})
		var gain := PublicOpinion.propaganda_gain(PublicOpinion.party_strength(
			_ideology(bot), center, CardManager.activity_of(province_id, bot)))
		for target in CardManager.turn_order:
			if target == bot:
				continue
			var damage := PublicOpinion.propaganda_damage(PublicOpinion.party_strength(
				_ideology(target), center, CardManager.activity_of(province_id, target)))
			var rival := 1.0 + float(GovernmentManager.seats_of(target)) / _total_seats() * 2.0
			var value := (gain + damage * 0.6 * rival) * seats / 6.0
			if value > best_value:
				best_value = value
				best = {"peer": target, "province": province_id}
	if best.is_empty():
		return {}
	best["score"] = best_value * 0.45
	return best

## Gözcü hamlesi: vekili çok ve henüz bilinmeyen il değerlidir (yasa ve il
## başkanlığı kararları bu bilgiye dayanır). Bilinen il arttıkça değeri düşer.
static func _best_scout(bot: int) -> Dictionary:
	if not CardManager.can_scout(bot):
		return {}
	var best_province := ""
	var known := 0
	for province_id in _seats().keys():
		if CardManager.has_scouted(bot, province_id):
			known += 1
		elif best_province == "" or CardManager.province_seat_count(province_id) > CardManager.province_seat_count(best_province):
			best_province = province_id
	if best_province == "":
		return {}
	var score := (0.6 + float(CardManager.province_seat_count(best_province)) / 12.0) / (1.0 + known * 0.15)
	return {"score": score, "province": best_province}

## Anket botların kararlarına girmez: sadece el dolunca atılır.
static func _eval_poll(bot: int) -> Dictionary:
	var best_province := ""
	for province_id in _seats().keys():
		if best_province == "" or CardManager.province_seat_count(province_id) > CardManager.province_seat_count(best_province):
			best_province = province_id
	if best_province == "":
		return {}
	return {"score": 0.1, "peer": -1, "province": best_province}

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
	# Vekil sayısı bir sonraki seçime de momentum olarak yansır.
	var score := 1.8 + (float(r["min"]) + float(r["max"])) / 7.0
	# Muhalefetten hükümeti azınlığa düşürebilecek hamle çok değerli (gensoru yolu).
	if not in_gov and GovernmentManager.has_majority() and CardManager.is_government_party(target):
		var after: float = GovernmentManager.government_seats() - (float(r["min"]) + float(r["max"])) / 2.0
		if after * 2.0 <= GovernmentManager.total_seats():
			score += 3.0
	return {"score": score, "peer": target, "province": ""}

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
			return _best_law_vote(bot, GovernmentManager.proposal_law, GovernmentManager.proposal_peer_id,
				GovernmentManager.proposal_gov_ids, _known_centers(bot))
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
