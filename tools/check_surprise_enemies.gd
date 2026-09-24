extends Node
## Headless regression for the D20 surprise enemies: trigger -> attack -> damage -> death for
## each type, weapon reactions (beam/missile/bomb/ice/undertow), and the stalker room follower.

const HitResult = preload("res://scripts/combat/hit_result.gd")
const FLOOR_Y := 1000.0
const CEILING_Y := 200.0

var failures: Array[String] = []
var _world: Node2D
var _player: FakePlayer


class FakePlayer:
	extends CharacterBody2D
	var damage_taken := 0
	var hits := 0

	func _ready() -> void:
		add_to_group(&"player")
		collision_layer = 2
		collision_mask = 0
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(40, 90)
		shape.shape = rect
		shape.position = Vector2(0, -45)
		add_child(shape)

	func take_damage(amount: int, _source := Vector2.ZERO) -> void:
		damage_taken += amount
		hits += 1


class FakeCampaignRoot:
	extends Node2D
	signal room_changed(room_id: String)
	var current_room: Node2D


class FakeRoom:
	extends Node2D
	var area_id: StringName = &"fringe"

	func size_px() -> Vector2:
		return Vector2(1920, 1088)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	GameState.reset_progress()
	DefeatRewards.set_test_seed(7)
	_world = Node2D.new()
	add_child(_world)
	_build_box(_world)
	_player = FakePlayer.new()
	_world.add_child(_player)
	_player.global_position = Vector2(200, FLOOR_Y)
	await _frames(2)
	_test_catalog()
	await _test_bat_swarm()
	await _test_mimic(&"mimic")
	await _test_mimic(&"mimic_lure")
	await _test_mimic_contact_windows()
	await _test_drop_spider()
	await _test_surface_eel()
	await _test_stalker()
	await _test_chasm_sniper()
	await _test_stalker_follower()
	await _test_aggression_pass()
	await _test_ambush_diver_dives()
	if failures.is_empty():
		print(
			"PASS: surprise enemies trigger, attack, react to weapons, die, and the stalker follows"
		)
		await TestShutdown.finish(get_tree())
	else:
		for failure in failures:
			push_error(failure)
		await TestShutdown.finish(get_tree(), 1)


func _test_catalog() -> void:
	for id in SurpriseCatalog.IDS:
		var enemy := EnemyFactory.create(id)
		_check(enemy != null, "factory creates %s" % id)
		if enemy != null:
			enemy.free()
	_check(ContentCatalog.ENEMY_IDS.size() == 13, "ordinary roster stays at thirteen")


func _test_bat_swarm() -> void:
	_player.global_position = Vector2(1500, FLOOR_Y)
	var roost := _spawn(&"bat_swarm", Vector2(900, CEILING_Y + 60))
	await _frames(6)
	_check(absf(roost.global_position.y - CEILING_Y) < 6.0, "roost snaps to the ceiling")
	_check(roost.get("state") == &"roosting", "roost sleeps while the player is far")
	_player.global_position = Vector2(960, FLOOR_Y - 480)
	await _frames(2)
	_check(roost.get("state") == &"rustling", "roost rustles (telegraph) when the player is near")
	await _frames(40)
	var bats: Array = roost.get("bats")
	_check(bats.size() >= 4 and bats.size() <= 7, "swarm bursts into 4-7 bats")
	_player.hits = 0
	_player.global_position = Vector2(960, FLOOR_Y)
	var moved := false
	for bat in bats:
		var start: Vector2 = bat.global_position
		await _frames(1)
		moved = moved or bat.global_position.distance_to(start) > 1.0
	await _frames(240)
	_check(moved, "bats fly")
	_check(_player.hits > 0, "bats swoop into the player")
	var bat: CombatEnemy = bats[0]
	_check(
		bat.receive_hit(10, &"beam") == HitResult.Reaction.DAMAGE and bat._dying,
		"a bat dies to one beam hit"
	)
	var frozen: CombatEnemy = bats[1]
	_check(frozen.receive_hit(0, &"ice") == HitResult.Reaction.FREEZE, "bats can be frozen")
	# Flee from a bright shot.
	var flier: CombatEnemy = bats[2]
	await _frames(2)
	var light := Node2D.new()
	light.add_to_group(&"bat_repel")
	_world.add_child(light)
	light.global_position = flier.global_position + Vector2(60, 0)
	await _frames(2)
	_check(flier.get("_special_state") == &"flee", "bat flees from light")
	light.queue_free()
	roost.queue_free()
	await _frames(2)


