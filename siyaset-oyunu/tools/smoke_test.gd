extends SceneTree
## Headless smoke test: tüm sahneleri tek tek yükleyip GERÇEKTEN ağaca ekler
## (sadece instantiate() yetmez — _ready() ancak ağaca eklenince çalışır).
## Script parse/runtime hatalarını (örn. eksik %UniqueName) yakalar.
## `godot --headless --script res://tools/smoke_test.gd` ile çalıştırılır.

func _initialize() -> void:
	var scenes := [
		"res://scenes/Lobby.tscn",
		"res://scenes/RoomSetup.tscn",
		"res://scenes/RoomLobby.tscn",
		"res://scenes/Map.tscn",
		"res://scenes/SettingsOverlay.tscn",
		"res://scenes/SceneTransition.tscn",
		"res://scenes/PartySetup.tscn",
		"res://scenes/GameScreen.tscn",
		"res://scenes/ElectionResults.tscn",
	]
	for path in scenes:
		print("--- loading ", path, " ---")
		var packed: PackedScene = load(path)
		if packed == null:
			print("FAILED TO LOAD: ", path)
			continue
		var instance := packed.instantiate()
		root.add_child(instance)
		print("ready OK: ", instance)
		await process_frame
		await process_frame
		instance.queue_free()
		await process_frame
	print("=== SMOKE TEST DONE ===")
	quit()
