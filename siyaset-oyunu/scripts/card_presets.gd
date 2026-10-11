extends Node
## Autoload. Kart ve hamle katalogu. Görseller normal PNG'ler (assets/cards/).
##
## KARTLAR: sırası gelen oyuncuya oyun bir kart verir; oynamanın bedeli CARD_MANA_COSTS.
## YATIRIM ve GENSORU da artık hamle (bkz. CardManager.invest / censure).
##   - POPÜLİZM BONUSU : POPULISM_ROUNDS tur kendi hamlelerinin iyi etkisi artar, kötüsü azalır.
##   - MANA BONUSU     : zayıf +MANA_BONUS_WEAK, güçlü +MANA_BONUS_STRONG mana.
##   - BONUS KART      : rastgele BONUS_CARD_DRAW kart daha çekilir.
##   - KART ÇALMA      : seçilen partinin elinden rastgele 1 kart çalınır (eli boşsa boşa gider).
## MİTİNG, YATIRIM, GENSORU kart değil, hamle; türleri hamlenin kimliği olarak durur.
##   - MİTİNG    : seçilen ilde güç kazandırır; provokasyon riski var.
##   - YATIRIM   : sadece hükümet partilerine gelir; seçilen ile yatırım.
##   - KARALAMA  : bir ilde bir partiyi karalar: ona eksi, oynayana artı.
##   - VEKİL ÇALMA / GENSORU : koşullu özel kartlar.
## YASA bir kart DEĞİL, bir hamle türüdür (bkz. CardManager.propose_law): bir
## SEÇMEN GRUBU seçilir. Meclis akışı metin tabanlı olduğu için yasa "law:grup"
## biçiminde bir metinle taşınır (bkz. law_type / law_data).
## Hangi kartın ne olasılıkla çekileceği CardManager._draw_weights'te.

## Bir başka partiden milletvekili çalar. Kullanılırken HEDEF parti seçilir.
const STEAL_WEAK_CARD_TYPE := "steal_weak"
const STEAL_STRONG_CARD_TYPE := "steal_strong"
const STEAL_CARD_TYPES: Array[String] = [
	STEAL_WEAK_CARD_TYPE,
	STEAL_STRONG_CARD_TYPE,
]

## Hedef PARTİ seçilen diğer saldırı kartları.
## Kaset: hedefin ulusal desteğini doğrudan düşürür, partide biraz KARIŞIKLIK çıkarır.
## İç karışıklık (isyan): hedefin ulusal desteği düşer ve partide çok KARIŞIKLIK
## çıkar (gizli değer; çok birikirse parti bölünür, bkz. CardManager.turmoil).
## Kart çalma: hedefin elinden rastgele bir kart alınır.
const REPUTATION_CARD_TYPE := "kaset"
const REBELLION_CARD_TYPE := "isyan"
const CARD_THEFT_CARD_TYPE := "kart_calma"

## Hükümeti düşürmek için meclise getirilen teklif.
const CENSURE_CARD_TYPE := "gensoru"
const MITING_CARD_TYPE := "miting"
const INVEST_CARD_TYPE := "yatirim"
const PROPAGANDA_CARD_TYPE := "karalama"
## ERKEN SEÇİM: meclise getirilir, kabul edilirse dönem sonunda sandığa gidilir
## ve seçim takvimi o tarihten itibaren yeniden işler.
const EARLY_ELECTION_CARD_TYPE := "erken_secim"

## Hedefsiz bonus kartlar: seçip tekrar dokununca oynanır.
const POPULISM_CARD_TYPE := "populizm"
const MANA_BONUS_CARD_TYPE := "mana_bonusu"
const MANA_BONUS_STRONG_CARD_TYPE := "mana_bonusu_guclu"
const BONUS_CARD_TYPE := "bonus_kart"

