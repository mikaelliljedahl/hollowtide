extends "res://scripts/pickups/pickup.gd"


func _ready() -> void:
	if instance_id.is_empty():
		instance_id = "prototype.weapon.beam"
	if kind == &"":
		kind = &"beam"
	pickup_sound = &"weapon_pickup"
	super._ready()
