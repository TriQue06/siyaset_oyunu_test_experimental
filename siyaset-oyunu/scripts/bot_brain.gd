class_name BotBrain
extends RefCounted
## Botların KARARLARI (zamanlaması BotManager'da). Basit fayda puanı: her olası
## hamle oyunun kendi formülleriyle (seçim desteği, il gücü, miting riski,
## yasanın il etkileri...) kabaca puanlanır, en yükseği seçilir.
##
## BİLGİ KISITI: botlar da insanlar gibi illerin görüşünü BİLMEZ. Sadece
## teşkilat kurdukları illerde her eksenin hangi uçta ya da ortada olduğunu bilirler
## (bkz. _known_centers; gözcünün süresi bitse de görüş hatırlanır), bilmedikleri
## illeri nötr (0) sayarlar. Önce
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
## Gözcü bilgisinden tahmin edilen eksen değeri (uç biliniyor, büyüklük değil).
const LEANING_ESTIMATE := 2.0
## Yasanın taban puanı: yasa her tur meclisi durdurur, bot onu sadece gerçekten
## işe yarayacaksa sunsun (miting / il başkanlığı / kartlar öne geçebilsin).
const LAW_BASE_SCORE := 1.0
## Bot bir yasayı en fazla bu kadar turda bir sunar.
const LAW_EVERY_ROUNDS := 2
## Muhalefetteki bot, hükümete bu mesafeden yakınsa gensoruda çekimser kalır.
const CENSURE_LOYALTY_DISTANCE := 1.2

# --- BOT BLOĞU ------------------------------------------------------------------
## Hükümeti bir İNSAN partisi kurduysa muhalefetteki botlar birleşir:
##   1. Hepsi vekil çalma kartlarını hükümetin ana partisine yöneltir; bloğun
##      en büyük botunu birinci parti yapmak (hükümet kurma yetkisi sırası
##      sandalyeye göre) ve hükümeti azınlığa düşürmek ek puan kazandırır.
##   2. Gensoruyu blok olarak hesaplar ve oylar (ideolojik yakınlık fark etmez).
##   3. Gensoru geçince kurulacak hükümette bloğun botları birbirini destekler
##      ve ortak olarak önce birbirini seçer.
## Blokta gensoru ile düşen hükümetin ardından kurma süreci işaretlenir.
const BLOC_STEAL_BONUS := 2.5
const BLOC_OVERTAKE_BONUS := 3.0
static var _bloc_forming := false

## Blok şu an hedefte mi (insan hükümeti var)?
static func bloc_active() -> bool:
	if not GovernmentManager.has_government():
		return false
	var main := GovernmentManager.main_gov_peer_id
	return main != -1 and not MultiplayerManager.is_bot(main)

## Muhalefetteki (vekili olan) botlar.
static func bloc_members() -> Array:
	var members: Array = []
	for peer_id in GovernmentManager.voter_ids():
		if MultiplayerManager.is_bot(peer_id) and not CardManager.is_government_party(peer_id):
			members.append(peer_id)
	return members

## Bloğun en büyük botu: gensorudan sonra hükümeti kuracak aday.
static func bloc_leader() -> int:
	var leader := -1
	for peer_id in bloc_members():
		if leader == -1 or GovernmentManager.seats_of(peer_id) > GovernmentManager.seats_of(leader):
			leader = peer_id
	return leader

## Gensoru sonrası kurma sürecinde blok dayanışması sürüyor mu?
static func _bloc_solidarity() -> bool:
	if GovernmentManager.has_government() or CardManager.round_number <= 1:
		_bloc_forming = false
	return _bloc_forming

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
		if not CardManager.knows_leaning(bot, province_id):
			result[province_id] = {}
			continue
		var center := CardManager.province_center(province_id)
		var estimate := {}
		for axis in IdeologyAxes.AXES:
			estimate[axis] = signf(float(center.get(axis, 0.0))) * LEANING_ESTIMATE
		result[province_id] = estimate
	return result

