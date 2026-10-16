extends SceneTree
## Türkiye haritaları (0.0.219): altıgen ve net mod, sabit il vekilleri, ulusal liste.
var fails := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String, detail: String = "") -> void:
	if not ok:
		fails += 1
	print(("  [OK]  " if ok else "  [HATA] ") + label + ("  -> " + detail if detail != "" else ""))
func run() -> void:
	var mm = root.get_node("MultiplayerManager")
	var gm = root.get_node("GameMap")
	var cm = root.get_node("CardManager")
	mm.offline_mode = true
	mm.owner_id = 1
	mm.is_host = true
	check(mm.world_settings["map_mode"] == "random", "varsayilan harita rastgele")
	for mode in ["turkiye_altigen"]:
		print("=== ", mode, " ===")
		mm._apply_world_settings(mm._world_with("map_mode", mode))
		check(int(mm.world_settings["national_seats"]) == 0, "Turkiye'ye gecince ulusal liste 0 baslar")
		gm.generate_new(12345)
		var ids: Array = gm.province_ids()
		check(ids.size() == 81, "81 il", str(ids.size()))
		var total := 0
		var names := {}
		var empty := []
		var lonely := []
		for id in ids:
			total += gm.seats_of(id)
			names[gm.name_of(id)] = id
			if gm.region_cells(id).is_empty():
				empty.append(gm.name_of(id))
			if (gm.neighbors()[id] as Array).is_empty():
				lonely.append(gm.name_of(id))
		check(total == 600, "il vekilleri toplami 600 (koltuk_verisi)", str(total))
		check(names.has("İstanbul") and gm.seats_of(names["İstanbul"]) >= 90, "Istanbul cevreleri tek ilde toplandi", str(gm.seats_of(names.get("İstanbul", ""))))
		check(names.has("Bayburt") and gm.seats_of(names["Bayburt"]) == 1, "Bayburt 1 vekil")
		check(empty.is_empty(), "her ilin hucresi var", str(empty))
		check(lonely.is_empty(), "her ilin komsusu var", str(lonely))
		check(gm.province_at(gm.center_of(names["Ankara"])) == names["Ankara"], "Ankara'nin vekil noktasi Ankara'da")
		check(gm.is_coastal(names["İzmir"]) and not gm.is_coastal(names["Ankara"]), "Izmir kiyi, Ankara ic")
		check(gm.map_size().x > 700.0 and gm.map_size().x < 820.0, "harita genisligi rastgele haritayla ayni olcekte", str(gm.map_size()))
		check(gm.data.size() == 2 and gm.data["preset"] == mode, "agda yalniz preset + tohum gider", str(gm.data.keys()))
		# Ağdan gelen veri istemcide aynı haritayı kurar.
		var sent: Dictionary = gm.data.duplicate()
		gm.set_data({"seed": 1, "cols": 2, "rows": 1, "cells": [0, -1], "regions": [{"id": "b01", "name": "x", "seats": 3}]})
		gm.set_data(sent)
		check(gm.province_ids().size() == 81, "istemci preset'ten haritayi kurdu")
		mm._apply_world_settings(mm._world_with("national_seats", 100))
		cm.init_game()
		check(cm.TOTAL_SEATS == 700, "toplam meclis = 600 il + 100 ulusal", str(cm.TOTAL_SEATS))
		check(gm.province_ids().size() == 81, "yeni oyun Turkiye haritasiyla basladi")
	check(not mm.WORLD_OPTIONS["map_mode"].has("turkiye_net"), "net harita kaldirildi")
	mm._apply_world_settings(mm._world_with("map_mode", "random"))
	check(int(mm.world_settings["national_seats"]) == int(mm.WORLD_DEFAULTS["national_seats"]), "rastgele haritaya donunce ulusal liste varsayilana doner")
	gm.generate_new(12345)
	check(gm.province_ids().size() != 81 or not gm.is_turkey(), "rastgele harita yeniden uretilir")
	print("")
	print("SONUC: ", "TUM TESTLER GECTI" if fails == 0 else "%d HATA" % fails)
	quit(1 if fails > 0 else 0)
