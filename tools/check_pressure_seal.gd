extends Node
## Pressure Seal overlay: hidden without `pressure_seal`, visible with it, cool motes only while in heat.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const HEAT_ZONE := preload("res://scripts/campaign/heat_zone.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var game_state := get_node("/root/GameState")
	game_state.reset_progress()
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	add_child(player)
	await get_tree().process_frame
	await get_tree().process_frame
	var visuals := player.get_node("PressureSealVisuals") as PressureSealVisuals
	var overlay := visuals.get_node("SealOverlay") as AnimatedSprite2D
	var motes := visuals.get_child(1) as CPUParticles2D
	var failures := 0
	if overlay.visible:
		failures += _fail("overlay visible without the seal")
	game_state.unlock_ability(&"pressure_seal")
	await get_tree().process_frame
	if not overlay.visible:
		failures += _fail("overlay hidden with the seal")
	if motes.emitting:
		failures += _fail("motes emitting outside heat")
	var zone := Area2D.new()
	zone.set_script(HEAT_ZONE)
	add_child(zone)
	zone.set("_player", player)
	await get_tree().process_frame
	if not motes.emitting:
		failures += _fail("no cool motes inside heat while sealed")
	zone.queue_free()
	player.queue_free()
	game_state.reset_progress()
	await get_tree().process_frame
	print("check_pressure_seal: %s" % ("OK" if failures == 0 else "FAILED"))
	get_tree().quit(1 if failures else 0)


func _fail(message: String) -> int:
	push_error("check_pressure_seal: " + message)
	return 1