## İdeolojinin tüm ülkedeki (bilinen) seçmen desteği (milletvekili ağırlıklı).
## Görüşü bilinmeyen iller sayılmaz: onları nötr saymak her yasayı (nötrden
## uzaklaştırdığı için) zararlı gösterir, botlar hep aynı yedek yasaya düşerdi.
static func _electoral_strength(ideology: Dictionary, known: Dictionary) -> float:
	var seats := _seats()
	var weighted := 0.0
	for province_id in seats.keys():
		var center: Dictionary = known.get(province_id, {})
		if center.is_empty():
			continue
		weighted += ElectionModel.support(ideology, center) * float(seats[province_id])
	return weighted / _total_seats()

static func _election_soon() -> bool:
	var next := GameRules.next_election_round(CardManager.round_number)
	return next != -1 and next - CardManager.round_number <= 1

# --- Ana hamle ------------------------------------------------------------------

## Manası bol olan bot için mana ucuzdur (birikip boşa durmasın), azsa değerlidir.
static func _mana_value(bot: int) -> float:
	return MANA_VALUE * clampf(4.0 / maxf(1.0, float(CardManager.mana_of(bot))), 0.2, 1.5)

## Dönüş: {"type": "card"} | {"type": "law", "law"} | {"type": "organization",
## "province"} | {"type": "miting", "province"} | |
## {"type": "draw"} | {"type": "pass"}
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
		# Yasa sıklığı sınırı (her gündem turunda herkes yasa sunup meclisi kilitlemesin).
		var rested: bool = CardManager.round_number - int(CardManager.law_rounds.get(bot, -99)) >= LAW_EVERY_ROUNDS
		if not rested:
			law = {}
		if not law.is_empty() and float(law["score"]) - GameRules.LAW_MANA_COST * mana_value > best_score:
			best = {"type": "law", "law": law["law"]}
			best_score = float(law["score"]) - GameRules.LAW_MANA_COST * mana_value

	var org := _best_organization(bot, known)
	if not org.is_empty() and float(org["score"]) - GameRules.ORG_MANA_COST * mana_value > best_score:
		best = {"type": "organization", "province": org["province"]}
		best_score = float(org["score"]) - GameRules.ORG_MANA_COST * mana_value

	if CardManager.can_invest(bot):
		var invest := _eval_investment(bot, known)
		if not invest.is_empty() and float(invest["score"]) - GameRules.INVEST_MANA_COST * mana_value > best_score:
			best = {"type": "invest", "province": invest["province"]}
			best_score = float(invest["score"]) - GameRules.INVEST_MANA_COST * mana_value

	if CardManager.can_censure(bot) and _censure_worth_it(bot):
		# Geçeceği hesaplanan gensoru: hükümet düşer, yeni kurma turu başlar.
		# Blokta gensoru planın son adımı: çok daha değerli.
		var censure_score := 7.0 if bloc_active() else 4.0
		if censure_score - GameRules.CENSURE_MANA_COST * mana_value > best_score:
			best = {"type": "censure"}
			_bloc_forming = bloc_active()
			best_score = censure_score - GameRules.CENSURE_MANA_COST * mana_value

	if CardManager.can_miting(bot):
		var miting := _eval_miting(bot, known)
		if not miting.is_empty() and float(miting["score"]) - GameRules.MITING_MANA_COST * mana_value > best_score:
			best = {"type": "miting", "province": miting["province"]}
			best_score = float(miting["score"]) - GameRules.MITING_MANA_COST * mana_value


	if CardManager.can_draw_for(bot):
		# Kart çekmek bedava (turda bir): el dolu değilse her zaman çek.
		if hand.size() < CardManager.MAX_HAND_SIZE - 1:
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
	for axis in _law_axes():
		for dir in [-1, 1]:
			var law_type := CardPresets.law_type(axis, dir)
			var sum := 0.0
			for province_id in seats.keys():
				if (known.get(province_id, {}) as Dictionary).is_empty():
					continue
				var alignment := PublicOpinion.law_alignment(known[province_id], axis, dir)
				sum += float(seats[province_id]) * PublicOpinion.law_proposer_delta(alignment, false)
			var value := sum / known_seats * confidence * CardManager.agenda_law_mult(law_type)
			if in_parliament:
				var pass_chance := _law_pass_chance(bot, law_type, known)
				value *= 1.0 + pass_chance * (PublicOpinion.LAW_PASSED_MULT - 1.0)
				# Kabul edilen yasa puan tablosuna ciddi puan yazar.
				value += pass_chance * CardManager.law_pass_score(CardManager.is_government_party(bot)) * 0.12
			var moved := mine.duplicate()
			moved[axis] = IdeologyAxes.clamp_value(float(mine.get(axis, 0)) + IdeologyAxes.LAW_PROPOSE_SHIFT * dir)
			value += (_electoral_strength(moved, known) - _electoral_strength(mine, known)) * 20.0
			var score := LAW_BASE_SCORE + value * 5.0 - _repeat_penalty(bot, law_type)
			if best.is_empty() or score > float(best["score"]):
				best = {"law": law_type, "score": score}
	# Tahmin gürültülü ya da bütün yasalar zararlı görünüyorsa kimlik yasası
	# (partinin belirgin ekseni) yedek seçenektir: meclis oyunu durmasın.
	var exploration := _exploration_law(bot, mine)
	if known_seats >= 60.0:
		exploration["score"] = 0.8
	if float(exploration["score"]) > float(best["score"]):
		return exploration
	return best

