extends RefCounted
## Playtest agent telemetry (docs/features/playtest-agent.md, "Telemetry"). Listens to game
## signals and samples the player once per physics frame; `to_dict()` is the run's JSON record.
## Damage sources are attributed by proximity at the moment health drops (the game does not
## report who hit the player), so "unknown" can appear.

const TILE := 64.0
const SAMPLE_SECONDS := 0.5
const STUCK_WINDOW := 3.0
const STUCK_SPREAD := 48.0
const SHOT_RADIUS := 170.0
const CONTACT_RADIUS := 280.0
const HAZARD_RADIUS := 320.0
const BOSS_ATTACK_MEMORY := 3.0
const KILLER_MEMORY := 1.5
const BREAK_RADIUS := 1.5
const BREAK_KINDS := ["jump", "jump_over", "wall_jump", "dash_through"]
const HAZARD_GROUPS := [
	&"worldfx_crusher", &"worldfx_stalactite", &"worldfx_rising_shaft", &"campaign_heat"
]

var now := 0.0
var room := ""
var deaths: Array = []
## Enemy type -> enemies that died while the agent played (freed or at zero health).
var kills: Dictionary = {}
var damage: Dictionary = {}
var hits: Array = []
var room_seconds: Dictionary = {}
var stuck_episodes: Array = []
var ambushes: Array = []
var bosses: Array = []
var deflect := {"attempts": 0, "successes": 0}
var pickups: Array = []
var breaks: Dictionary = {}
## Boss id -> damage it took while the player was outside its arena (it does not fight back then).
var disengaged_damage: Dictionary = {}
var decisions: Dictionary = {}
var actions: Dictionary = {}
var _player: Player
var _root: Node
var _health := -1
var _last_hit := {}
var _samples: Array = []
var _stuck: Dictionary = {}
var _ambush: Dictionary = {}
var _boss: Dictionary = {}
var _boss_attacks: Dictionary = {}
var _boss_health: Dictionary = {}
var _alive: Dictionary = {}
var _known_pickups := 0
var _reflected := 0
var _break_specs: Array = []
var _break_seen: Dictionary = {}


## `break_specs`: [{id, room, cell: Vector2i}] feet cells where intended sequence breaks start.
func attach(root: Node, player: Player, break_specs: Array) -> void:
	_root = root
	_player = player
	_break_specs = break_specs
	_health = GameState.health
	_known_pickups = GameState.collected_pickup_ids.size()
	_reflected = _reflected_count()
	GameState.health_changed.connect(_on_health_changed)
	GameState.player_died.connect(_on_player_died)
	if root.has_signal(&"room_changed"):
		root.connect(&"room_changed", _on_room_changed)
	_on_room_changed(String(root.get("current_room_id")))


func detach() -> void:
	_finish_ambush("unfinished")
	_finish_boss("unfinished")
	_finish_stuck()
	if GameState.health_changed.is_connected(_on_health_changed):
		GameState.health_changed.disconnect(_on_health_changed)
	if GameState.player_died.is_connected(_on_player_died):
		GameState.player_died.disconnect(_on_player_died)


## Called once per unpaused physics frame. `moving` is true while the current action wants to
## travel; `kind` is the current action kind.
func tick(delta: float, moving: bool, kind: String) -> void:
	now += delta
	if room.is_empty() or _player == null:
		return
	room_seconds[room] = float(room_seconds.get(room, 0.0)) + delta
	var alive := GameState.health > 0
	_track_stuck(moving and alive)
	_track_pickups()
	_track_boss()
	_track_kills()
	_track_ambush_wave()
	var reflected := _reflected_count()
	if reflected > _reflected:
		deflect["successes"] += reflected - _reflected
	_reflected = reflected
	if alive and kind in BREAK_KINDS:
		_track_breaks()


func record_decision(policy: String, latency_usec: int, fallback: String, kind: String) -> void:
	var entry: Dictionary = decisions.get(
		policy, {"count": 0, "latency_ms_total": 0.0, "latency_ms_max": 0.0, "fallbacks": {}}
	)
	var latency := latency_usec / 1000.0
	entry["count"] += 1
	entry["latency_ms_total"] += latency
	entry["latency_ms_max"] = maxf(entry["latency_ms_max"], latency)
	if not fallback.is_empty():
		entry["fallbacks"][fallback] = int(entry["fallbacks"].get(fallback, 0)) + 1
	decisions[policy] = entry
	actions[kind] = int(actions.get(kind, 0)) + 1
	if kind == "dash_through":
		deflect["attempts"] += 1


