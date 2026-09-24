extends "res://scripts/pickups/pickup.gd"


func _ready() -> void:
	if instance_id.is_empty():
		instance_id = "prototype.orb.slip"
	if kind == &"":
		kind = &"slipstream"
	pickup_sound = &"orb_pickup"
	super._ready()