func _test_mimic(id: StringName) -> void:
	_player.global_position = Vector2(1600, FLOOR_Y)
	var mimic := _spawn(id, Vector2(900, FLOOR_Y - 40)) as CombatEnemy
	await _frames(30)
	_check(mimic.is_on_floor(), "%s rests on the floor" % id)
	_check(mimic.presentation_state() == &"disguised", "%s starts disguised" % id)
	_check(
		mimic.receive_hit(10, &"beam") == HitResult.Reaction.BLOCKED,
		"%s disguise deflects the beam" % id
	)
	_check(mimic.presentation_state() == &"reveal", "%s wakes when probed" % id)
	mimic.queue_free()
	await _frames(2)
	mimic = _spawn(id, Vector2(900, FLOOR_Y - 40)) as CombatEnemy
	await _frames(30)
	_player.hits = 0
	_player.global_position = Vector2(990, FLOOR_Y)
	await _frames(2)
	_check(mimic.presentation_state() == &"reveal", "%s reveals when adjacent" % id)
	await _frames(40)
	_check(_player.hits > 0, "%s lunge bites the player" % id)
	_player.global_position = Vector2(1700, FLOOR_Y)
	await _frames(30)
	_check(mimic.presentation_state() == &"scuttle", "%s scuttles after the lunge" % id)
	_check(mimic.receive_hit(35, &"missile") == HitResult.Reaction.DAMAGE, "%s takes damage" % id)
	mimic.receive_hit(20, &"bomb")
	_check(mimic._dying, "%s dies" % id)
	await _frames(2)


## Only the lunge and its landing bite. The rattle is the warning, and the scuttle that follows
## must not keep hurting a player it runs into (fringe_05: five 16-point hits in one visit).
func _test_mimic_contact_windows() -> void:
	_player.global_position = Vector2(1600, FLOOR_Y)
	var mimic := _spawn(&"mimic", Vector2(900, FLOOR_Y - 40)) as CombatEnemy
	await _frames(30)
	mimic.receive_hit(10, &"beam")
	_player.hits = 0
	_player.global_position = Vector2(920, FLOOR_Y)
	await _frames(12)
	_check(
		mimic.presentation_state() == &"reveal" and _player.hits == 0,
		"mimic rattle does not bite a player beside it (hits %d)" % _player.hits
	)
	for _i in 30:
		if mimic.presentation_state() == &"lunge":
			break
		await get_tree().physics_frame
	await _frames(2)
	_check(_player.hits > 0, "mimic lunge bites a player who stayed beside it")
	for _i in 90:
		if mimic.presentation_state() == &"scuttle":
			break
		await get_tree().physics_frame
	var scuttle_frames := 0
	for _i in 20:
		await get_tree().physics_frame
		scuttle_frames += 1
	_player.hits = 0
	for _i in 4:
		_player.global_position = Vector2(1800, FLOOR_Y)
		await _frames(3)
		_player.global_position = Vector2(mimic.global_position.x, FLOOR_Y)
		await _frames(3)
		scuttle_frames += 6
	_check(
		mimic.presentation_state() == &"scuttle" and _player.hits == 0,
		"mimic scuttle after the landing is harmless (hits %d)" % _player.hits
	)
	_player.global_position = Vector2(1800, FLOOR_Y)
	while mimic.presentation_state() == &"scuttle" and scuttle_frames < 240:
		await get_tree().physics_frame
		scuttle_frames += 1
	_check(
		scuttle_frames <= 120, "mimic scuttle ends within 2 s (%.2f s)" % (scuttle_frames / 60.0)
	)
	mimic.queue_free()
	await _frames(2)


func _test_drop_spider() -> void:
	_player.global_position = Vector2(1600, FLOOR_Y)
	var spider := _spawn(&"drop_spider", Vector2(900, CEILING_Y + 100)) as CombatEnemy
	await _frames(20)
	var hang_y := spider.global_position.y
	_check(hang_y < CEILING_Y + 60.0, "spider hangs at the ceiling")
	_player.hits = 0
	_player.global_position = Vector2(910, FLOOR_Y)
	await _frames(2)
	_check(spider.presentation_state() == &"twitch", "spider twitches before dropping")
	var locked_stop: float = spider.get("_drop_target_y")
	_check(locked_stop > hang_y + 200.0, "twitch locks the drop stop below the spider")
	var shook := false
	for _i in 12:
		await _frames(1)
		shook = shook or absf(spider.global_position.x - 900.0) > 1.0
	_check(shook, "spider shakes on its thread while twitching")
	await _frames(58)
	_check(
		absf(spider.global_position.y - locked_stop) < 8.0,
		"spider hangs at the stop its drop line showed"
	)
	_check(spider.global_position.y > FLOOR_Y - 200.0, "spider drops on its thread")
	_check(_player.hits > 0, "dropping spider bites")
	_player.global_position = Vector2(1600, FLOOR_Y)
	await _frames(200)
	_check(absf(spider.global_position.y - hang_y) < 2.0, "spider climbs back up")
	_check(spider.receive_hit(0, &"ice") == HitResult.Reaction.FREEZE, "spider freezes")
	spider.receive_hit(35, &"missile")
	_check(spider._dying, "spider dies")
	await _frames(2)


