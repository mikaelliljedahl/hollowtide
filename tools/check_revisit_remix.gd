extends Node

## Revisit remix (docs/features/revisit-remix.md): tier from defeated bosses, seeded elite rolls,
## elite stats/visuals/reward, the kit filter, and that the dev track and evidence runs never remix.
## godot --headless --path . res://tools/check_revisit_remix.tscn -- --test-mode

const CAMPAIGN := preload("res://scenes/campaign/campaign.tscn")
const Rooms = preload("res://scripts/campaign/campaign_rooms.gd")
const Catalog = preload("res://scripts/progression/content_catalog.gd")
const EnemySpawnScript = preload("res://scripts/campaign/enemy_spawn.gd")
const PROBE_ROOM := "remix_probe"
const PROBE_SPAWNS := 12
## Pinned rolls for PROBE_ROOM / Enemy01..Enemy12: spawn numbers that roll elite at each tier.
const PINNED := {1: [6], 2: [1, 6, 7], 3: [1, 5, 6, 7, 11, 12]}

var _failures: Array[String] = []
var _holder: Node2D


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_holder = Node2D.new()
	add_child(_holder)
	_tiers()
	_rolls()
	_campaign_table()
	_kit_filter()
	await _elite_stats()
	await _elite_reward()
	await _dev_untouched()
	await _campaign_live()
	await _finish()


func _finish() -> void:
	for failure in _failures:
		print("FAIL ", failure)
	print("revisit-remix: %s" % ("PASS" if _failures.is_empty() else "FAIL"))
	await TestShutdown.finish(get_tree(), 0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	print(("  ok  " if condition else "  FAIL ") + label)
	if not condition:
		_failures.append(label)


func _frames(count: int) -> void:
	for _index in count:
		await get_tree().physics_frame


func _full_kit() -> void:
	GameState.reset_progress()
	for ability_id in Catalog.ABILITY_IDS:
		if ability_id != &"missiles":
			GameState.unlock_ability(ability_id)
	GameState.acquire_missiles(Catalog.MISSILES_PER_TANK)


func _set_tier(value: int) -> void:
	for index in Catalog.BOSS_IDS.size():
		GameState.set_world_flag("boss:" + String(Catalog.BOSS_IDS[index]), index < value)


func _probe_elites(tier_value: int) -> Array:
	var hits: Array = []
	for number in range(1, PROBE_SPAWNS + 1):
		if RevisitRemix.rolls_elite(PROBE_ROOM, "Enemy%02d" % number, tier_value):
			hits.append(number)
	return hits


# --- pure rules ------------------------------------------------------------------------------


func _tiers() -> void:
	GameState.reset_progress()
	_check(RevisitRemix.tier() == 0, "no boss defeated is tier 0")
	for value in range(1, 4):
		_set_tier(value)
		_check(RevisitRemix.tier() == value, "%d boss flag(s) give tier %d" % [value, value])
	_check(RevisitRemix.chance(0) == 0.0, "tier 0 has no elite chance")
	_check(
		(
			RevisitRemix.chance(1) < RevisitRemix.chance(2)
			and RevisitRemix.chance(2) < RevisitRemix.chance(3)
		),
		"elite chance rises with every boss"
	)
	GameState.reset_progress()


func _rolls() -> void:
	_check(_probe_elites(0).is_empty(), "tier 0 rolls no elite")
	for value in range(1, 4):
		var first := _probe_elites(value)
		_check(first == _probe_elites(value), "tier %d rolls repeat exactly" % value)
		print("  tier %d probe elites %s" % [value, first])
		_check(
			first == PINNED[value],
			"tier %d probe elites match the pinned %s" % [value, PINNED[value]]
		)


## Every authored campaign enemy spawn: tier 0 never remixes; tiers 1-3 remix some common enemies,
## never a surprise enemy, and every elite of a tier stays elite at the next.
func _campaign_table() -> void:
	var spawns := _campaign_spawns()
	_check(spawns.size() >= 20, "found the authored campaign enemy spawns (%d)" % spawns.size())
	_full_kit()
	var common := spawns.filter(func(spawn: Array) -> bool: return Catalog.ENEMY_IDS.has(spawn[2]))
	print("  %d of the spawns are common enemies" % common.size())
	var previous := []
	for value in range(0, 4):
		var elites := []
		var surprise_elite := false
		for spawn in spawns:
			if RevisitRemix.is_elite_spawn(spawn[2], spawn[0], spawn[1], value, true):
				elites.append(spawn)
				surprise_elite = surprise_elite or not Catalog.ENEMY_IDS.has(spawn[2])
		print(
			"  tier %d: %d of %d campaign spawns are elite" % [value, elites.size(), spawns.size()]
		)
		if value == 0:
			_check(elites.is_empty(), "tier 0 remixes no campaign spawn")
		else:
			_check(not elites.is_empty(), "tier %d remixes at least one campaign spawn" % value)
		_check(not surprise_elite, "tier %d never remixes a surprise enemy" % value)
		_check(
			previous.all(func(spawn: Array) -> bool: return elites.has(spawn)),
			"tier %d keeps every elite of the tier below" % value
		)
		previous = elites
		var first_visit := false
		for spawn in spawns:
			first_visit = (
				first_visit
				or RevisitRemix.is_elite_spawn(spawn[2], spawn[0], spawn[1], value, false)
			)
		_check(not first_visit, "tier %d never remixes a first visit" % value)
	GameState.reset_progress()


func _campaign_spawns() -> Array:
	var spawns: Array = []
	for room_id in Rooms.ROOMS:
		var scene := load(String(Rooms.ROOMS[room_id]["scene"])) as PackedScene
		var room := scene.instantiate()
		for node in room.find_children("*", "Marker2D", true, false):
			if node.get_script() == EnemySpawnScript:
				spawns.append(
					[String(room_id), String(node.name), StringName(node.get("enemy_id"))]
				)
		room.free()
	return spawns


## The ambush kill filter carries over: an enemy the kit cannot beat never becomes elite, and a
## harpoon-only enemy needs a quiver that covers its elite health.
func _kit_filter() -> void:
	var always := _always_elite_spawn()
	_check(not always.is_empty(), "found a probe spawn that rolls elite at every tier")
	GameState.reset_progress()
	GameState.unlock_ability(&"beam")
	for enemy_id in [&"crawler", &"armored_guard"]:
		_check(
			not RevisitRemix.is_elite_spawn(enemy_id, PROBE_ROOM, always, 3, true),
			"beam-only kit never meets an elite %s" % enemy_id
		)
	_check(
		RevisitRemix.is_elite_spawn(&"hopper", PROBE_ROOM, always, 3, true),
		"beam-only kit still meets an elite hopper"
	)
	GameState.acquire_missiles(Catalog.MISSILES_PER_TANK)
	_check(
		RevisitRemix.is_elite_spawn(&"crawler", PROBE_ROOM, always, 3, true),
		(
			"a 5-bolt quiver (175 damage) can meet an elite crawler (%d HP)"
			% EnemyElite.health_for(&"crawler")
		)
	)
	GameState.max_missiles = 4
	_check(
		not RevisitRemix.is_elite_spawn(&"crawler", PROBE_ROOM, always, 3, true),
		"a 4-bolt quiver never meets an elite crawler"
	)
	_check(
		RevisitRemix.is_elite_spawn(&"armored_guard", PROBE_ROOM, always, 3, true),
		"4 bolts cover an elite armored guard (%d HP)" % EnemyElite.health_for(&"armored_guard")
	)
	GameState.unlock_ability(&"slipstream")
	GameState.unlock_ability(&"bombs")
	GameState.max_missiles = 0
	_check(
		RevisitRemix.is_elite_spawn(&"armored_guard", PROBE_ROOM, always, 3, true),
		"pulses beat an elite armored guard without bolts"
	)
	GameState.reset_progress()


func _always_elite_spawn() -> String:
	for number in range(1, 200):
		var spawn_id := "Probe%03d" % number
		# Rolls nest across tiers, so an elite at tier 1 is one at every tier.
		if RevisitRemix.rolls_elite(PROBE_ROOM, spawn_id, 1):
			return spawn_id
	return ""


# --- elite runtime ---------------------------------------------------------------------------


func _spawn(enemy_id: StringName, at: Vector2, elite: bool) -> Node2D:
	var enemy := EnemyFactory.create(enemy_id)
	enemy.position = at
	_holder.add_child(enemy)
	if elite:
		EnemyElite.apply(enemy)
	return enemy


func _elite_stats() -> void:
	_full_kit()
	for enemy_id in Catalog.ENEMY_IDS:
		var enemy := _spawn(enemy_id, Vector2(0, -4000), true)
		var base: int = Catalog.ENEMY_DATA[enemy_id]["max_health"]
		var expected := ceili(base * EnemyElite.HEALTH_SCALE)
		_check(
			int(enemy.get("max_health")) == expected and int(enemy.get("health")) == expected,
			"elite %s has %d HP (base %d)" % [enemy_id, expected, base]
		)
		_check(
			EnemyElite.is_elite(enemy) and enemy.find_child("EliteRim", true, false) != null,
			"elite %s is marked and carries a rim" % enemy_id
		)
		if enemy is CombatEnemy:
			_check(
				(
					int(enemy.get("contact_damage"))
					== int(Catalog.ENEMY_DATA[enemy_id]["contact_damage"])
				),
				"elite %s keeps catalog contact damage" % enemy_id
			)
		enemy.queue_free()
	await _frames(2)
	var crawler := _spawn(&"crawler", Vector2(0, -4000), false)
	var crawler_speed := float(crawler.get("move_speed"))
	EnemyElite.apply(crawler)
	EnemyElite.apply(crawler)
	_check(
		is_equal_approx(float(crawler.get("move_speed")), crawler_speed * EnemyElite.SPEED_SCALE),
		"elite crawler moves %.2fx, applied once" % EnemyElite.SPEED_SCALE
	)
	crawler.call("receive_hit", Catalog.MISSILE_DAMAGE * 4, &"missile", {})
	_check(int(crawler.get("health")) > 0, "elite crawler survives four harpoon bolts")
	crawler.queue_free()
	# Cadence: the attack cooldown runs faster; speed: the patrol covers more ground.
	var normal := _spawn(&"spitter", Vector2(0, -4000), false)
	var elite := _spawn(&"spitter", Vector2(400, -4000), true)
	normal.set("_attack_timer", 1.0)
	elite.set("_attack_timer", 1.0)
	var guard := _spawn(&"armored_guard", Vector2(0, -2000), false)
	var elite_guard := _spawn(&"armored_guard", Vector2(600, -2000), true)
	var guard_x := guard.global_position.x
	var elite_guard_x := elite_guard.global_position.x
	await _frames(30)
	var spent := 1.0 - float(normal.get("_attack_timer"))
	var elite_spent := 1.0 - float(elite.get("_attack_timer"))
	_check(
		absf(elite_spent - spent * EnemyElite.CADENCE_SCALE) < 0.02,
		(
			"elite cooldown runs %.2fx (%.3f vs %.3f s)"
			% [EnemyElite.CADENCE_SCALE, elite_spent, spent]
		)
	)
	var moved := absf(guard.global_position.x - guard_x)
	var elite_moved := absf(elite_guard.global_position.x - elite_guard_x)
	_check(
		moved > 0.0 and absf(elite_moved / moved - EnemyElite.SPEED_SCALE) < 0.02,
		(
			"elite guard patrols %.2fx as far (%.1f vs %.1f px)"
			% [EnemyElite.SPEED_SCALE, elite_moved, moved]
		)
	)
	var sprite := elite.get_node("Sprite2D") as Sprite2D
	_check(sprite.self_modulate == EnemyElite.TINT, "elite sprite carries the elite tint")
	for node in [normal, elite, guard, elite_guard]:
		node.queue_free()
	await _frames(2)
	GameState.reset_progress()


func _elite_reward() -> void:
	GameState.reset_progress()
	GameState.unlock_ability(&"beam")
	GameState.acquire_missiles(Catalog.MISSILES_PER_TANK)
	GameState.missile_count = 1
	var elite := _spawn(&"hopper", Vector2(0, -4000), true)
	elite.call("receive_hit", 9999, &"beam", {})
	# Strings, not StringNames: StringName sort order follows interning, not the alphabet.
	var kinds: Array[String] = []
	for node in _holder.get_children():
		if node is CombatLoot:
			kinds.append(String(node.get("kind")))
	kinds.sort()
	_check(
		kinds == ["energy_refill", "missile_refill"],
		"elite drops the needed refill plus energy (%s)" % [kinds]
	)
	var crawler := _spawn(&"crawler", Vector2(800, -4000), true)
	for node in _holder.get_children():
		if node is CombatLoot:
			node.queue_free()
	await _frames(2)
	crawler.call("receive_hit", 9999, &"missile", {})
	var crawler_loot := 0
	for node in _holder.get_children():
		if node is CombatLoot and not node.is_queued_for_deletion():
			crawler_loot += 1
	_check(crawler_loot == 2, "elite crawler drops a refill pair (%d)" % crawler_loot)
	for node in _holder.get_children():
		node.queue_free()
	await _frames(4)
	GameState.reset_progress()


## The dev track has no campaign root and never remixes; evidence runs never remix either.
func _dev_untouched() -> void:
	_full_kit()
	_set_tier(3)
	_check(
		not RevisitRemix.enabled(get_tree(), PackedStringArray()), "no campaign root: remix is off"
	)
	var room := CampaignRoom.new()
	room.room_id = PROBE_ROOM
	var entities := Node2D.new()
	entities.name = "Entities"
	room.add_child(entities)
	var spawn := EnemySpawnScript.new() as Marker2D
	spawn.name = _always_elite_spawn()
	spawn.set("enemy_id", &"hopper")
	entities.add_child(spawn)
	GameState.discovered_rooms.append(PROBE_ROOM)
	_holder.add_child(room)
	await _frames(3)
	var enemy := spawn.get("enemy") as Node2D
	_check(
		enemy != null and not EnemyElite.is_elite(enemy),
		"a spawn outside the campaign stays normal"
	)
	room.queue_free()
	await _frames(2)
	var fake_root := Node.new()
	fake_root.add_to_group(&"campaign_root")
	add_child(fake_root)
	_check(RevisitRemix.enabled(get_tree(), PackedStringArray()), "a campaign root enables remix")
	_check(
		not RevisitRemix.enabled(get_tree(), PackedStringArray(["--evidence-run=route"])),
		"an evidence run disables remix"
	)
	fake_root.free()
	GameState.reset_progress()


## Real campaign: at tier 3 a revisited room spawns exactly the predicted elites; the same room at
## tier 0, or on a first visit, spawns none.
func _campaign_live() -> void:
	_full_kit()
	GameState.set_checkpoint(Rooms.START_ROOM, Rooms.START_POSITION)
	var root := CAMPAIGN.instantiate()
	add_child(root)
	await _frames(20)
	(root.get("player") as Player).dev_invulnerable = true
	var room_id := _room_with_elite(3)
	_check(not room_id.is_empty(), "a room with saves holds a tier 3 elite (%s)" % room_id)
	if room_id.is_empty():
		root.queue_free()
		return
	_set_tier(3)
	GameState.discover_room(room_id)
	var elites := await _visit(root, room_id)
	_check(
		elites[0] > 0 and elites[0] == elites[1],
		"tier 3 revisit spawns the predicted elites (%d/%d)" % elites
	)
	_set_tier(0)
	elites = await _visit(root, room_id)
	_check(elites[0] == 0 and elites[1] == 0, "tier 0 revisit spawns no elite")
	_set_tier(3)
	GameState.discovered_rooms.erase(room_id)
	elites = await _visit(root, room_id)
	_check(elites[0] == 0, "tier 3 first visit spawns no elite")
	root.queue_free()
	await _frames(2)
	GameState.reset_progress()


func _room_with_elite(tier_value: int) -> String:
	for spawn in _campaign_spawns():
		var saves: Array = Rooms.ROOMS[spawn[0]]["saves"]
		if saves.is_empty() or spawn[0] == Rooms.START_ROOM:
			continue
		if RevisitRemix.is_elite_spawn(spawn[2], spawn[0], spawn[1], tier_value, true):
			return spawn[0]
	return ""


## Returns [elites spawned, elites predicted] for the room after teleporting in.
func _visit(root: Node, room_id: String) -> Array:
	var saves: Array = Rooms.ROOMS[room_id]["saves"]
	var revisit := GameState.discovered_rooms.has(room_id)
	root.call("teleport", room_id, Vector2(saves[0]))
	await _frames(6)
	var room := root.get("current_room") as Node
	var spawned := 0
	var predicted := 0
	for node in room.find_children("*", "Marker2D", true, false):
		if node.get_script() != EnemySpawnScript:
			continue
		var enemy := node.get("enemy") as Node
		if EnemyElite.is_elite(enemy):
			spawned += 1
		if RevisitRemix.is_elite_spawn(
			node.get("enemy_id"), room_id, String(node.name), RevisitRemix.tier(), revisit
		):
			predicted += 1
	return [spawned, predicted]