func is_stuck() -> bool:
	return not _stuck.is_empty()


func current_cell() -> Vector2i:
	var room_node := _root.get("current_room") as Node2D
	if room_node == null:
		return Vector2i.ZERO
	var local := _player.global_position - room_node.global_position
	return Vector2i(floori(local.x / TILE), floori((local.y - 1.0) / TILE))


func to_dict() -> Dictionary:
	var decision_out := {}
	for policy in decisions:
		var entry: Dictionary = decisions[policy]
		decision_out[policy] = {
			"count": entry["count"],
			"latency_ms_mean": snappedf(entry["latency_ms_total"] / maxf(entry["count"], 1), 0.01),
			"latency_ms_max": snappedf(entry["latency_ms_max"], 0.01),
			"fallbacks": entry["fallbacks"],
		}
	var rooms := {}
	for id in room_seconds:
		rooms[id] = snappedf(room_seconds[id], 0.1)
	return {
		"seconds": snappedf(now, 0.1),
		"deaths": deaths,
		"kills": kills,
		"damage_by_source": damage,
		"hits": hits,
		"room_seconds": rooms,
		"stuck": stuck_episodes,
		"ambushes": ambushes,
		"bosses": bosses,
		"boss_damage_while_disengaged": disengaged_damage,
		"deflect": deflect,
		"pickups": pickups,
		"sequence_break_attempts": breaks,
		"decisions": decision_out,
		"actions": actions,
	}


# --- signals ----------------------------------------------------------------------------------


func _on_room_changed(room_id: String) -> void:
	_finish_ambush("left_room")
	_finish_boss("left_room")
	_finish_stuck()
	_samples.clear()
	_alive.clear()
	room = room_id
	var tree := _player.get_tree()
	for node in tree.get_nodes_in_group(&"worldfx_ambush"):
		var arena := node as AmbushArena
		if arena == null or arena.is_queued_for_deletion():
			continue
		arena.sealed.connect(_on_ambush_sealed.bind(arena))
		arena.cleared.connect(_finish_ambush.bind("cleared"))
		arena.aborted.connect(_on_ambush_aborted)
	for node in tree.get_nodes_in_group(&"bosses"):
		var boss := node as CombatBoss
		if boss == null or boss.is_queued_for_deletion() or boss.health <= 0:
			continue
		boss.attack_released.connect(_on_boss_attack.bind(boss))
		boss.stage_changed.connect(_on_boss_stage.bind(boss))
		boss.defeated.connect(func(_id: StringName) -> void: _finish_boss("defeated"))


func _on_health_changed(current: int, _maximum: int) -> void:
	var lost := _health - current
	_health = current
	if lost <= 0 or _player == null:
		return
	var source := _source()
	damage[source] = int(damage.get(source, 0)) + lost
	var cell := current_cell()
	hits.append(
		{
			"t": snappedf(now, 0.01),
			"room": room,
			"cell": [cell.x, cell.y],
			"source": source,
			"amount": lost
		}
	)
	_last_hit = {"t": now, "source": source}
	if not _ambush.is_empty():
		_ambush["damage_taken"] += lost
	if not _boss.is_empty():
		var by_attack: Dictionary = _boss["damage_by_source"]
		by_attack[source] = int(by_attack.get(source, 0)) + lost


func _on_player_died() -> void:
	var cell := current_cell()
	var killer := "unknown"
	if not _last_hit.is_empty() and now - float(_last_hit["t"]) <= KILLER_MEMORY:
		killer = _last_hit["source"]
	var death := {
		"t": snappedf(now, 0.01), "room": room, "cell": [cell.x, cell.y], "killer": killer
	}
	if not _boss.is_empty():
		death["boss"] = _boss["id"]
		death["boss_stage"] = _boss["stage"]
		_finish_boss("died")
	if not _ambush.is_empty():
		_finish_ambush("died")
	var fight: Dictionary = ambushes[-1] if not ambushes.is_empty() else {}
	if fight.get("outcome") == "died" and not fight.has("death_noted"):
		fight["death_noted"] = true
		death["ambush"] = fight["id"]
		death["ambush_wave"] = fight["wave_reached"]
	deaths.append(death)