## Hiç il bilinmiyorken: parti kimliğini güçlendiren (en belirgin ekseninde)
## yasa; kimlik yoksa bota ve tura göre bir eksen. Çok iyi bir kart (ör. büyük
## ilde gözcü) varsa o önce gelir. Yasa partiyi kaydırdıkça kimlik oluşur.
static func _exploration_law(bot: int, mine: Dictionary) -> Dictionary:
	# En az kullandığı eksen; yön partinin o eksendeki eğilimi (yoksa bota göre).
	var best_law := ""
	var best_penalty := INF
	var offset := absi(bot) + CardManager.round_number
	var axes := _law_axes()
	for i in axes.size():
		var axis: String = axes[(i + offset) % axes.size()]
		var v := float(mine.get(axis, 0))
		var dir := 1 if v > 0 else (-1 if v < 0 else (1 if (absi(bot) / 7 + i) % 2 == 0 else -1))
		var law_type := CardPresets.law_type(axis, dir)
		var penalty := _repeat_penalty(bot, law_type)
		if penalty < best_penalty:
			best_penalty = penalty
			best_law = law_type
	return {"law": best_law, "score": 1.0}

## Yasa sunulabilecek eksenler: sadece gündemdeki eksen (gündem yoksa hepsi;
## zaten yasa sunulamaz).
static func _law_axes() -> Array:
	var current := CardManager.agenda_type()
	if current == "":
		return IdeologyAxes.AXES
	return [CardPresets.agenda_data(current)["axis"]]

## Botun son sunduğu yasalar: aynı yasayı (ve aynı ekseni) üst üste sunmasın.
static var _recent_laws: Dictionary = {}
const RECENT_LAW_MEMORY := 4

static func note_law(bot: int, law_type: String) -> void:
	var recent: Array = _recent_laws.get(bot, [])
	recent.append(law_type)
	while recent.size() > RECENT_LAW_MEMORY:
		recent.pop_front()
	_recent_laws[bot] = recent

static func _repeat_penalty(bot: int, law_type: String) -> float:
	var law := CardPresets.law_data(law_type)
	var penalty := 0.0
	for previous in _recent_laws.get(bot, []):
		if previous == law_type:
			penalty += 0.9
		elif not law.is_empty() and CardPresets.law_data(previous).get("axis", "") == law["axis"]:
			penalty += 0.35
	return penalty

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
		# Kalıcı oy bonusu (seviye farkı) + bilgi: 1. seviye ilin görüşünü, 2-3 anketi açar.
		var gain := PublicOpinion.org_activity(level + 1) - PublicOpinion.org_activity(level)
		var value := float(seats[province_id]) * (0.5 + closeness) / 30.0 * gain / 1.2 * 0.8
		if level == 0:
			value += 0.25 + float(seats[province_id]) / 40.0
		var score := 1.0 + value * (1.3 if _election_soon() else 1.0)
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
		CardPresets.POPULISM_CARD_TYPE:
			# Seçime az kala ya da hiç popülizm yokken değerli.
			if CardManager.populism_rounds_left(bot) > 0:
				return {}
			return {"score": 2.2 if _election_soon() else 1.4, "peer": -1, "province": ""}
		CardPresets.MANA_BONUS_CARD_TYPE:
			# Turu bitirir: manası azken, yapacak başka şey yokken kullanılır.
			return {"score": 0.9 if CardManager.mana_of(bot) < GameRules.MITING_MANA_COST else 0.3, "peer": -1, "province": ""}
		CardPresets.PROPAGANDA_CARD_TYPE:
			return _eval_propaganda(bot, known)
	if CardPresets.needs_target(card_type):
		return _eval_steal(bot, card_type)
	if card_type == CardPresets.REPUTATION_CARD_TYPE:
		return _eval_reputation(bot)
	if card_type == CardPresets.REBELLION_CARD_TYPE:
		return _eval_rebellion(bot)
	return {}

## Kaset: en büyük rakibin (blok varsa insan hükümetinin) ulusal desteğini vurur.
static func _eval_reputation(bot: int) -> Dictionary:
	var target := _attack_target(bot)
	if target == -1:
		return {}
	var score := 1.9 + PublicOpinion.REPUTATION_NATIONAL_DAMAGE / 4.0
	if bloc_active() and bloc_members().has(bot) and target == GovernmentManager.main_gov_peer_id:
		score += BLOC_STEAL_BONUS * 0.6
	return {"score": score, "peer": target, "province": ""}

## Parti içi isyan: yasa oylaması yakınken büyük bir rakibi çekimsere zorlar.
static func _eval_rebellion(bot: int) -> Dictionary:
	var target := _attack_target(bot)
	if target == -1 or not CardManager.has_seats(target):
		return {}
	var score := 1.2 + float(GovernmentManager.seats_of(target)) / float(maxi(1, GovernmentManager.total_seats())) * 3.0
	if CardManager.is_government_party(target) and not CardManager.is_government_party(bot):
		score += 0.5  # hükümetin yasasını zora sokar
	return {"score": score, "peer": target, "province": ""}

## Saldırı kartlarının hedefi: blok varsa hükümetin ana partisi, yoksa
## kendisi dışındaki en çok vekilli parti.
static func _attack_target(bot: int) -> int:
	if bloc_active() and bloc_members().has(bot):
		return GovernmentManager.main_gov_peer_id
	var target := -1
	for peer_id in CardManager.turn_order:
		if peer_id == bot:
			continue
		if target == -1 or GovernmentManager.seats_of(peer_id) > GovernmentManager.seats_of(target):
			target = peer_id
	return target

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
		# İl başkanlığıyla aynı ölçek (vekil/30). Zaten güçlü olduğu ilde getirisi azalır.
		var diminish := 1.0 / (1.0 + maxf(0.0, CardManager.activity_of(province_id, bot)) / 2.0)
		var value := expected / PublicOpinion.MITING_LOCAL * seats / 30.0 * (0.5 + closeness) * diminish \
			+ (1.0 - risk) * PublicOpinion.MITING_NATIONAL + risk * PublicOpinion.PROVOCATION_NATIONAL
		if value > best_value:
			best_value = value
			best_province = province_id
	if best_province == "":
		return {}
	var score := best_value * 1.4 * (1.4 if _election_soon() else 1.0)
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
	# İl başkanlığı ve mitingle aynı ölçek (vekil/30).
	return {"score": 0.8 + best_value / 30.0 * 1.2 * (1.3 if _election_soon() else 1.0), "peer": -1, "province": best_province}

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

