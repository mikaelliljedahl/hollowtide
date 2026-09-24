extends RefCounted
## Playtest agent state exporter (docs/features/playtest-agent.md): turns the live campaign into
## one compact, JSON-safe Dictionary per decision. Positions of other things are relative to the
## player's feet in pixels (x right, y down); the player's own position is room-local.
## Read-only: it never changes game state.

const Rooms = preload("res://scripts/campaign/campaign_rooms.gd")
const Catalog = preload("res://scripts/progression/content_catalog.gd")
const TILE := 64.0
const MAX_ENEMIES := 6
const MAX_PROJECTILES := 8
const MAX_PICKUPS := 4
const MAX_HAZARDS := 4
const PROJECTILE_RADIUS := 900.0
const HAZARD_RADIUS := 1200.0
const HAZARD_GROUPS: Array[StringName] = [
	&"worldfx_crusher",
	&"worldfx_stalactite",
	&"worldfx_rising_shaft",
	&"worldfx_crumble",
	&"campaign_heat",
]
## Crossbow height above the feet, used for line-of-sight checks.
const EYE := Vector2(0, -100)
const ARENA_STATES := ["armed", "sealing", "fighting", "cleared", "intermission"]

var _ids: Dictionary = {}
var _next_id := 1


## Stable per-run label for a node ("e1", "e2", ...); the same enemy keeps its label all run.
func label_for(node: Node) -> String:
	var key := node.get_instance_id()
	if not _ids.has(key):
		_ids[key] = "e%d" % _next_id
		_next_id += 1
	return _ids[key]


func snapshot(root: Node, player: Player, tick: int, seconds: float) -> Dictionary:
	var room := root.get("current_room") as Node2D
	var room_id := String(root.get("current_room_id"))
	if room == null or player == null or not room.has_method(&"size_px"):
		return {"tick": tick, "t": snappedf(seconds, 0.01), "room": null}
	var feet := player.global_position
	var tree := player.get_tree()
	return {
		"tick": tick,
		"t": snappedf(seconds, 0.01),
		"room": _room(room, room_id),
		"player": _player(player, room),
		"kit": kit(),
		"enemies": enemies(tree, feet),
		"projectiles": _projectiles(tree, feet),
		"ambush": ambush(tree, feet),
		"exits": exits(room, room_id, feet),
		"pickups": pickups(room, feet),
		"hazards": _hazards(tree, feet),
	}


static func kit() -> Dictionary:
	var owned: Array[String] = []
	for id in Catalog.ABILITY_IDS:
		if GameState.has_ability(id):
			owned.append(String(id))
	return {
		"abilities": owned,
		"beam": String(GameState.active_beam),
		"missiles": GameState.missile_count,
		"max_missiles": GameState.max_missiles,
	}


static func rel(from: Vector2, to: Vector2) -> Array:
	return [roundi(to.x - from.x), roundi(to.y - from.y)]


static func _room(room: Node2D, room_id: String) -> Dictionary:
	var size: Vector2 = room.call("size_px")
	return {
		"id": room_id,
		"area": String(room.get("area_id")),
		"size": [roundi(size.x), roundi(size.y)],
	}


static func _player(player: Player, room: Node2D) -> Dictionary:
	var local := player.global_position - room.global_position
	var form := "standing"
	if player.is_ball:
		form = "ball"
	elif player.is_crouching:
		form = "crouching"
	return {
		"pos": [roundi(local.x), roundi(local.y)],
		"cell": [floori(local.x / TILE), floori((local.y - 1.0) / TILE)],
		"vel": [roundi(player.velocity.x), roundi(player.velocity.y)],
		"health": GameState.health,
		"max_health": GameState.max_health,
		"grounded": player.is_on_floor(),
		"on_wall": player.is_on_wall() and not player.is_on_floor(),
		"facing": player.facing,
		"form": form,
		"dash_ready": player.can_dash(),
	}


## Living enemies nearest first, including bosses.
func enemies(tree: SceneTree, feet: Vector2) -> Array:
	var found: Array = []
	for node in tree.get_nodes_in_group(&"enemies"):
		var enemy := node as Node2D
		if enemy == null or enemy.is_queued_for_deletion() or int(enemy.get("health")) <= 0:
			continue
		found.append(enemy)
	found.sort_custom(
		func(a: Node2D, b: Node2D) -> bool:
			return (
				feet.distance_squared_to(a.global_position)
				< feet.distance_squared_to(b.global_position)
			)
	)
	var result: Array = []
	for enemy in found.slice(0, MAX_ENEMIES):
		result.append(_enemy(enemy, feet))
	return result


func _enemy(enemy: Node2D, feet: Vector2) -> Dictionary:
	var is_boss := enemy.is_in_group(&"bosses")
	var entry := {
		"id": label_for(enemy),
		"type": String(enemy.get("enemy_id")),
		"rel": rel(feet, enemy.global_position),
		"dist": roundi(feet.distance_to(enemy.global_position)),
		"health": int(enemy.get("health")),
		"max_health": int(enemy.get("max_health")),
		"is_boss": is_boss,
		"telegraph": false,
		"ambush": enemy.is_in_group(&"worldfx_ambush_enemy"),
		"hurt_by": hurt_by(enemy),
		"visible": clear_line(enemy, feet + EYE, enemy.global_position),
	}
	if enemy.has_method(&"presentation_state"):
		var shown := StringName(enemy.call(&"presentation_state"))
		entry["telegraph"] = shown in [&"attack_telegraph", &"attack"]
	if is_boss:
		entry["stage"] = int(enemy.get("stage"))
		entry["attack"] = String(enemy.get("_attack_id"))
		entry["attack_state"] = String(enemy.get("_attack_state"))
		entry["engaged"] = enemy.get("_player_engaged") == true
	return entry