func _on_ambush_sealed(arena: AmbushArena) -> void:
	_finish_ambush("unfinished")
	_ambush = {
		"id": arena.flag(),
		"room": room,
		"arena": arena,
		"start": now,
		"wave": 1,
		"waves": arena.plan_waves().size(),
		"damage_taken": 0,
	}


func _on_ambush_aborted() -> void:
	# The arena may hear player_died before this recorder does; the death then reads it back.
	_finish_ambush("died" if GameState.health <= 0 else "aborted")
	# The abort removes the arena's enemies; they were not killed.
	_alive.clear()


func _on_boss_attack(attack: StringName, boss: CombatBoss) -> void:
	_boss_attacks[boss.get_instance_id()] = {"attack": String(attack), "t": now}
	if not _boss.is_empty():
		var counts: Dictionary = _boss["attacks"]
		counts[String(attack)] = int(counts.get(String(attack), 0)) + 1


func _on_boss_stage(stage: int, _boss_node: CombatBoss) -> void:
	if _boss.is_empty():
		return
	var stages: Dictionary = _boss["stage_seconds"]
	var key := str(_boss["stage"])
	stages[key] = snappedf(float(stages.get(key, 0.0)) + now - float(_boss["stage_start"]), 0.1)
	_boss["stage"] = stage
	_boss["stage_start"] = now


# --- trackers ---------------------------------------------------------------------------------


func _track_boss() -> void:
	for node in _player.get_tree().get_nodes_in_group(&"bosses"):
		var boss := node as CombatBoss
		if boss == null:
			continue
		var engaged: bool = boss.get("_player_engaged") == true
		var before := int(_boss_health.get(boss.get_instance_id(), boss.health))
		_boss_health[boss.get_instance_id()] = boss.health
		if boss.health < before and not engaged:
			var id := String(boss.enemy_id)
			disengaged_damage[id] = int(disengaged_damage.get(id, 0)) + before - boss.health
		if not _boss.is_empty() or boss.health <= 0 or not engaged:
			continue
		_boss = {
			"id": String(boss.enemy_id),
			"room": room,
			"start": now,
			"stage": boss.stage,
			"stage_start": now,
			"stage_seconds": {},
			"attacks": {},
			"damage_by_source": {},
			"node": boss,
		}
		return


func _finish_boss(outcome: String) -> void:
	if _boss.is_empty():
		return
	_on_boss_stage(int(_boss["stage"]), null)
	var boss = _boss["node"]
	var health := 0
	if is_instance_valid(boss):
		health = int(boss.get("health"))
	(
		bosses
		. append(
			{
				"id": _boss["id"],
				"room": _boss["room"],
				"outcome": outcome,
				"seconds": snappedf(now - float(_boss["start"]), 0.1),
				"stage_reached": _boss["stage"],
				"stage_seconds": _boss["stage_seconds"],
				"boss_health_left": health,
				"attacks": _boss["attacks"],
				"damage_by_source": _boss["damage_by_source"],
			}
		)
	)
	_boss = {}


func _track_kills() -> void:
	var seen := {}
	for node in _player.get_tree().get_nodes_in_group(&"enemies"):
		if node.is_queued_for_deletion() or int(node.get("health")) <= 0:
			continue
		seen[node.get_instance_id()] = String(node.get("enemy_id"))
	for id in _alive:
		if not seen.has(id):
			kills[_alive[id]] = int(kills.get(_alive[id], 0)) + 1
	_alive = seen


func _track_ambush_wave() -> void:
	if _ambush.is_empty():
		return
	var arena = _ambush["arena"]
	if is_instance_valid(arena):
		_ambush["wave"] = maxi(int(_ambush["wave"]), int(arena.get("wave_index")) + 1)


func _finish_ambush(outcome: String) -> void:
	if _ambush.is_empty():
		return
	(
		ambushes
		. append(
			{
				"id": _ambush["id"],
				"room": _ambush["room"],
				"outcome": outcome,
				"seconds": snappedf(now - float(_ambush["start"]), 0.1),
				"wave_reached": _ambush["wave"],
				"waves": _ambush["waves"],
				"damage_taken": _ambush["damage_taken"],
			}
		)
	)
	_ambush = {}


