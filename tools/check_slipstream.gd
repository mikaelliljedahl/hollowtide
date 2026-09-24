extends Node
## Slipstream presentation: Ball form hides the rolling sprite and shows the droplet,
## standing form restores the sprite. Collision/form rules are untouched.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	GameState.reset_progress()
	GameState.unlock_ability(&"slipstream")
	var player := PLAYER_SCENE.instantiate() as Player
	add_child(player)
	player.global_position = Vector2(400, 400)
	var visuals := player.get_node("SlipstreamVisuals") as Node2D
	var sprite := player.get_node("AnimatedSprite2D") as AnimatedSprite2D
	var ok := visuals != null
	await _frames(3)
	ok = ok and not visuals.visible and sprite.visible
	player.call("_begin_slip", true)
	await _frames(20)
	ok = ok and player.is_ball and visuals.visible and sprite.self_modulate.a == 0.0
	player.call("_begin_slip", false)
	await _frames(30)
	ok = ok and not player.is_ball and sprite.visible and sprite.self_modulate == Color.WHITE
	player.queue_free()
	await _frames(2)
	if not ok:
		push_error("FAIL: slipstream visuals did not follow the Ball form")
	print("slipstream: %s" % ("PASS" if ok else "FAIL"))
	await TestShutdown.finish(get_tree(), 0 if ok else 1)


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame
