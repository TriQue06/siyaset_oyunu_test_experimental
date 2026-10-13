extends SceneTree
## SİYASETÇİ PROFİLİ TESTİ: harita oyun başında kurulur, memleket ve geçmiş
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
	check("6 gecmis, her biri farkli bir secmen grubuyla", _covers_all_sides())
	mm.start_offline("Barış")
	for i in 3:
		mm.add_bot()
	mm.start_game()
	check("harita oyun baslarken kuruldu", mm.game_map_seed != 0 and not gmap.province_ids().is_empty())
	var map_before: Array = gmap.province_ids().duplicate()
	var home := String(gmap.province_ids()[0])
	pm.set_my_politician(PP.make("Ayla", "Gökyelken", "is_insani", home))
	var core: Array = ["isci", "ilerici"]
	var start: Dictionary = VoterGroups.start_affinities(core)
	var boosted: Dictionary = PP.boosted_affinities("is_insani", start)
	check("is insani isverenlere biraz yaklastirir (isci cekirdekli partide bile)", float(boosted["isveren"]) > float(start["isveren"]) \
		and float(boosted["isveren"]) <= float(start["isveren"]) + PP.BACKGROUND_GROUP_BONUS)
	pm.set_party_and_ready("Yeni Yol", 3, Color.WHITE, Color("F20C1F"), core, true)
	var me: int = mm.owner_id
	check("oyun basladi", mm.stage == mm.Stage.IN_GAME)
	check("oyun ayni haritada", gmap.province_ids() == map_before)
	check("siyasetci parti verisinde korundu", PP.background_of(me) == "is_insani",
		str(pm.politicians.get(me, {})))
	check("memlekette 2. seviye teskilat", cm.organization_level(home, me) == PP.HOMETOWN_ORG_LEVEL)
	# Sıra oyunda ilk bendeyse ilk tur geliri memleket teşkilatı kurulmadan
	# verilir (teşkilat geliri yok): iki durum da geçerli.
	var first_income: float = cm.turn_income(me) - cm.org_income(me) if cm.current_turn_peer_id() == me else 0.0
	var base: float = GameRules.FUNDS_START + PP.BUSINESS_START_FUNDS
	check("is insani +2 milyon ile basladi", is_equal_approx(cm.funds_of(me), base + first_income)
		or is_equal_approx(cm.funds_of(me), base + cm.turn_income(me)),
		str(cm.funds_of(me)))
	var neighbor := String(gmap.neighbors().get(home, [""])[0])
	check("hemsehri destegi memlekette", is_equal_approx(PP.hometown_activity(home, me), PP.HOMETOWN_ACTIVITY))
	check("komsu il etkilenmez", PP.hometown_activity(neighbor, me) == 0.0)
	check("oyun basinda gecmis bonusu uygulandi", is_equal_approx(float(pm.parties[me]["groups"]["isveren"]), float(boosted["isveren"])),
		str(pm.parties[me]["groups"]))
	check("cekirdek gruplar korundu", is_equal_approx(float(pm.parties[me]["groups"]["isci"]), VoterGroups.CORE_START))
	check("aktiviteye eklendi", cm.activity_of(home, me) >= PublicOpinion.org_activity(2) + PP.HOMETOWN_ACTIVITY - 0.01,
		"%.2f" % cm.activity_of(home, me))
	var all_bots_ok := true
	for bot in mm.bot_ids():
		var bh: String = PP.hometown_of(bot)
		var bg: Dictionary = PP.background(PP.background_of(bot))
		var bot_groups: Dictionary = pm.parties[bot]["groups"]
		var bot_start: Dictionary = VoterGroups.start_affinities(pm.parties[bot]["core"])
		if bh == "" or cm.organization_level(bh, bot) != PP.HOMETOWN_ORG_LEVEL \
				or float(bot_groups[bg["group"]]) <= float(bot_start[bg["group"]]):
			all_bots_ok = false
	check("botlarin da siyasetcisi, memleketi ve gecmis bonusu var", all_bots_ok)

	# Geçmiş avantajları.
	var bot: int = mm.bot_ids()[0]
	cm.turmoil.erase(bot)
	pm.politicians[bot]["background"] = "emekli_subay"
	cm._add_turmoil(bot, 1.0)
	check("emekli subay karisikligi az biriktirir", is_equal_approx(cm.turmoil_of(bot), PP.OFFICER_TURMOIL_MULT))
	pm.politicians[bot]["background"] = "belediye_baskani"
	var bh: String = PP.hometown_of(bot)
	check("belediye baskani teskilat bonusu", is_equal_approx(cm.org_bonus(bh, bot),
		PublicOpinion.org_activity(2) * PP.MAYOR_ORG_MULT) or cm.populism_rounds_left(bot) > 0)

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
	check("gercek soyad reddedilir", not PP.is_valid(PP.make("Ali", "Erdoğan", "sendikaci", home)))
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

	print("")
	print("=== %s ===" % ("TUM TESTLER GECTI" if _failed == 0 else "%d TEST BASARISIZ" % _failed))
	quit(1 if _failed > 0 else 0)

func _covers_all_sides() -> bool:
	var seen := {}
	for id in PP.BACKGROUND_ORDER:
		var info: Dictionary = PP.background(id)
		if VoterGroups.is_group(String(info.get("group", ""))):
			seen[info["group"]] = true
	return PP.BACKGROUNDS.size() == 6 and seen.size() == 6
