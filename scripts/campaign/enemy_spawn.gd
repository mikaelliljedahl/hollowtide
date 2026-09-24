extends Marker2D

## Spawns one common enemy when the room loads. Enemies return on every room revisit.

const CRAWLER_SPEED := 110.0

@export var enemy_id: StringName = &"hopper"
## Local-pixel rectangle the enemy is confined to; it only engages while the player is inside.
@export var bounds := Rect2()
@export var travel_direction := 1

var enemy: Node2D


func _ready() -> void:
	call_deferred("_spawn")


func _spawn() -> void:
	enemy = EnemyFactory.create(enemy_id)
	if enemy == null:
		push_warning("Campaign: could not create enemy %s" % enemy_id)
		return
	var room := get_parent().get_parent() as Node2D
	enemy.position = position
	if enemy_id == &"crawler":
		enemy.set("travel_direction", travel_direction)
		enemy.set("move_speed", CRAWLER_SPEED)
	get_parent().add_child(enemy)
	if enemy.has_method("configure_arena") and bounds.size != Vector2.ZERO:
		var origin := room.global_position if room != null else Vector2.ZERO
		enemy.call("configure_arena", Rect2(origin + bounds.position, bounds.size))
	enemy.add_to_group(&"campaign_enemy")