## İktidardaysa en büyük muhalefetten, muhalefetteyse hükümetten çal.
static func _eval_steal(bot: int, card_type: String) -> Dictionary:
	if bloc_active() and bloc_members().has(bot):
		var bloc := _eval_bloc_steal(bot, card_type)
		if not bloc.is_empty():
			return bloc
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
	var r: Dictionary = CardManager.steal_range(bot, target, card_type)
	# Vekil sayısı bir sonraki seçime de momentum olarak yansır.
	var score := 1.8 + (float(r["min"]) + float(r["max"])) / 7.0
	# Muhalefetten hükümeti azınlığa düşürebilecek hamle çok değerli (gensoru yolu).
	if not in_gov and GovernmentManager.has_majority() and CardManager.is_government_party(target):
		var after: float = GovernmentManager.government_seats() - (float(r["min"]) + float(r["max"])) / 2.0
		if after * 2.0 <= GovernmentManager.total_seats():
			score += 3.0
	return {"score": score, "peer": target, "province": ""}

## Blok üyesi: hedef hükümetin ana partisi (insan). Bloğun lideri birinci
## partiyi geçebiliyorsa ya da hükümet azınlığa düşüyorsa hamle çok değerli.
static func _eval_bloc_steal(bot: int, card_type: String) -> Dictionary:
	var target := GovernmentManager.main_gov_peer_id
	if not CardManager.is_valid_steal_target(bot, target):
		return {}
	var r: Dictionary = CardManager.steal_range(bot, target, card_type)
	var avg: float = (float(r["min"]) + float(r["max"])) / 2.0
	var score := 1.8 + avg / 3.5 + BLOC_STEAL_BONUS
	var leader := bloc_leader()
	var leader_seats := float(GovernmentManager.seats_of(leader)) + (avg if leader == bot else 0.0)
	if leader_seats > float(GovernmentManager.seats_of(target)) - avg:
		score += BLOC_OVERTAKE_BONUS  # blok lideri birinci parti olur
	if GovernmentManager.has_majority() and (GovernmentManager.government_seats() - avg) * 2.0 <= GovernmentManager.total_seats():
		score += BLOC_OVERTAKE_BONUS  # hükümet çoğunluğu kaybeder
	return {"score": score, "peer": target, "province": ""}

## Gensoru ancak geçeceği hesaplanıyorsa ve hükümet yeni kurulmamışsa verilir;
## aynı tur içinde ikinci gensoru yok (her tur meclisi kilitlemesin).
static func _censure_worth_it(bot: int) -> bool:
	if CardManager.round_number - GovernmentManager.formed_round < 2:
		return false
	if GovernmentManager.censure_round == CardManager.round_number:
		return false
	var yes := GovernmentManager.seats_of(bot)
	var no := 0
	var main_gov := GovernmentManager.main_gov_peer_id
	for peer_id in GovernmentManager.voter_ids():
		if peer_id == bot:
			continue
		if CardManager.is_government_party(peer_id):
			no += GovernmentManager.seats_of(peer_id)
		elif bloc_active() and MultiplayerManager.is_bot(peer_id):
			yes += GovernmentManager.seats_of(peer_id)  # blok üyesi: kesin evet
		elif not MultiplayerManager.is_bot(peer_id):
			continue  # insanın oyu bilinmez: hesaba katılmaz
		elif ElectionModel.distance(_ideology(peer_id), _ideology(main_gov)) < 2.0:
			continue  # çekimser
		else:
			yes += GovernmentManager.seats_of(peer_id)
	return yes > no

# --- Oylama --------------------------------------------------------------------

