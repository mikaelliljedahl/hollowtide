extends Marker2D

## Lava basin surface. Reuses the dev hazard fixture (art, loop audio, contact damage) with the
## campaign's own placement. Lava sits in a one-tile basin whose floor is rock.

const HAZARD_SCRIPT = preload("res://scripts/dev/dev_hazard.gd")
const LAVA_DAMAGE := 18

@export var hazard_size := Vector2(256, 64)
@export var profile: StringName = &"lava_surface"


func _ready() -> void:
	var hazard := HAZARD_SCRIPT.new() as Area2D
	if hazard == null:
		return
	hazard.call("configure_profile", profile, hazard_size, LAVA_DAMAGE, true, true, &"")
	add_child(hazard)
