class_name GameLog
extends RefCounted
## OYUN GÜNLÜĞÜ DOSYASI (0.0.227): ESC menüsündeki "LOG İNDİR". Kurallar, partiler,
## bütün olaylar (oyuncu ve bot hamleleri, oylamalar, afetler, gizli türler
## dahil), seçim sonuçları ve dosyanın yazıldığı andaki durum tek metin dosyasında.
## Masaüstünde İndirilenler klasörüne, olmazsa oyunun veri klasörüne yazılır.

## Seçim sonucu günlüğe (her istemcide, seçim durumu gelince).
static func note_election() -> void:
	var cm = CardManager
	var lines := PackedStringArray()
	lines.append("=== %s SEÇİMİ (tur %d)%s ===" % [GameRules.election_label(cm.last_election_round), cm.last_election_round,
		" · ERKEN" if cm.last_election_was_early else ""])
	var ids: Array = cm.last_vote_shares.keys()
	ids.sort_custom(func(a, b): return float(cm.last_vote_shares[a]) > float(cm.last_vote_shares[b]))
	for pid in ids:
		lines.append("  %s  %%%.2f  %d vekil%s" % [_party(int(pid)), float(cm.last_vote_shares[pid]), int(cm.last_seats.get(pid, 0)),
			"" if cm.passed_threshold.has(pid) else "  (baraj altı)"])
	for aid in cm.last_election_alliances:
		var a: Dictionary = cm.last_election_alliances[aid]
		var names := PackedStringArray()
		for pid in a.get("members", []):
			names.append(_party(int(pid)))
		lines.append("  İttifak %s: %s" % [String(a.get("name", "")), ", ".join(names)])
	for line in lines:
		cm.full_log.append(line)

static func _party(pid: int) -> String:
	return "%s (%s%s)" % [String(PartyManager.data_of(pid).get("name", "?")), PoliticianPresets.display_name(pid),
		", bot" if MultiplayerManager.is_bot(pid) else ""]

static func build() -> String:
	var cm = CardManager
	var mm = MultiplayerManager
	var out := PackedStringArray()
	out.append("SİYASET OYUNU · OYUN GÜNLÜĞÜ")
	out.append("Sürüm %s · yazıldı %s" % [str(ProjectSettings.get_setting("application/config/version", "?")), Time.get_datetime_string_from_system(false, true)])
	out.append("")
	out.append("--- KURALLAR ---")
	out.append("Harita: %s · tohum %d · il %d" % [String(mm.world_settings.get("map_mode", "random")), GameMap.seed_value(), GameMap.province_ids().size()])
	out.append("Baraj %%%s · seçim %s yılda bir · %d seçim · meclis %d (ulusal liste %d) · sayım %s" % [String.num(mm.election_threshold, 1),
		GameRules.years_text(mm.election_interval), mm.election_count, cm.TOTAL_SEATS, ElectionModel.NATIONAL_LIST_SEATS, ElectionModel.method_title(mm.seat_method)])
	out.append("İttifaklar: %s · tur süresi %d sn" % ["açık" if cm.alliances_enabled else "kapalı", int(mm.world_settings.get("turn_seconds", 75))])
	out.append("")
	out.append("--- PARTİLER ---")
	for pid in cm.party_ids():
		var data: Dictionary = PartyManager.data_of(int(pid))
		var politician: Dictionary = PoliticianPresets.of(int(pid))
		out.append("%s · meslek %s · kişilik %s · memleket %s · çekirdek %s" % [_party(int(pid)),
			String(politician.get("background", "-")), String(politician.get("trait", "-")), GameMap.name_of(String(politician.get("hometown", ""))),
			", ".join(PackedStringArray(data.get("core", [])))])
	out.append("")
	out.append("--- OLAYLAR ---")
	out.append_array(cm.full_log)
	out.append("")
	out.append("--- ŞU ANKİ DURUM (%s) ---" % GameRules.period_label(maxi(1, cm.round_number)))
	for pid in cm.party_ids():
		var p := int(pid)
		var groups := PackedStringArray()
		var g: Dictionary = PartyManager.groups_of(p)
		for group in VoterGroups.GROUP_IDS:
			groups.append("%s %.1f" % [group, float(g.get(group, 0.0))])
		out.append("%s · vekil %d · son oy %%%.2f · ulusal puan %.2f · kasa %.1f · teşkilat %d · grup payı: %s" % [_party(p),
			int(cm.last_seats.get(p, 0)), float(cm.last_vote_shares.get(p, 0.0)), cm.national_of(p), cm.funds_of(p), cm.org_count(p), ", ".join(groups)])
	out.append("Hükümet: %s" % str(GovernmentManager.government))
	out.append("Ekonomi: %s" % str(cm.economy))
	return "\n".join(out)

## Dosyayı yazar; yazılan yolu ya da "" döner.
static func export_file() -> String:
	var name := "siyaset_oyunu_log_%s.txt" % Time.get_datetime_string_from_system(false, false).replace(":", "-").replace("T", "_")
	var dirs: Array = []
	var downloads := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if downloads != "" and DirAccess.dir_exists_absolute(downloads):
		dirs.append(downloads)
	dirs.append(OS.get_user_data_dir().path_join("logs"))
	var text := build()
	for dir in dirs:
		DirAccess.make_dir_recursive_absolute(String(dir))
		var path: String = String(dir).path_join(name)
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_string(text)
			file.close()
			return path
	return ""
