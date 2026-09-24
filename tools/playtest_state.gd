extends RefCounted
## Playtest agent state exporter (docs/features/playtest-agent.md): turns the live campaign into
## one compact, JSON-safe Dictionary per decision. Positions of other things are relative to the
## player's feet in pixels (x right, y down); the player's own position is room-local.
## Read-only: it never changes game state.

const Rooms = preload("res://scripts/campaign/campaign_rooms.gd")
const Catalog = preload("res://scripts/progression/content_catalog.gd")
const Hazards = preload("res://tools/playtest_hazards.gd")
const Boss = preload("res://tools/playtest_boss.gd")
const TILE := 64.0
const MAX_ENEMIES := 6
const MAX_PROJECTILES := 8
const MAX_PICKUPS := 4
const MAX_HAZARDS := 4
const MAX_REFILLS := 3
const PROJECTILE_RADIUS := 900.0
const HAZARD_RADIUS := 1200.0
## What each shrine kind (scripts/campaign/station.gd) and combat drop restores.
const RESTORES := {
	&"save": ["health", "harpoons"],
	&"refill": ["health", "harpoons"],
	&"missilerefill": ["harpoons"],
	&"energy_refill": ["health"],
	&"missile_refill": ["harpoons"],
}
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
		"hazards": hazards(player),
		"refills": refills(room, tree, feet),
	}


static func kit() -> Dictionary:
	var owned: Array[String] = []
	for id in Catalog.ABILITY_IDS:
		if GameState.has_ability(id):
			owned.append(String(id))
	return {
		"abilities": owned,
		"beam": String(GameState.active_beam),
		"beams": Boss.owned_beams(),
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
		"switch_to": switch_to(enemy),
		"visible": clear_line(enemy, feet + EYE, enemy.global_position),
	}
	if enemy.has_method(&"presentation_state"):
		var shown := StringName(enemy.call(&"presentation_state"))
		# Surprise enemies name their own states (a spider's twitch); their wind-up glow counts too.
		var wind_up = enemy.get("_telegraph_remaining")
		entry["telegraph"] = (
			shown in [&"attack_telegraph", &"attack"] or (wind_up is float and wind_up > 0.0)
		)
	if is_boss:
		entry["stage"] = int(enemy.get("stage"))
		entry["attack"] = String(enemy.get("_attack_id"))
		entry["attack_state"] = String(enemy.get("_attack_state"))
		entry["engaged"] = enemy.get("_player_engaged") == true
		entry.merge(Boss.facts(enemy, feet))
	return entry


## True when no world tile lies between `from` and `to`.
static func clear_line(node: Node2D, from: Vector2, to: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(from, to, 1)
	return node.get_world_2d().direct_space_state.intersect_ray(query).is_empty()


## Damage kinds the player can use on `enemy` right now: the equipped beam kind, the Harpoon while
## a shot's worth of bolts is left, the Resonance Pulse, the dash.
static func hurt_by(enemy: Node) -> Array:
	var kinds: Array = []
	if not enemy.has_method(&"is_vulnerable_to"):
		return kinds
	if GameState.has_beam:
		var beam := beam_kind()
		if enemy.call(&"is_vulnerable_to", beam):
			kinds.append(String(beam))
	if harpoons_ready() and enemy.call(&"is_vulnerable_to", &"missile"):
		kinds.append("missile")
	if GameState.has_ability(&"bombs") and enemy.call(&"is_vulnerable_to", &"bomb"):
		kinds.append("bomb")
	if GameState.has_ability(&"undertow_dash") and enemy.call(&"is_vulnerable_to", &"undertow"):
		kinds.append("undertow")
	return kinds


## True while one Harpoon shot's bolts are left (a Tide Glyph can make a shot cost more).
static func harpoons_ready() -> bool:
	var cost := 1 + GameState.tide.add(&"harpoon_bolt_add")
	return GameState.has_missiles and GameState.missile_count >= cost


## An owned, unequipped beam (GameState id) that hurts `enemy` now when the equipped one does not;
## "" otherwise.
static func switch_to(enemy: Node) -> String:
	if not enemy.has_method(&"is_vulnerable_to") or enemy.call(&"is_vulnerable_to", beam_kind()):
		return ""
	for beam in Boss.owned_beams():
		if beam != String(GameState.active_beam) and enemy.call(&"is_vulnerable_to", _kind(beam)):
			return beam
	return ""


## Damage kind of the equipped beam, as enemies test it.
static func beam_kind() -> StringName:
	return _kind(String(GameState.active_beam))


static func _kind(beam: String) -> StringName:
	match beam:
		"ice":
			return &"ice"
		"wave":
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


## Hazards within HAZARD_RADIUS of the player's hitbox, nearest first: `kind`, `rel` (the nearest
## point of the hazard's body), `size`, `gap` (px from her hitbox, 0 when touching) and `state`
## (a stalactite's, flood's or crusher's phase, else "").
static func hazards(player: Player) -> Array:
	var feet := player.global_position
	var body := Hazards.body_rect(player)
	var result: Array = []
	for hazard in Hazards.near(player.get_tree(), body, HAZARD_RADIUS, false).slice(0, MAX_HAZARDS):
		var rect: Rect2 = hazard["rect"]
		(
			result
			. append(
				{
					"kind": hazard["kind"],
					"rel": rel(feet, Hazards.nearest_point(rect, body.get_center())),
					"size": [roundi(rect.size.x), roundi(rect.size.y)],
					"gap": roundi(hazard["gap"]),
					"state": hazard["state"],
				}
			)
		)
	return result


## Shrines in the current room and dropped refills, nearest first: `kind`, `restores` ("health",
## "harpoons") and `rel`.
static func refills(room: Node2D, tree: SceneTree, feet: Vector2) -> Array:
	var found: Array = []
	for node in tree.get_nodes_in_group(&"campaign_station"):
		var station := node as Node2D
		if station != null and room.is_ancestor_of(station):
			found.append([StringName(station.get("station_kind")), station.global_position])
	for node in tree.get_nodes_in_group(&"transient"):
		var loot := node as CombatLoot
		if loot != null and not loot.is_queued_for_deletion():
			found.append([loot.kind, loot.global_position])
	var result: Array = []
	for pair in found:
		if RESTORES.has(pair[0]):
			(
				result
				. append(
					{
						"kind": String(pair[0]),
						"restores": RESTORES[pair[0]],
						"rel": rel(feet, pair[1]),
					}
				)
			)
	result.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return (
				Vector2(a["rel"][0], a["rel"][1]).length()
				< Vector2(b["rel"][0], b["rel"][1]).length()
			)
	)
	return result.slice(0, MAX_REFILLS)