## GÜNDEMLER: her seçmen grubu için bir sıcak konu (bkz. GameRules gündem
## takvimi). Gündem bir grubun derdidir ama yasa o grubun ÇİFTİNDEKİ iki
## gruptan biri için sunulabilir (ör. "Hayat Pahalılığı": işçi ya da işveren).
const AGENDAS := {
	"gundem_isci": {"group": "isci", "title": "Hayat Pahalılığı",
		"text": "Maaşlar eriyor, çalışanlar ücret artışı bekliyor."},
	"gundem_isveren": {"group": "isveren", "title": "Vergi ve Bürokrasi Yükü",
		"text": "Esnaf ve sanayici vergi ve kırtasiyeden bunaldı."},
	"gundem_genc": {"group": "genc", "title": "Genç İşsizliği",
		"text": "Mezunlar iş bulamıyor, yurtlar dolu."},
	"gundem_emekli": {"group": "emekli", "title": "Emekli Maaşları",
		"text": "Emekliler aylıkların geçinmeye yetmediğini söylüyor."},
	"gundem_dindar": {"group": "dindar", "title": "İnanç ve Eğitim Tartışması",
		"text": "Din eğitimi ve inanç özgürlüğü ülkenin gündeminde."},
	"gundem_ilerici": {"group": "ilerici", "title": "Ayrımcılık Tartışması",
		"text": "Eşit yurttaşlık ve ayrımcılık yasağı tartışılıyor."},
	"gundem_ozerkci": {"group": "ozerkci", "title": "Yerelden Yönetim Talebi",
		"text": "Şehirler kendi kararlarını kendileri vermek istiyor."},
	"gundem_milliyetci": {"group": "milliyetci", "title": "Güvenlik ve Birlik",
		"text": "Güvenlik kaygısı güçlü bir merkez talebini büyüttü."},
}

const CARD_TYPES: Array[String] = [
	"steal_weak",
	"steal_strong",
	"kaset",
	"isyan",
	"gensoru",
	"miting",
	"yatirim",
	"karalama",
	"populizm",
	"mana_bonusu",
	"mana_bonusu_guclu",
	"bonus_kart",
	"kart_calma",
]

const LAW_PREFIX := "law:"

const CARD_NATIVE_SIZE := Vector2(72, 96)

## Vekil çalma kartlarının çaldığı milletvekili aralığı (her değer eşit olası).
const STEAL_RANGES := {
	"steal_weak": {"min": 2, "max": 4},
	"steal_strong": {"min": 10, "max": 16},
}

## Seçmen grubu yakınlığına göre aralık (bkz. VoterGroups.party_closeness):
## yukarıdaki STEAL_RANGES NÖTR hâl (orta yakınlık); iki partinin grup
## yakınlıkları birebir aynıysa STEAL_RANGES_CLOSE (2 kat), çok farklıysa
## STEAL_RANGES_FAR. Arası doğrusal (bkz. steal_range).
const STEAL_RANGES_CLOSE := {
	"steal_weak": {"min": 4, "max": 8},
	"steal_strong": {"min": 20, "max": 32},
}
const STEAL_RANGES_FAR := {
	"steal_weak": {"min": 1, "max": 2},
	"steal_strong": {"min": 6, "max": 9},
}

## closeness: 0 (en uzak) .. 0.5 (nötr) .. 1 (aynı grup profili) -> {"min", "max"}.
func steal_range(card_type: String, closeness: float) -> Dictionary:
	var mid: Dictionary = STEAL_RANGES.get(card_type, {})
	if mid.is_empty():
		return {}
	var other: Dictionary = STEAL_RANGES_CLOSE[card_type] if closeness >= 0.5 else STEAL_RANGES_FAR[card_type]
	var t: float = absf(closeness - 0.5) * 2.0
	return {"min": int(round(lerpf(float(mid["min"]), float(other["min"]), t))),
		"max": int(round(lerpf(float(mid["max"]), float(other["max"]), t)))}

