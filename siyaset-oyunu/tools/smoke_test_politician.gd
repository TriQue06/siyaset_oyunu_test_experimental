extends SceneTree
## SİYASETÇİ PROFİLİ TESTİ: harita oyun başında kurulur, memleket, meslek ve kişilik
## kuralları oyuna doğru yansır (bkz. PP).
##   godot --headless --path . --script res://tools/smoke_test_politician.gd

var _failed := 0
## Autoload'lardan sonra yüklenir (sınıf autoload adlarını kullanıyor).
var PP

func check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_failed += 1
	print("  [%s]  %s%s" % ["OK" if ok else "HATA", label, ("  -> " + detail) if detail != "" else ""])

func _initialize() -> void:
	load("res://scripts/bot_brain.gd").skill_variance = false
	await process_frame
	PP = load("res://scripts/politician_presets.gd")
	var mm = root.get_node("MultiplayerManager")
	var cm = root.get_node("CardManager")
	cm.allow_temporary_parties = false
	var pm = root.get_node("PartyManager")
	var gmap = root.get_node("GameMap")
	root.get_node("BotManager").set_process(false)

	print("=== SIYASETCI PROFILI ===")
	check("7 meslek, 3 kisilik, hepsinin metni var", _profiles_ok())
	mm.start_offline("Barış")
	for i in 3:
		mm.add_bot()
	mm.start_game()
	check("harita oyun baslarken kuruldu", mm.game_map_seed != 0 and not gmap.province_ids().is_empty())
	var map_before: Array = gmap.province_ids().duplicate()
	var home := String(gmap.province_ids()[0])
	pm.set_my_politician(PP.make("Ayla", "Gökyelken", "is_insani", home, "f", "teknokrat"))
	var core: Array = ["isci", "ilerici"]
	pm.set_party_and_ready("Yeni Yol", 3, Color.WHITE, Color("F20C1F"), core, true)
	var me: int = mm.owner_id
	check("oyun basladi", mm.stage == mm.Stage.IN_GAME)
	check("oyun ayni haritada", gmap.province_ids() == map_before)
	check("siyasetci parti verisinde korundu", PP.background_of(me) == "is_insani" and PP.trait_of(me) == "teknokrat",
		str(pm.politicians.get(me, {})))
	check("memlekette 2. seviye teskilat", cm.organization_level(home, me) == PP.HOMETOWN_ORG_LEVEL)
	# Sıra oyunda ilk bendeyse ilk tur geliri memleket teşkilatı kurulmadan
	# verilir (teşkilat geliri yok): iki durum da geçerli.
	var first_income: float = cm.turn_income(me) - cm.org_income(me) if cm.current_turn_peer_id() == me else 0.0
	var base: float = GameRules.FUNDS_START + PP.BUSINESS_START_FUNDS
	check("is insani ek parayla basladi", is_equal_approx(cm.funds_of(me), base + first_income)
		or is_equal_approx(cm.funds_of(me), base + cm.turn_income(me)),
		str(cm.funds_of(me)))
	var neighbor := String(gmap.neighbors().get(home, [""])[0])
	check("hemsehri destegi memlekette", is_equal_approx(PP.hometown_activity(home, me), PP.HOMETOWN_ACTIVITY))
	check("komsu il etkilenmez", PP.hometown_activity(neighbor, me) == 0.0)
	check("is insani her tur ek gelir alir", cm.turn_income(me) >= PP.BUSINESS_TURN_INCOME)
	check("teknokrat vergi tepkisini azaltir", is_equal_approx(PP.party_effect(me, "tax_mood"), 0.8))
	check("cekirdek gruplar korundu (botlar az pay alabilir)", float(pm.parties[me]["groups"]["isci"]) <= VoterGroups.CORE_START + 0.001 and float(pm.parties[me]["groups"]["isci"]) > VoterGroups.CORE_START * 0.8, str(pm.parties[me]["groups"]["isci"]))
	check("aktiviteye eklendi", cm.activity_of(home, me) >= PublicOpinion.org_activity(2) + PP.HOMETOWN_ACTIVITY - 0.01,
		"%.2f" % cm.activity_of(home, me))
	var all_bots_ok := true
	for bot in mm.bot_ids():
		var bh: String = PP.hometown_of(bot)
		if bh == "" or cm.organization_level(bh, bot) != PP.HOMETOWN_ORG_LEVEL \
				or not PP.is_valid_background(PP.background_of(bot)) or not PP.is_valid_trait(PP.trait_of(bot)):
			all_bots_ok = false
	check("botlarin da siyasetcisi, memleketi, meslegi ve kisiligi var", all_bots_ok)

	# Geçmiş avantajları.
	var bot: int = mm.bot_ids()[0]
	cm.turmoil.erase(bot)
	pm.politicians[bot]["background"] = "emekli_subay"
	pm.politicians[bot]["trait"] = "teknokrat"
	cm._add_turmoil(bot, 1.0)
	check("emekli subay karisikligi az biriktirir", is_equal_approx(cm.turmoil_of(bot), 0.75))
	check("emekli subaya karalama az isler", is_equal_approx(PP.party_effect(bot, "propaganda_in"), 0.75))
	pm.politicians[bot]["background"] = "belediye_baskani"
	var bh: String = PP.hometown_of(bot)
	check("belediye baskani teskilat bonusu", is_equal_approx(cm.org_bonus(bh, bot),
		PublicOpinion.org_activity(2) * 1.1) or cm.populism_rounds_left(bot) > 0)
	var orgs_before: int = cm.org_count(bot)
	cm._grant_mayor_orgs(bot, bh)
	var expected: int = maxi(1, int(round(gmap.province_ids().size() * PP.MAYOR_ORG_SHARE)))
	check("belediye baskani rastgele illerde teskilat alir", cm.org_count(bot) - orgs_before == expected,
		"%d -> %d (beklenen +%d)" % [orgs_before, cm.org_count(bot), expected])
	pm.politicians[bot]["background"] = "sendikaci"
	pm.politicians[bot]["trait"] = "hatip"
	check("sendikaci + hatip miting carpani", is_equal_approx(PP.effect(bot, "miting"), 1.25 * 1.1))
	check("hatip grup toplantisi", is_equal_approx(PP.effect(bot, "speech"), 1.2))
	check("sendikaci iscilere hitap", is_equal_approx(PP.group_appeal(bot, "isci"), 1.1) and is_equal_approx(PP.group_appeal(bot, "isveren"), 1.0))
	pm.politicians[bot]["background"] = "aktivist"
	pm.politicians[bot]["trait"] = "sert"
	check("aktivist: miting guclu, yasa ve toplanti zayif", is_equal_approx(PP.effect(bot, "miting"), 1.25 * 1.05)
		and is_equal_approx(PP.effect(bot, "law"), 0.75) and is_equal_approx(PP.effect(bot, "speech"), 0.75))
	check("aktivist genclere ve ilericilere hitap", is_equal_approx(PP.group_appeal(bot, "genc"), 1.1) and is_equal_approx(PP.group_appeal(bot, "ilerici"), 1.1))
	check("sert: karalama guclu, gelen karalama biraz guclu", is_equal_approx(PP.effect(bot, "propaganda_out"), 1.2)
		and is_equal_approx(PP.party_effect(bot, "propaganda_in"), 1.05))
	pm.politicians[bot]["background"] = "gazeteci"
	check("gazeteci kaset ve karalama", is_equal_approx(PP.effect(bot, "reputation_out"), 1.25) and is_equal_approx(PP.effect(bot, "propaganda_out"), 1.25 * 1.2))
	pm.politicians[bot]["background"] = "hukukcu"
	check("hukukcu vekil calmaya direnir", is_equal_approx(PP.party_effect(bot, "steal_in"), 0.75))
	check("kisilik verilmezse rastgele atanir", PP.is_valid_trait(String(PP.make("A", "B", "hukukcu", home)["trait"])))

	# Rastgele isim ve güvenilirlik.
	var all_ok := true
	var seen := {}
	for i in 500:
		var n: Dictionary = PP.random_name()
		seen[n["surname"]] = true
		if PP.is_banned_surname(String(n["surname"])) or String(n["first_name"]) == "":
			all_ok = false
	check("500 rastgele isimde yasakli soyad yok", all_ok)
	var males := 0
	for i in 4000:
		if PP.random_name()["gender"] == "m":
			males += 1
	check("botlarin ~%75'i erkek", absf(males / 4000.0 - 0.75) < 0.03, "%.3f" % (males / 4000.0))
	var gender_ok := true
	for i in 300:
		if PP.FEMALE_NAMES.has(PP.random_first_name("m")) or PP.MALE_NAMES.has(PP.random_first_name("f")):
			gender_ok = false
	check("ad secilen cinsiyete uyar (unisex ikisinde)", gender_ok and PP.names_for("m").has("Deniz") and PP.names_for("f").has("Deniz"))
	check("Umit ve Ozgur sadece erkek", not PP.names_for("f").has("Ümit") and not PP.names_for("f").has("Özgür") and PP.names_for("m").has("Ümit") and PP.names_for("m").has("Özgür"))
	check("istenen adlar var", PP.MALE_NAMES.has("Recep") and PP.MALE_NAMES.has("Necdet") and PP.FEMALE_NAMES.has("Meral") and PP.FEMALE_NAMES.has("Tansu"))
	var overlap := false
	for n in PP.MALE_NAMES:
		if PP.FEMALE_NAMES.has(n) or PP.UNISEX_NAMES.has(n):
			overlap = true
	check("erkek ve kadin listeleri ayrik", not overlap)
	check("soyadlar cesitli", seen.size() > 300, str(seen.size()))
	var yilmaz := false
	for i in 2000:
		if PP.random_surname() == "Yılmaz":
			yilmaz = true
	check("Yilmaz soyadi cikabilir", yilmaz)
	check("Karabulut gecerli", not PP.is_banned_surname("Karabulut"))
	check("Bayraktar, Soylu, Albayrak yasakli", PP.is_banned_surname("Bayraktar") and PP.is_banned_surname("Soylu") and PP.is_banned_surname("Albayrak"))
	check("elle yazilan gercek soyad kabul edilir (kara liste yalniz rastgelede)", PP.is_valid(PP.make("Ali", "Erdoğan", "sendikaci", home)))
	check("rastgele soyad kullanilani vermez", not PP.random_surname(["Gökyelken"]).is_empty())
	var bot_surnames := {}
	for b in mm.bot_ids():
		bot_surnames[PP.surname_of(b)] = true
	check("botlarin soyadlari farkli ve dolu", bot_surnames.size() == mm.bot_ids().size() and not bot_surnames.has(""))
	check("guvenilirlik 100 baslar", is_equal_approx(cm.credibility_of(me), 100.0))
	check("oy kaybinda dusus", is_equal_approx(cm.credibility_drop(20.0, 17.0), 11.0))
	check("oy artisinda dusus yok", cm.credibility_drop(17.0, 20.0) == 0.0)
	cm.credibility[me] = 100.0
	cm._update_credibility({me: 20.0}, {me: 15.0})
	check("guvenilirlik guncellendi", is_equal_approx(cm.credibility_of(me), 85.0), str(cm.credibility_of(me)))

	# 0.0.222: isim dili düğmesi.
	check("isim dili sirayla: tr -> en -> tr", PP.next_name_lang("tr") == "en" and PP.next_name_lang("en") == "tr")
	check("dil dugmesi dilin kendi adini yazar", PP.name_lang_title("tr") == "Türkçe" and PP.name_lang_title("en") == "English")
	var en_ok := true
	for i in 50:
		var first: String = PP.random_first_name("f", "", null, "en")
		var last: String = PP.random_surname([], null, "en")
		if not (PP.EN_FEMALE_NAMES + PP.EN_UNISEX_NAMES).has(first) or not PP.EN_SURNAMES.has(last) or PP.is_banned_surname(last):
			en_ok = false
	check("Ingilizce ad ve soyad uretilir, gercek siyasetci soyadi yok", en_ok)
	check("yabanci siyasetci soyadi kara listede (rastgele uretimde)", PP.is_banned_surname("Trump"))
	# 0.0.223: elle yazilan ad kara listeye takilmaz.
	check("elle yazilan kara liste soyadi gecerli", PP.is_valid(PP.make("Ahmet", "Soylu", String(PP.BACKGROUND_ORDER[0]), "b01")))

	print("")
	print("=== %s ===" % ("TUM TESTLER GECTI" if _failed == 0 else "%d TEST BASARISIZ" % _failed))
	quit(1 if _failed > 0 else 0)

func _profiles_ok() -> bool:
	for id in PP.BACKGROUND_ORDER:
		var info: Dictionary = PP.background(id)
		if String(info.get("title", "")) == "" or String(info.get("perk", "")) == "":
			return false
	for id in PP.TRAIT_ORDER:
		if String(PP.trait_info(id).get("perk", "")) == "":
			return false
	return PP.BACKGROUNDS.size() == 7 and PP.TRAITS.size() == 3