static func choose_vote(bot: int) -> int:
	match GovernmentManager.proposal_kind:
		GovernmentManager.KIND_GOVERNMENT:
			if bot == GovernmentManager.proposal_peer_id or GovernmentManager.proposal_partner_ids().has(bot):
				return GovernmentManager.VOTE_YES
			if _bloc_solidarity() and MultiplayerManager.is_bot(GovernmentManager.proposal_peer_id):
				return GovernmentManager.VOTE_YES  # blok, kendi botunun hükümetini destekler
			var pm := int(GovernmentManager.proposal_assignments.get(GovernmentPresets.POST_PM, GovernmentManager.proposal_peer_id))
			var d := ElectionModel.distance(_ideology(bot), _ideology(pm))
			if d < 2.5:
				return GovernmentManager.VOTE_YES
			if d < 4.0:
				return GovernmentManager.VOTE_ABSTAIN
			return GovernmentManager.VOTE_NO
		GovernmentManager.KIND_CENSURE:
			if bot == GovernmentManager.proposal_peer_id:
				return GovernmentManager.VOTE_YES
			if CardManager.is_government_party(bot):
				return GovernmentManager.VOTE_NO
			if bloc_active():
				_bloc_forming = true
				return GovernmentManager.VOTE_YES
			return _censure_vote(bot)
		GovernmentManager.KIND_LAW:
			if bot == GovernmentManager.proposal_peer_id:
				return GovernmentManager.VOTE_YES
			return _best_law_vote(bot, GovernmentManager.proposal_law, GovernmentManager.proposal_peer_id,
				GovernmentManager.proposal_gov_ids, _known_centers(bot))
	return GovernmentManager.VOTE_ABSTAIN

## Muhalefetteki botun gensoru oyu. Hükümetin düşmesi ona yeni bir hükümet
## şansı verir: kendisi ya da kendisine hükümetten DAHA YAKIN olan gensoru
## sahibi hükümet kurabilir. Bu yüzden varsayılan EVET'tir; sadece hükümet
## ideolojik olarak çok yakınken ve gensoruyu veren belirgin biçimde uzakken
## çekimser kalır.
static func _censure_vote(bot: int) -> int:
	var gov := GovernmentManager.main_gov_peer_id
	if gov == -1:
		return GovernmentManager.VOTE_YES
	var d_gov := ElectionModel.distance(_ideology(bot), _ideology(gov))
	var d_prop := ElectionModel.distance(_ideology(bot), _ideology(GovernmentManager.proposal_peer_id))
	# Muhalefetin en büyük partisiyse hükümet kurma sırası ona gelebilir.
	var biggest_in_opposition := true
	for peer_id in GovernmentManager.voter_ids():
		if peer_id == bot or CardManager.is_government_party(peer_id):
			continue
		if GovernmentManager.seats_of(peer_id) > GovernmentManager.seats_of(bot):
			biggest_in_opposition = false
	if biggest_in_opposition and d_gov >= 1.0:
		return GovernmentManager.VOTE_YES
	if d_prop <= d_gov:
		return GovernmentManager.VOTE_YES  # gensoruyu veren, hükümetten daha yakın
	if d_gov < CENSURE_LOYALTY_DISTANCE:
		return GovernmentManager.VOTE_ABSTAIN  # hükümet çok yakın: düşürmeye ortak olmaz
	return GovernmentManager.VOTE_YES

# --- Hükümet kurma -------------------------------------------------------------

## İdeolojik olarak en yakın partilerle salt çoğunluğa ulaşana kadar koalisyon;
## bakanlıklar sandalyeyle orantılı. Reddedilince sonraki teklifte aday sırası
## kaydırılır (aynı teklifi tekrar tekrar sunmasın).
static func build_government(bot: int) -> Dictionary:
	var total := GovernmentManager.total_seats()
	var mine := _ideology(bot)
	var candidates: Array = GovernmentManager.voter_ids()
	candidates.erase(bot)
	var bloc := _bloc_solidarity()
	candidates.sort_custom(func(a, b):
		# Blok dayanışmasında önce diğer botlar ortak seçilir.
		if bloc and MultiplayerManager.is_bot(a) != MultiplayerManager.is_bot(b):
			return MultiplayerManager.is_bot(a)
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