## Kartın elden oynanma bedeli (mana).
const CARD_MANA_COSTS := {
	"karalama": 10,
	"populizm": 10,
	"mana_bonusu": 0,
	"mana_bonusu_guclu": 0,
	"bonus_kart": 0,
	"kart_calma": 10,
	"steal_weak": 10,
	"steal_strong": 30,
	"kaset": 20,
	"isyan": 10,
	"erken_secim": 30,
}

## Kendi görseli olmayan kartlar geçici olarak başka bir kartın görselini kullanır.
const CARD_ART_ALIAS := {
	"kaset": "steal_medium",
	"isyan": "gensoru",
	"erken_secim": "gensoru",
	"mana_bonusu_guclu": "mana_bonusu",
	"bonus_kart": "anket",
	"kart_calma": "gozcu",
}

var _card_textures: Dictionary = {}

func _ready() -> void:
	for card_type in CARD_TYPES:
		var path := "res://assets/cards/politic_card_%s.png" % String(CARD_ART_ALIAS.get(card_type, card_type))
		if ResourceLoader.exists(path):
			_card_textures[card_type] = load(path)
		else:
			push_warning("Kart görseli bulunamadı: %s" % path)

func get_card_texture(card_type: String) -> Texture2D:
	return _card_textures.get(card_type, _card_textures.get(MITING_CARD_TYPE))

## Bu kart oynanırken hedef PARTİ seçilmesi gerekiyor mu? (vekil çalma)
func needs_target(card_type: String) -> bool:
	return STEAL_CARD_TYPES.has(card_type)

## Hedef parti seçilen TÜM kartlar: vekil çalma + kaset + iç karışıklık + kart çalma.
func needs_party_target(card_type: String) -> bool:
	return needs_target(card_type) or card_type in [REPUTATION_CARD_TYPE, REBELLION_CARD_TYPE, CARD_THEFT_CARD_TYPE]

## Bu kart oynanırken haritadan İL seçilmesi gerekiyor mu? (Karalamada ilden
## sonra hedef parti de seçilir.)
func needs_province_target(card_type: String) -> bool:
	return card_type in [MITING_CARD_TYPE, INVEST_CARD_TYPE, PROPAGANDA_CARD_TYPE]

## Hedef gerektirmeyen bonus kart mı? (popülizm, mana bonusu)
func is_self_card(card_type: String) -> bool:
	return card_type in [POPULISM_CARD_TYPE, MANA_BONUS_CARD_TYPE, MANA_BONUS_STRONG_CARD_TYPE, BONUS_CARD_TYPE,
		EARLY_ELECTION_CARD_TYPE]

## Meclise sunulan (oylanan) kart mı?
func is_parliament_card(card_type: String) -> bool:
	return card_type == EARLY_ELECTION_CARD_TYPE or is_law_card(card_type)

## KRİZLER: bir seçmen grubunun acil talebi (bkz. CardManager.crisis).
## Gündemle birlikte açılır, gündemdeki çiftten bir grubu seçer.
const CRISES := {
	"kriz_isci": {"group": "isci", "title": "Fabrika Kapanmaları",
		"text": "Fabrikalar kapanıyor, işçiler meydanlarda."},
	"kriz_isveren": {"group": "isveren", "title": "İflas Dalgası",
		"text": "Küçük işletmeler peş peşe kepenk kapatıyor."},
	"kriz_genc": {"group": "genc", "title": "Gençlik Protestoları",
		"text": "Öğrenciler barınma ve iş talebiyle sokakta."},
	"kriz_emekli": {"group": "emekli", "title": "Sağlık Sistemi Krizi",
		"text": "Hastaneler doldu, emekliler ilaç bulamıyor."},
	"kriz_dindar": {"group": "dindar", "title": "İnanç Gerginliği",
		"text": "İbadet yerlerine yönelik kısıtlamalar tepki çekiyor."},
	"kriz_ilerici": {"group": "ilerici", "title": "Nefret Saldırıları",
		"text": "Ayrımcı saldırılar eşit yurttaşlık talebini büyüttü."},
	"kriz_ozerkci": {"group": "ozerkci", "title": "Bölgesel Ayaklanma",
		"text": "Bölgeler yerinden yönetim talebiyle sokakta."},
	"kriz_milliyetci": {"group": "milliyetci", "title": "Güvenlik Krizi",
		"text": "Olaylar güçlü bir devlet talebini artırdı."},
}