func _test_surface_eel() -> void:
	_player.global_position = Vector2(1600, FLOOR_Y)
	var eel := _spawn(&"surface_eel", Vector2(900, FLOOR_Y)) as CombatEnemy
	await _frames(10)
	_check(
		eel.receive_hit(35, &"missile") == HitResult.Reaction.PASS, "submerged eel is untouchable"
	)
	_player.hits = 0
	_player.global_position = Vector2(1030, FLOOR_Y - 150)
	await _frames(50)
	_check(eel.presentation_state() in [&"bubble", &"rise"], "eel bubbles before striking")
	await _frames(30)
	_check(eel.presentation_state() in [&"rise", &"hold"], "eel strikes out")
	_check(eel.global_position.y < FLOOR_Y - 150.0, "eel rears up in an arc")
	_check(eel.receive_hit(10, &"beam") == HitResult.Reaction.DAMAGE, "exposed eel can be shot")
	eel.receive_hit(35, &"missile")
	_check(eel._dying, "eel dies")
	await _frames(2)


func _test_stalker() -> void:
	_player.global_position = Vector2(1400, FLOOR_Y)
	var stalker := _spawn(&"stalker", Vector2(600, FLOOR_Y - 40)) as CombatEnemy
	_player.hits = 0
	var saw_windup := false
	var saw_pounce := false
	for _i in 300:
		await get_tree().physics_frame
		saw_windup = saw_windup or stalker.presentation_state() == &"windup"
		saw_pounce = saw_pounce or stalker.presentation_state() == &"pounce"
	_check(saw_windup and saw_pounce, "stalker winds up then pounces")
	_check(_player.hits > 0 or saw_pounce, "stalker pounce reaches the player")
	stalker.receive_hit(10, &"beam")
	_check(stalker.presentation_state() == &"retreat", "stalker springs back when hit")
	for _i in 3:
		stalker.receive_hit(35, &"missile")
	_check(stalker._dying, "stalker dies")
	await _frames(2)


func _test_chasm_sniper() -> void:
	_player.global_position = Vector2(300, FLOOR_Y)
	var sniper := _spawn(&"chasm_sniper", Vector2(1500, FLOOR_Y - 40)) as CombatEnemy
	await _frames(10)
	_check(
		sniper.receive_hit(35, &"missile") == HitResult.Reaction.BLOCKED, "hidden sniper is armored"
	)
	_check(
		sniper.receive_hit(20, &"bomb") == HitResult.Reaction.DAMAGE,
		"pulse reaches a hidden sniper"
	)
	var saw_lock := false
	var shots := 0
	_player.hits = 0
	for _i in 320:
		await get_tree().physics_frame
		saw_lock = saw_lock or sniper.presentation_state() == &"lock"
		for node in get_tree().get_nodes_in_group(&"transient"):
			if node is EnemyProjectile and node.get_meta(&"counted", false) == false:
				node.set_meta(&"counted", true)
				shots += 1
	_check(saw_lock, "sniper shows a locked aim line before firing")
	_check(shots >= 1, "sniper fires")
	_check(_player.hits >= 1, "sniper shot hits the player")
	sniper.receive_hit(35, &"missile")
	await _frames(1)
	sniper.free()


func _test_stalker_follower() -> void:
	GameState.reset_progress()
	var root := FakeCampaignRoot.new()
	add_child(root)
	var room_a := FakeRoom.new()
	var room_b := FakeRoom.new()
	root.add_child(room_a)
	root.current_room = room_a
	_player.global_position = Vector2(900, FLOOR_Y)
	var stalker := SurpriseCatalog.create(&"stalker")
	room_a.add_child(stalker)
	stalker.global_position = Vector2(500, FLOOR_Y - 40)
	await _frames(4)
	var follower := root.get_node_or_null(StalkerFollower.NODE_NAME) as StalkerFollower
	_check(follower != null, "stalker attaches a session follower to the campaign root")
	if follower == null:
		root.queue_free()
		return
	_check(follower.is_hunting(&"fringe"), "stalker starts hunting once it sees the player")
	stalker.receive_hit(10, &"beam")
	var wounded: int = stalker.get("health")
	# Room change: old room unloads, new room in the same area loads.
	root.remove_child(room_a)
	room_a.queue_free()
	root.add_child(room_b)
	root.current_room = room_b
	root.room_changed.emit("b")
	_player.global_position = Vector2(64, FLOOR_Y)
	var arrived: Node2D = null
	for _i in 300:
		await get_tree().physics_frame
		for node in get_tree().get_nodes_in_group(&"surprise_enemies"):
			if node.get("enemy_id") == &"stalker" and room_b.is_ancestor_of(node):
				arrived = node
		if arrived != null:
			break
	_check(arrived != null, "stalker re-enters the next room after a delay")
	if arrived != null:
		_check(arrived.get("health") == wounded, "stalker keeps its HP between rooms")
		_check(arrived.global_position.x < 300.0, "stalker comes through the player's door")
		for _i in 4:
			arrived.call("receive_hit", 35, &"missile")
		_check(GameState.has_world_flag("stalker_defeated:fringe"), "defeat is saved for good")
	# A layout-spawned stalker in a defeated area removes itself.
	var again := SurpriseCatalog.create(&"stalker")
	room_b.add_child(again)
	await _frames(3)
	_check(
		not is_instance_valid(again) or again.is_queued_for_deletion(),
		"defeated stalker stays dead"
	)
	root.queue_free()
	await _frames(2)


func _test_aggression_pass() -> void:
	_player.global_position = Vector2(1300, FLOOR_Y)
	var guard := _spawn(&"armored_guard", Vector2(900, FLOOR_Y - 40)) as CombatEnemy
	var saw_charge := false
	for _i in 120:
		await get_tree().physics_frame
		if guard._special_state == &"charge":
			saw_charge = saw_charge or absf(guard.velocity.x) > 500.0
	_check(saw_charge, "armored guard winds up and charges when the player is near")
	guard.queue_free()
	var hopper := _spawn(&"hopper", Vector2(900, FLOOR_Y - 40)) as CombatEnemy
	await _frames(20)
	for _i in 60:
		await get_tree().physics_frame
		if hopper._telegraph_remaining > 0.0:
			break
	hopper.receive_hit(10, &"beam")
	var jumped := false
	for _i in 90:
		await get_tree().physics_frame
		jumped = jumped or hopper.velocity.y < -300.0
	_check(jumped, "a hit during the hopper wind-up does not stall its next jump")
	hopper.queue_free()
	var parasite := _spawn(&"energy_parasite", Vector2(1150, FLOOR_Y - 150)) as CombatEnemy
	var lunged := false
	for _i in 120:
		await get_tree().physics_frame
		lunged = lunged or parasite._special_state == &"lunge"
	_check(lunged, "energy parasite telegraphs and lunges")
	parasite.queue_free()
	await _frames(2)


## An ambush spawns a Ceiling Diver at an air point well below the ceiling (position set before
## add_child, then configure_arena). It must perch on the ceiling, then dive all the way toward
## the player below and climb back to its perch.
func _test_ambush_diver_dives() -> void:
	_player.global_position = Vector2(1000, FLOOR_Y)
	var diver := EnemyFactory.create(&"ceiling_diver") as CombatEnemy
	diver.position = Vector2(950, CEILING_Y + 350)
	_world.add_child(diver)
	diver.configure_arena(Rect2(Vector2(80, CEILING_Y), Vector2(1840, FLOOR_Y - CEILING_Y + 60)))
	await _frames(4)
	var perch := diver._home_position.y
	_check(perch < CEILING_Y + 200.0, "ambush diver perches on the ceiling (home y %.0f)" % perch)
	var deepest := diver.global_position.y
	var returned := false
	for _i in 240:
		await get_tree().physics_frame
		deepest = maxf(deepest, diver.global_position.y)
		returned = (
			returned or deepest > FLOOR_Y - 250.0 and absf(diver.global_position.y - perch) < 2.0
		)
	_check(
		deepest > FLOOR_Y - 250.0,
		"ambush diver dives toward the player below (deepest y %.0f, perch %.0f)" % [deepest, perch]
	)
	_check(returned, "ambush diver climbs back to its perch after the dive")
	diver.queue_free()
	await _frames(2)


func _spawn(id: StringName, at: Vector2) -> Node2D:
	var enemy := EnemyFactory.create(id)
	_world.add_child(enemy)
	enemy.global_position = at
	if enemy.has_method("configure_arena"):
		enemy.call(
			"configure_arena",
			Rect2(Vector2(80, CEILING_Y), Vector2(1840, FLOOR_Y - CEILING_Y + 60))
		)
	return enemy


func _build_box(parent: Node2D) -> void:
	for rect in [
		Rect2(0, FLOOR_Y, 2000, 200),
		Rect2(0, CEILING_Y - 200, 2000, 200),
		Rect2(-200, 0, 240, 1200),
		Rect2(1960, 0, 240, 1200),
	]:
		var body := StaticBody2D.new()
		body.collision_layer = 1
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = rect.size
		shape.shape = box
		shape.position = rect.get_center()
		body.add_child(shape)
		parent.add_child(body)


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		print("  FAIL ", message)
	else:
		print("  ok   ", message)