## True when no world tile lies between `from` and `to`.
static func clear_line(node: Node2D, from: Vector2, to: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(from, to, 1)
	return node.get_world_2d().direct_space_state.intersect_ray(query).is_empty()


## Damage kinds the player owns that hurt `enemy` right now (active beam kind, missile, dash).
static func hurt_by(enemy: Node) -> Array:
	var kinds: Array = []
	if not enemy.has_method(&"is_vulnerable_to"):
		return kinds
	if GameState.has_beam:
		var beam := beam_kind()
		if enemy.call(&"is_vulnerable_to", beam):
			kinds.append(String(beam))
	if GameState.has_missiles and enemy.call(&"is_vulnerable_to", &"missile"):
		kinds.append("missile")
	if GameState.has_ability(&"undertow_dash") and enemy.call(&"is_vulnerable_to", &"undertow"):
		kinds.append("undertow")
	return kinds


## Damage kind of the equipped beam, as enemies test it.
static func beam_kind() -> StringName:
	match GameState.active_beam:
		&"ice":
			return &"ice"
		&"wave":
			return &"wave"
	return &"beam"


static func _projectiles(tree: SceneTree, feet: Vector2) -> Array:
	var found: Array = []
	for node in tree.get_nodes_in_group(&"enemy_shot"):
		var shot := node as EnemyProjectile
		if shot == null or shot.is_queued_for_deletion():
			continue
		var distance := feet.distance_to(shot.global_position)
		if distance <= PROJECTILE_RADIUS:
			found.append([distance, shot])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var result: Array = []
	for pair in found.slice(0, MAX_PROJECTILES):
		var shot := pair[1] as EnemyProjectile
		var velocity := shot.direction * shot.speed
		(
			result
			. append(
				{
					"rel": rel(feet, shot.global_position),
					"vel": [roundi(velocity.x), roundi(velocity.y)],
					"style": String(shot.style),
				}
			)
		)
	return result


## The ambush arena of the current room, or null.
static func ambush(tree: SceneTree, feet: Vector2) -> Variant:
	for node in tree.get_nodes_in_group(&"worldfx_ambush"):
		var arena := node as AmbushArena
		if arena == null or arena.is_queued_for_deletion():
			continue
		return {
			"id": arena.flag(),
			"state": ARENA_STATES[arena.state],
			"wave": arena.wave_index + 1,
			"waves": arena.all_waves().size(),
			"alive": arena.alive_count(),
			"trigger_rel": rel(feet, trigger_center(arena)),
			"inside": arena.arena_rect_global().has_point(feet + Vector2(0, -60)),
		}
	return null


## Global point that commits the player to `arena` (centre of its trigger zone).
static func trigger_center(arena: AmbushArena) -> Vector2:
	if arena.trigger_rect.size == Vector2.ZERO:
		return arena.global_position
	return arena.global_position + arena.trigger_rect.get_center()


## Door openings from the generated room index (none for rooms outside it, such as test rooms);
## gated while the gate flag is unset.
static func exits(room: Node2D, room_id: String, feet: Vector2) -> Array:
	var result: Array = []
	if not Rooms.ROOMS.has(room_id):
		return result
	for door in Rooms.ROOMS[room_id]["doors"]:
		var from: Vector2i = door["from"]
		var to: Vector2i = door["to"]
		var center := (Vector2(from + to) * 0.5 + Vector2(0.5, 1.0)) * TILE
		var gate := String(door["gate"])
		(
			result
			. append(
				{
					"id": "%s:%s" % [door["edge"], door["target"]],
					"rel": rel(feet, room.global_position + center),
					"gated":
					not gate.is_empty() and not GameState.has_world_flag(door["gate_flag"]),
					"gate": gate,
				}
			)
		)
	return result


static func pickups(room: Node2D, feet: Vector2) -> Array:
	var found: Array = []
	var entities := room.get_node_or_null("Entities")
	if entities == null:
		return found
	for child in entities.get_children():
		var pickup := child as ProgressionPickup
		if pickup == null or GameState.collected_pickup_ids.has(pickup.instance_id):
			continue
		(
			found
			. append(
				{
					"id": pickup.instance_id,
					"kind": String(pickup.kind),
					"rel": rel(feet, pickup.global_position),
				}
			)
		)
	found.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return (
				Vector2(a["rel"][0], a["rel"][1]).length()
				< Vector2(b["rel"][0], b["rel"][1]).length()
			)
	)
	return found.slice(0, MAX_PICKUPS)


static func _hazards(tree: SceneTree, feet: Vector2) -> Array:
	var found: Array = []
	for group in HAZARD_GROUPS:
		for node in tree.get_nodes_in_group(group):
			var hazard := node as Node2D
			if hazard == null or feet.distance_to(hazard.global_position) > HAZARD_RADIUS:
				continue
			found.append(
				{
					"kind": String(group).trim_prefix("worldfx_"),
					"rel": rel(feet, hazard.global_position)
				}
			)
	return found.slice(0, MAX_HAZARDS)