## {"group", "title", "text", "group_title", "opposite", "pair"} ya da boş sözlük.
func crisis_data(crisis_type: String) -> Dictionary:
	if not CRISES.has(crisis_type):
		return {}
	return _with_group_info(CRISES[crisis_type])

func agenda_data(agenda_type: String) -> Dictionary:
	if not AGENDAS.has(agenda_type):
		return {}
	return _with_group_info(AGENDAS[agenda_type])

func _with_group_info(source: Dictionary) -> Dictionary:
	var data: Dictionary = source.duplicate()
	var group := String(data["group"])
	data["group_title"] = VoterGroups.title(group)
	data["opposite"] = VoterGroups.opposite(group)
	data["pair"] = VoterGroups.pair_of(group)
	return data

## Gündemde yasa sunulabilecek iki grup (gündemin çifti).
func agenda_groups(agenda_type: String) -> Array:
	var data := agenda_data(agenda_type)
	if data.is_empty():
		return []
	return (VoterGroups.PAIRS[data["pair"]] as Array).duplicate()

## Gündemin yasalar üzerindeki etkisini anlatan kısa metin.
func agenda_effect_text(agenda_type: String) -> String:
	var groups := agenda_groups(agenda_type)
	if groups.size() != 2:
		return ""
	return "sadece %s ya da %s için yasa sunulabilir" % [VoterGroups.title(groups[0]), VoterGroups.title(groups[1])]

func is_censure_card(card_type: String) -> bool:
	return card_type == CENSURE_CARD_TYPE

## Yasa hamlesinin türü: "law:isci".
func law_type(group: String) -> String:
	return LAW_PREFIX + group

func is_law_card(card_type: String) -> bool:
	return not law_data(card_type).is_empty()

## {"group", "title", "group_title", "opposite", "problem"} ya da (yasa değilse) boş sözlük.
func law_data(card_type: String) -> Dictionary:
	if not card_type.begins_with(LAW_PREFIX):
		return {}
	var group := card_type.substr(LAW_PREFIX.length())
	if not VoterGroups.is_group(group):
		return {}
	var info := VoterGroups.data(group)
	return {"group": group, "title": String(info["law_title"]), "group_title": VoterGroups.title(group),
		"opposite": VoterGroups.opposite(group), "problem": String(info["law_problem"])}

func card_cost(card_type: String) -> int:
	return int(CARD_MANA_COSTS.get(card_type, 0))