func _track_stuck(moving: bool) -> void:
	var position := _player.global_position
	if not _samples.is_empty() and now - float(_samples[-1]["t"]) < SAMPLE_SECONDS:
		return
	_samples.append({"t": now, "pos": position, "moving": moving})
	while not _samples.is_empty() and now - float(_samples[0]["t"]) > STUCK_WINDOW:
		_samples.pop_front()
	var window_full := now - float(_samples[0]["t"]) >= STUCK_WINDOW - SAMPLE_SECONDS
	var all_moving := _samples.all(func(sample: Dictionary) -> bool: return sample["moving"])
	var bounds := Rect2(_samples[0]["pos"], Vector2.ZERO)
	for sample in _samples:
		bounds = bounds.expand(sample["pos"])
	var stuck := window_full and all_moving and bounds.size.length() < STUCK_SPREAD
	if stuck and _stuck.is_empty():
		var cell := current_cell()
		_stuck = {"room": room, "cell": [cell.x, cell.y], "start": now - STUCK_WINDOW}
	elif not stuck:
		_finish_stuck()


func _finish_stuck() -> void:
	if _stuck.is_empty():
		return
	(
		stuck_episodes
		. append(
			{
				"room": _stuck["room"],
				"cell": _stuck["cell"],
				"t": snappedf(float(_stuck["start"]), 0.1),
				"seconds": snappedf(now - float(_stuck["start"]), 0.1),
			}
		)
	)
	_stuck = {}


func _track_pickups() -> void:
	var collected := GameState.collected_pickup_ids
	for index in range(_known_pickups, collected.size()):
		pickups.append({"t": snappedf(now, 0.01), "id": collected[index], "room": room})
	_known_pickups = collected.size()


func _track_breaks() -> void:
	var cell := Vector2(current_cell())
	for spec in _break_specs:
		if spec["room"] != room or cell.distance_to(Vector2(spec["cell"])) > BREAK_RADIUS:
			continue
		var id: String = spec["id"]
		if now - float(_break_seen.get(id, -10.0)) < 2.0:
			continue
		_break_seen[id] = now
		breaks[id] = int(breaks.get(id, 0)) + 1


func _reflected_count() -> int:
	var dash = _player.get("_dash") if _player != null else null
	if dash == null:
		return 0
	return int(dash.deflect.reflected_count)


## Best guess at what just hurt the player: a nearby enemy shot (credited to a boss attack when a
## boss released one recently), then boss contact, a nearby enemy, a hazard, else "unknown".
func _source() -> String:
	var tree := _player.get_tree()
	var center := _player.global_position + Vector2(0, -90)
	var boss_label := _boss_source(center)
	var shot := _nearest(tree.get_nodes_in_group(&"enemy_shot"), center, SHOT_RADIUS)
	if shot != null:
		return boss_label if not boss_label.is_empty() else "shot:%s" % shot.get("style")
	if not boss_label.is_empty():
		return boss_label
	var enemy := _nearest(tree.get_nodes_in_group(&"enemies"), center, CONTACT_RADIUS)
	if enemy != null:
		return String(enemy.get("enemy_id"))
	for group in HAZARD_GROUPS:
		if _nearest(tree.get_nodes_in_group(group), center, HAZARD_RADIUS) != null:
			return "hazard:%s" % String(group).trim_prefix("worldfx_")
	return "unknown"


func _boss_source(center: Vector2) -> String:
	for node in _player.get_tree().get_nodes_in_group(&"bosses"):
		var boss := node as CombatBoss
		if boss == null or boss.health <= 0:
			continue
		var last: Dictionary = _boss_attacks.get(boss.get_instance_id(), {})
		if not last.is_empty() and now - float(last["t"]) <= BOSS_ATTACK_MEMORY:
			return "%s:%s" % [boss.enemy_id, last["attack"]]
		if center.distance_to(boss.global_position) <= CONTACT_RADIUS * 1.5:
			return "%s:contact" % boss.enemy_id
	return ""


static func _nearest(nodes: Array, center: Vector2, radius: float) -> Node2D:
	var best: Node2D = null
	var best_distance := radius
	for node in nodes:
		var item := node as Node2D
		if item == null or item.is_queued_for_deletion():
			continue
		if item.has_method(&"presentation_state") and int(item.get("health")) <= 0:
			continue
		var distance := center.distance_to(item.global_position)
		if distance <= best_distance:
			best = item
			best_distance = distance
	return best
