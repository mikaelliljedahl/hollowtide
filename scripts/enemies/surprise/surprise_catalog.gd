class_name SurpriseCatalog
extends RefCounted
## D20 surprise enemies: additive runtime ids next to the thirteen ordinary enemies in
## ContentCatalog.ENEMY_IDS (which stays at thirteen). EnemyFactory, the dev panel and the
## campaign `enemy <id>` legend all resolve these ids through this file.

const ART_DIR := "res://assets/sprites/enemies_new/"

## Selectable/placeable ids, in dev-panel order. `bat` is internal (spawned by bat_swarm).
const IDS: Array[StringName] = [
	&"bat_swarm",
	&"mimic",
	&"mimic_lure",
	&"drop_spider",
	&"surface_eel",
	&"stalker",
	&"chasm_sniper",
]
const INTERNAL_IDS: Array[StringName] = [&"bat"]

const LABELS := {
	&"bat_swarm": "Bat Swarm",
	&"bat": "Bat",
	&"mimic": "Mimic (rock)",
	&"mimic_lure": "Mimic (lure)",
	&"drop_spider": "Drop Spider",
	&"surface_eel": "Surface Eel",
	&"stalker": "Stalker",
	&"chasm_sniper": "Chasm Sniper",
}

## body = movement collision size, contact = player-damage detector size (px).
const DATA := {
	&"bat":
	{
		"max_health": 6,
		"contact_damage": 6,
		"freeze_capable": true,
		"body": Vector2(30, 22),
		"contact": Vector2(40, 30),
	},
	&"mimic":
	{
		"max_health": 40,
		"contact_damage": 16,
		"freeze_capable": true,
		"body": Vector2(110, 70),
		"contact": Vector2(124, 84),
	},
	&"mimic_lure":
	{
		"max_health": 40,
		"contact_damage": 16,
		"freeze_capable": true,
		"body": Vector2(96, 70),
		"contact": Vector2(110, 84),
	},
	&"drop_spider":
	{
		"max_health": 30,
		"contact_damage": 14,
		"freeze_capable": true,
		"body": Vector2(56, 56),
		"contact": Vector2(72, 72),
	},
	&"surface_eel":
	{
		"max_health": 36,
		"contact_damage": 16,
		"freeze_capable": true,
		"body": Vector2(60, 60),
		"contact": Vector2(76, 76),
	},
	&"stalker":
	{
		"max_health": 90,
		"contact_damage": 18,
		"freeze_capable": true,
		"body": Vector2(150, 64),
		"contact": Vector2(176, 80),
	},
	&"chasm_sniper":
	{
		"max_health": 30,
		"contact_damage": 12,
		"projectile_damage": 14,
		"freeze_capable": true,
		"body": Vector2(80, 60),
		"contact": Vector2(96, 72),
	},
}

const SCRIPTS := {
	&"bat": "res://scripts/enemies/surprise/bat.gd",
	&"mimic": "res://scripts/enemies/surprise/mimic.gd",
	&"mimic_lure": "res://scripts/enemies/surprise/mimic.gd",
	&"drop_spider": "res://scripts/enemies/surprise/drop_spider.gd",
	&"surface_eel": "res://scripts/enemies/surprise/surface_eel.gd",
	&"stalker": "res://scripts/enemies/surprise/stalker.gd",
	&"chasm_sniper": "res://scripts/enemies/surprise/chasm_sniper.gd",
}
const ROOST_SCRIPT := "res://scripts/enemies/surprise/bat_roost.gd"


static func has(runtime_id: StringName) -> bool:
	return IDS.has(runtime_id) or INTERNAL_IDS.has(runtime_id)


static func data(runtime_id: StringName) -> Dictionary:
	return DATA.get(runtime_id, DATA[&"bat"])


static func label(runtime_id: StringName) -> String:
	return LABELS.get(runtime_id, String(runtime_id))


static func art_path(file_name: String) -> String:
	return ART_DIR + file_name + ".png"


static func create(runtime_id: StringName) -> Node2D:
	if runtime_id == &"bat_swarm":
		var roost := Node2D.new()
		roost.set_script(load(ROOST_SCRIPT))
		roost.name = "BatSwarm"
		return roost
	if not SCRIPTS.has(runtime_id):
		return null
	var info := data(runtime_id)
	var body := CharacterBody2D.new()
	body.name = String(runtime_id).to_pascal_case()
	body.collision_layer = 8
	body.collision_mask = 3
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.visible = false
	body.add_child(sprite)
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var rect := RectangleShape2D.new()
	rect.size = info["body"]
	shape.shape = rect
	body.add_child(shape)
	var detector := Area2D.new()
	detector.name = "PlayerDetector"
	detector.collision_layer = 0
	detector.collision_mask = 2
	detector.monitorable = false
	var detector_shape := CollisionShape2D.new()
	detector_shape.name = "CollisionShape2D"
	var contact := RectangleShape2D.new()
	contact.size = info["contact"]
	detector_shape.shape = contact
	detector.add_child(detector_shape)
	body.add_child(detector)
	# Script last: CombatEnemy._ready expects the child nodes above.
	body.set_script(load(SCRIPTS[runtime_id]))
	body.set(&"runtime_id", runtime_id)
	return body


## Dev-panel spawn point near `floor_point` (a point on the station floor): hanging types go
## under the lowest nearby ceiling, the eel sits on the floor line, walkers just above it.
static func dev_spawn_point(
	id: StringName, space: PhysicsDirectSpaceState2D, floor_point: Vector2
) -> Vector2:
	match id:
		&"bat_swarm", &"drop_spider":
			var best := floor_point + Vector2(0, -520)
			var best_gap := INF
			for step in range(-9, 10):
				var from := floor_point + Vector2(step * 64.0, -60.0)
				var hit := space.intersect_ray(
					PhysicsRayQueryParameters2D.create(from, from + Vector2(0, -700), 1)
				)
				if hit.is_empty():
					continue
				var gap: float = from.y - Vector2(hit["position"]).y
				if gap > 260.0 and gap < best_gap:
					best_gap = gap
					best = Vector2(hit["position"]) + Vector2(0, 40)
			return best
		&"surface_eel":
			return floor_point + Vector2(0, 132)
	return floor_point + Vector2(0, 40)