## weights: card_type -> ağırlık (>0). Ağırlıkla orantılı rastgele seçim.
func weighted_pick(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for card_type in weights.keys():
		total += maxf(0.0, float(weights[card_type]))
	if total <= 0.0:
		return MITING_CARD_TYPE
	var roll := rng.randf() * total
	for card_type in weights.keys():
		roll -= maxf(0.0, float(weights[card_type]))
		if roll <= 0.0:
			return card_type
	return weights.keys().back()

## Kartın görselinin üstüne yazılan kısa başlık (her kartta).
func card_short_title(card_type: String) -> String:
	match card_type:
		"populizm":
			return "POPÜLİZM\nBONUSU"
		"mana_bonusu":
			return "MANA BONUSU\nZAYIF"
		"mana_bonusu_guclu":
			return "MANA BONUSU\nGÜÇLÜ"
		"bonus_kart":
			return "BONUS\nKART"
		"kart_calma":
			return "KART\nÇALMA"
		"isyan":
			return "İÇ\nKARIŞIKLIK"
		"erken_secim":
			return "ERKEN\nSEÇİM"
		"steal_weak":
			return "VEKİL ÇALMA\nZAYIF"
		"steal_medium":
			return "VEKİL ÇALMA\nORTA"
		"steal_strong":
			return "VEKİL ÇALMA\nGÜÇLÜ"
	return card_title(card_type).to_upper()

func card_title(card_type: String) -> String:
	if is_law_card(card_type):
		return String(law_data(card_type)["title"])
	match card_type:
		"steal_weak":
			return "Vekil Çalma"
		"steal_strong":
			return "Vekil Çalma (Güçlü)"
		"kaset":
			return "Kaset / İtibar Suikastı"
		"isyan":
			return "İç Karışıklık"
		"kart_calma":
			return "Kart Çalma"
		"bonus_kart":
			return "Bonus Kart"
		"mana_bonusu_guclu":
			return "Mana Bonusu (Güçlü)"
		"gensoru":
			return "Gensoru"
		"miting":
			return "Miting"
		"yatirim":
			return "Yatırım"
		"karalama":
			return "Karalama"
		"populizm":
			return "Popülizm Bonusu"
		"mana_bonusu":
			return "Mana Bonusu"
		"erken_secim":
			return "Erken Seçim"
	return card_type

## Yasanın hedef grubu: "İşçiler ve Sendikalar".
func law_direction_text(card_type: String) -> String:
	var law := law_data(card_type)
	if law.is_empty():
		return ""
	return String(law["group_title"])

## Yasanın kabul / ret etkisini anlatan metin (gerçek kurallardan).
func law_description(card_type: String) -> String:
	var law := law_data(card_type)
	if law.is_empty():
		return ""
	var group := String(law["group"])
	var backlash := float(VoterGroups.data(group).get("law_backlash", 0.4))
	return ("Sorun: %s.\nKabul edilirse %s yakınlığın +%.1f, %s −%.1f (ulusal, kalıcı; azalan getirili).\n"
		+ "Reddedilirse vaat olarak kalır: +%.1f / −%.1f. EVET diyenler bu gruba, HAYIR diyenler karşıt gruba biraz yaklaşır.") % [
		law["problem"], law["group_title"], PublicOpinion.LAW_GROUP_GAIN_PASSED,
		VoterGroups.title(String(law["opposite"])), PublicOpinion.LAW_GROUP_GAIN_PASSED * backlash,
		PublicOpinion.LAW_GROUP_GAIN_REJECTED, PublicOpinion.LAW_GROUP_GAIN_REJECTED * backlash]

## Karta dokununca gösterilen açıklama (kısa ve somut) + mana bedeli.
func card_description(card_type: String) -> String:
	var text := _card_effect_text(card_type)
	var cost := card_cost(card_type)
	if cost > 0 and not is_law_card(card_type):
		text += "\nBedel: %d mana" % cost
	return text

func _card_effect_text(card_type: String) -> String:
	if is_law_card(card_type):
		return law_description(card_type)
	if needs_target(card_type):
		var r: Dictionary = STEAL_RANGES[card_type]
		var close: Dictionary = STEAL_RANGES_CLOSE[card_type]
		var far: Dictionary = STEAL_RANGES_FAR[card_type]
		var cost_line := "Güçlü varyantta ulusal desteğin biraz düşer; normalde bedel yok." if card_type == STEAL_STRONG_CARD_TYPE \
			else "Bedeli yok; çalınan parti mağduriyetten biraz destek kazanır."
		return "Seçtiğin partiden vekil çal: %d-%d; aynı seçmen gruplarına hitap ediyorsa %d-%d'e kadar, çok farklıysa %d-%d.\n%s\nSeç, sonra soldaki bir partiye tıkla." % [
			int(r["min"]), int(r["max"]), int(close["min"]), int(close["max"]),
			int(far["min"]), int(far["max"]), cost_line]
	match card_type:
		REPUTATION_CARD_TYPE:
			return ("Seçtiğin partinin itibarını sarsan bir kaset sızar:" + "\n"
				+ "ulusal desteği %.1f puan düşer, partide karışıklık çıkar." + "\n"
				+ "Seç, sonra soldaki bir partiye tıkla.") % PublicOpinion.REPUTATION_NATIONAL_DAMAGE
		REBELLION_CARD_TYPE:
			return ("Seçtiğin partide iç karışıklık çıkar: ulusal desteği" + "\n"
				+ "%.1f puan düşer, parti içi huzursuzluk büyür." + "\n"
				+ "Karışıklık çok birikirse parti BÖLÜNEBİLİR." + "\n"
				+ "Seç, sonra soldaki bir partiye tıkla.") % PublicOpinion.REBELLION_NATIONAL_DAMAGE
		CARD_THEFT_CARD_TYPE:
			return ("Seçtiğin partinin elinden rastgele 1 kart çalarsın." + "\n"
				+ "Elinde hiç kart yoksa kart boşa gider." + "\n"
				+ "Seç, sonra soldaki bir partiye tıkla.")
		BONUS_CARD_TYPE:
			return "Rastgele %d kart daha çekersin (el doluysa sığdığı kadar).\nSeçmek için dokun, tekrar dokun: kullan." % GameRules.BONUS_CARD_DRAW
		MANA_BONUS_STRONG_CARD_TYPE:
			return "+%d mana kazan.\nSeçmek için dokun, tekrar dokun: kullan." % GameRules.MANA_BONUS_STRONG
		EARLY_ELECTION_CARD_TYPE:
			return ("Meclise erken seçim önerisi sunarsın." + "\n"
				+ "Kabul edilirse dönem sonunda sandığa gidilir ve" + "\n"
				+ "seçim takvimi o tarihten itibaren yeniden işler." + "\n"
				+ "Seçmek için dokun, tekrar dokun: kullan.")
		CENSURE_CARD_TYPE:
			return "Hükümeti düşürmek için gensoru ver.\nSeçmek için dokun, tekrar dokun: kullan."
		MITING_CARD_TYPE:
			return "Seçtiğin ilde güç kazan (+%.0f); partin ilin kalabalık seçmen gruplarına yaklaşır (ulusal), karşıt gruplarda biraz kaybeder.\nİlin seçmeni sana uzaksa provokasyon riski var." % PublicOpinion.MITING_LOCAL
		INVEST_CARD_TYPE:
			return "Hükümet: seçtiğin ile yatırım (yerel memnuniyet, grup yakınlığını değiştirmez).\nSen +%.0f, ortakların +%.1f güç kazanır." % [PublicOpinion.INVEST_LOCAL, PublicOpinion.INVEST_PARTNER_LOCAL]
		PROPAGANDA_CARD_TYPE:
			return "Bir ilde bir partiyi karala: ona eksi, sana artı.\nİlde güçlü olan partiye az işler."
		POPULISM_CARD_TYPE:
			return "%d dönem boyunca her şey güçlenir: miting, yasa, karalama hasarı ve teşkilat bonusu %d kat, vekil çalma %.1f kat; kötü sonuçlar %%%d azalır; bu sürede seçim olursa ulusal +%.1f.\nSeçmek için dokun, tekrar dokun: kullan." % [
				GameRules.POPULISM_ROUNDS, int(PublicOpinion.POPULISM_GOOD_MULT), PublicOpinion.POPULISM_STEAL_MULT,
				int(round((1.0 - PublicOpinion.POPULISM_BAD_MULT) * 100)), PublicOpinion.POPULISM_ELECTION_NATIONAL]
		MANA_BONUS_CARD_TYPE:
			return "+%d mana kazan.\nSeçmek için dokun, tekrar dokun: kullan." % GameRules.MANA_BONUS_WEAK
	return ""
