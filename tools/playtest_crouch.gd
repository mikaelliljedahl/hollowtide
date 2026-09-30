extends RefCounted
## Crouched low fire for the playtest agent (docs/features/playtest-agent.md, "Candidates"): a
## grounded crouch fires level from far lower than a standing shot (docs/game-feel.md, "Crouch"),
## which is the intended answer to a target too low for a standing shot. The vaults_01 probe
## (armored guard held 256 to 560 px ahead on the pit floor) hit it with 0 of 3 standing Harpoons;
## the heuristic arena run fired 10 standing Harpoons over it and never killed it.

const Programs = preload("res://tools/playtest_programs.gd")
## Heights of the level shot's line above the feet, standing and crouched (negative is up).
const STANDING_LINE := PlayerConfig.STANDING_HORIZONTAL_MUZZLE_OFFSET.y
const CROUCH_LINE := PlayerConfig.CROUCH_HORIZONTAL_MUZZLE_OFFSET.y
## Half the height of a shot's body: the Harpoon is 14 px tall, the bolt a 7 px circle.
const SHOT_HALF := 7.0
## Frames held down before the shot: the crouch starts on the first grounded frame, and the
## crouched muzzle is used once the form has changed.
const CROUCH_FRAMES := 3
const SHOT_RANGE := 1100.0
## Bolt kinds that damage; the Snare (ice) only freezes an ordinary enemy.
const DAMAGING_BOLTS := ["beam", "wave"]


## [top, bottom] of what a player's shot hits on `enemy`, in px relative to the feet (y down): its
## projectile hurtbox (the art's silhouette), else its body shape; [] when it has neither.
static func span(enemy: Node2D, feet: Vector2) -> Array:
	var shapes: Array[Node] = []
	var hurtbox := enemy.find_child("ProjectileHurtbox", true, false)
	if hurtbox != null:
		shapes = hurtbox.get_children()
	var body := enemy.get_node_or_null("CollisionShape2D")
	if shapes.is_empty() and body != null:
		shapes = [body]
	var top := INF
	var bottom := -INF
	for node in shapes:
		var points := PackedVector2Array()
		if node is CollisionPolygon2D:
			points = (node as CollisionPolygon2D).polygon
		elif node is CollisionShape2D and (node as CollisionShape2D).shape != null:
			var rect := (node as CollisionShape2D).shape.get_rect()
			points = [rect.position, rect.end]
		for point in points:
			var y := ((node as Node2D).global_transform * point).y - feet.y
			top = minf(top, y)
			bottom = maxf(bottom, y)
	if top == INF:
		return []
	return [roundi(top), roundi(bottom)]


## True when a level shot from her standing crossbow passes over `span` and a crouched one hits it.
static func is_low(span_rel: Array) -> bool:
	if span_rel.size() != 2:
		return false
	var top := float(span_rel[0])
	var bottom := float(span_rel[1])
	return (
		top - SHOT_HALF > STANDING_LINE
		and top - SHOT_HALF <= CROUCH_LINE
		and bottom + SHOT_HALF >= CROUCH_LINE
	)


## `crouch_shot:<id>:<weapon>` at a visible, low, non-boss `target` while she stands on the
## ground: the equipped bolt when it damages the target, else a Harpoon when that hurts it, else
## the Snare when that freezes it; {} otherwise.
static func candidate(state: Dictionary, target: Dictionary) -> Dictionary:
	var me: Dictionary = state["player"]
	if not bool(me["grounded"]) or me["form"] == "ball" or bool(target["is_boss"]):
		return {}
	if not bool(target["visible"]) or not bool(target.get("low", false)):
		return {}
	var rel := Vector2(float(target["rel"][0]), float(target["rel"][1]))
	if rel.length() > SHOT_RANGE:
		return {}
	var kinds: Array = target["hurt_by"]
	var weapon := ""
	if kinds.any(func(kind: String) -> bool: return kind in DAMAGING_BOLTS):
		weapon = "bolt"
	elif kinds.has("missile"):
		weapon = "harpoon"
	elif kinds.has("ice"):
		weapon = "bolt"
	if weapon.is_empty():
		return {}
	var fire := &"fire_beam" if weapon == "bolt" else &"fire_missile"
	var direction := -1 if rel.x < 0.0 else 1
	return {
		"key": "crouch_shot:%s:%s" % [target["id"], weapon],
		"kind": "crouch_shot",
		"label":
		"crouch and fire a %s level at %s, too low for a standing shot" % [weapon, target["type"]],
		"program": program(direction, fire, int(me["facing"])),
	}


## Face `direction`, hold down to crouch, tap `fire` level while crouched, stay down three frames.
static func program(direction: int, fire: StringName, facing: int) -> Array:
	var frames: Array = []
	if direction != facing:
		frames.append_array(Programs.hold([Programs.move_action(direction)], 2))
	frames.append_array(Programs.hold([&"move_down"], CROUCH_FRAMES))
	frames.append_array(Programs.hold([&"move_down", fire], 3))
	frames.append_array(Programs.hold([&"move_down"], 3))
	return frames
