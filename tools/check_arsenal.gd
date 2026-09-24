extends Node
## D19 original arsenal: harpoon pegs, Bubble Snare drift/platform, Echo ricochet (see
## check_beam_family) and the Undertow Dash (damage, barrier break, air-dash reset).

const Catalog = preload("res://scripts/progression/content_catalog.gd")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const HARPOON_SCENE: PackedScene = preload("res://scenes/combat/harpoon_shot.tscn")
const HOPPER_SCENE: PackedScene = preload("res://scenes/enemies/hopper.tscn")
const TILE := 64
const FLOOR_ROW := 15

var failures: Array[String] = []
var _world: Node2D
var _tiles: TileMapLayer
var _player: Player


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	GameState.reset_progress()
	await _start_world()
	await _test_harpoon_pegs()
	await _test_bubble_snare()
	await _test_dash_movement()
	await _test_dash_combat()
	await _clear_world()
	if failures.is_empty():
		print("PASS: harpoon pegs, bubble snare, undertow dash")
	else:
		for failure in failures:
			push_error(failure)
	await TestShutdown.finish(get_tree(), 0 if failures.is_empty() else 1)


# --- World --------------------------------------------------------------------------------


func _start_world() -> void:
	_world = Node2D.new()
	add_child(_world)
	_tiles = TileMapLayer.new()
	_tiles.tile_set = _make_tileset()
	_world.add_child(_tiles)
	# Floor across the arena, a tall wall at column 20, and a low tunnel ceiling over 26..29.
	for x in range(0, 40):
		_tiles.set_cell(Vector2i(x, FLOOR_ROW), 0, Vector2i.ZERO)
	for y in range(3, FLOOR_ROW):
		_tiles.set_cell(Vector2i(20, y), 0, Vector2i.ZERO)
	for x in range(26, 34):
		_tiles.set_cell(Vector2i(x, FLOOR_ROW - 2), 0, Vector2i.ZERO)
	_tiles.set_cell(Vector2i(34, FLOOR_ROW - 1), 0, Vector2i.ZERO)
	_player = PLAYER_SCENE.instantiate() as Player
	_world.add_child(_player)
	_player.reset_for_spawn(Vector2(6 * TILE, FLOOR_ROW * TILE))
	_player._camera.enabled = false
	await _frames(3)


func _make_tileset() -> TileSet:
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(TILE, TILE)
	tileset.add_physics_layer()
	tileset.set_physics_layer_collision_layer(0, 1)
	var source := TileSetAtlasSource.new()
	var image := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.3, 0.3, 0.3))
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = Vector2i(TILE, TILE)
	tileset.add_source(source, 0)
	source.create_tile(Vector2i.ZERO)
	var data := source.get_tile_data(Vector2i.ZERO, 0)
	var half := TILE * 0.5
	data.add_collision_polygon(0)
	data.set_collision_polygon_points(
		0,
		0,
		PackedVector2Array(
			[Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]
		)
	)
	return tileset


func _clear_world() -> void:
	Weapons.reset_runtime()
	if is_instance_valid(_world):
		_world.queue_free()
	await _frames(2)


# --- Harpoon ------------------------------------------------------------------------------


func _fire_harpoon(origin: Vector2, direction: Vector2) -> void:
	var shot := HARPOON_SCENE.instantiate() as ProjectileBase
	add_child(shot)
	shot.global_position = origin
	shot.launch(direction)
	await _frames(40)


func _pegs() -> Array[Node]:
	var live: Array[Node] = []
	for node in get_tree().get_nodes_in_group(&"harpoon_pegs"):
		if not node.is_queued_for_deletion():
			live.append(node)
	return live


func _test_harpoon_pegs() -> void:
	var wall_x := 20.0 * TILE
	await _fire_harpoon(Vector2(wall_x - 400.0, 11.0 * TILE + 5.0), Vector2.RIGHT)
	var pegs := _pegs()
	_check(pegs.size() == 1, "harpoon embeds one peg in plain rock (got %d)" % pegs.size())
	if pegs.size() == 1:
		var peg := pegs[0] as HarpoonPeg
		_check(peg.wall_side == -1, "peg sticks out of the wall toward the shooter")
		_check(
			absf(peg.global_position.x - wall_x) <= 4.0,
			"peg is anchored on the wall surface (%.1f)" % peg.global_position.x
		)
		_check(int(peg.global_position.y) % int(HarpoonPeg.SNAP) == 0, "peg top snaps to grid")
		_check((peg.collision_layer & 32) != 0, "peg is on the player-only platform layer")
		var shape := peg.get_node("CollisionShape2D") as CollisionShape2D
		_check(shape.one_way_collision, "peg is one-way from above")
		# Stand on it: drop the player just above the peg.
		_player.reset_for_spawn(Vector2(peg.global_position.x - 36.0, peg.global_position.y - 40.0))
		await _frames(20)
		_check(
			_player.is_on_floor() and absf(_player.global_position.y - peg.global_position.y) < 3.0,
			(
				"player stands on the peg (y=%.1f peg=%.1f)"
				% [_player.global_position.y, peg.global_position.y]
			)
		)
	await _fire_harpoon(Vector2(wall_x - 400.0, 9.0 * TILE + 5.0), Vector2.RIGHT)
	await _fire_harpoon(Vector2(wall_x - 400.0, 7.0 * TILE + 5.0), Vector2.RIGHT)
	_check(
		_pegs().size() == Catalog.MAX_HARPOON_PEGS,
		"at most %d pegs at once" % Catalog.MAX_HARPOON_PEGS
	)
	for node in _pegs():
		(node as HarpoonPeg).remaining = 0.05
	await _frames(8)
	_check(_pegs().is_empty(), "pegs crumble when their time runs out")
	# Floor hit (normal up) and a cramped tunnel give no peg.
	await _fire_harpoon(Vector2(10.0 * TILE, 12.0 * TILE), Vector2.DOWN)
	_check(_pegs().is_empty(), "harpoon into the floor leaves no peg")
	await _fire_harpoon(Vector2(30.0 * TILE, (FLOOR_ROW - 0.5) * TILE), Vector2.RIGHT)
	_check(_pegs().is_empty(), "no peg inside a low tunnel")
	# Pegs are transient: reset/room change clears them.
	await _fire_harpoon(Vector2(wall_x - 400.0, 10.0 * TILE + 5.0), Vector2.RIGHT)
	Weapons.reset_runtime()
	await _frames(2)
	_check(_pegs().is_empty(), "runtime reset clears pegs")
	_player.reset_for_spawn(Vector2(6 * TILE, FLOOR_ROW * TILE))
	await _frames(3)


# --- Bubble Snare -------------------------------------------------------------------------


func _test_bubble_snare() -> void:
	var hopper := HOPPER_SCENE.instantiate() as CombatEnemy
	hopper.set("runtime_id", &"hopper")
	_world.add_child(hopper)
	hopper.global_position = Vector2(12.0 * TILE, FLOOR_ROW * TILE - 40.0)
	await _frames(20)
	hopper.receive_hit(0, &"ice")
	var start_y := hopper.global_position.y
	_check(hopper.is_frozen, "Bubble Snare traps the enemy")
	_check((hopper.collision_layer & 32) != 0, "bubble is a standable platform")
	_check(hopper.get_node_or_null("BubbleSnare") != null, "bubble visual attached")
	await _frames(60)
	var rise := start_y - hopper.global_position.y
	_check(
		rise > 20.0 and rise <= Catalog.BUBBLE_MAX_RISE + 0.5, "bubble drifts upward (%.1f)" % rise
	)
	await _frames(60)
	rise = start_y - hopper.global_position.y
	_check(rise <= Catalog.BUBBLE_MAX_RISE + 0.5, "bubble rise is capped (%.1f)" % rise)
	# Under a low ceiling the bubble must not rise into the rock.
	hopper.reset_runtime()
	await _frames(2)
	var tunnel := HOPPER_SCENE.instantiate() as CombatEnemy
	_world.add_child(tunnel)
	tunnel.global_position = Vector2(28.5 * TILE, FLOOR_ROW * TILE - 40.0)
	await _frames(10)
	tunnel.receive_hit(0, &"ice")
	var tunnel_y := tunnel.global_position.y
	await _frames(90)
	_check(
		not tunnel.test_move(tunnel.global_transform, Vector2.ZERO),
		"bubble never overlaps the tunnel ceiling"
	)
	_check(
		tunnel.global_position.y >= tunnel_y - Catalog.BUBBLE_MAX_RISE, "tunnel bubble stays put"
	)
	await _frames(int(Catalog.FREEZE_SECONDS * 60.0))
	_check(not tunnel.is_frozen, "bubble pops after the snare duration")
	_check(tunnel.get_node_or_null("BubbleSnare") == null, "popped bubble visual is removed")
	hopper.queue_free()
	tunnel.queue_free()
	await _frames(2)


# --- Undertow Dash ------------------------------------------------------------------------


func _dash_input() -> void:
	Input.action_press(&"dash")
	await get_tree().physics_frame
	Input.action_release(&"dash")


func _test_dash_movement() -> void:
	GameState.reset_progress()
	_player.reset_for_spawn(Vector2(4 * TILE, FLOOR_ROW * TILE))
	await _frames(3)
	await _dash_input()
	_check(not _player.dash_active, "no dash without the Undertow Dash upgrade")
	GameState.unlock_ability(&"undertow_dash")
	_check(InputMap.has_action(&"dash"), "dash input action exists")
	var start_x := _player.global_position.x
	Input.action_press(&"dash")
	await _frames(2)
	Input.action_release(&"dash")
	_check(_player.dash_active, "dash input starts the dash")
	await _frames(20)
	var travel := _player.global_position.x - start_x
	_check(not _player.dash_active, "dash ends")
	_check(
		travel > 220.0 and travel < 420.0, "ground dash travels a short burst (%.0f px)" % travel
	)
	# Air: one dash per airtime, restored on landing.
	await _frames(30)
	_player.velocity.y = -PlayerConfig.JUMP_VELOCITY
	await _frames(8)
	_check(not _player.is_on_floor(), "player is airborne")
	var air_y := _player.global_position.y
	_check(_player.start_dash(-1), "first air dash")
	await get_tree().physics_frame
	_check(absf(_player.global_position.y - air_y) < 30.0, "air dash holds altitude")
	await _frames(20)
	_check(not _player.can_dash(), "second air dash is refused")
	await _frames(60)
	_check(_player.is_on_floor(), "player lands")
	await get_tree().physics_frame
	_check(_player.can_dash(), "landing restores the dash")
	# Damage is ignored during the dash.
	var health := GameState.health
	_player.start_dash(1)
	_player.take_damage(20, _player.global_position + Vector2(40.0, 0.0))
	_check(GameState.health == health, "dash ignores contact damage")
	await _frames(30)


func _test_dash_combat() -> void:
	GameState.reset_progress()
	GameState.unlock_ability(&"undertow_dash")
	_player.reset_for_spawn(Vector2(3 * TILE, FLOOR_ROW * TILE))
	await _frames(3)
	var barrier := AbilityGate.new()
	barrier.gate_kind = &"undertow"
	barrier.gate_size = Vector2(64, 192)
	_world.add_child(barrier)
	barrier.global_position = Vector2(6 * TILE, FLOOR_ROW * TILE - 96.0)
	var socket := AbilityGate.new()
	socket.gate_kind = &"missile"
	_world.add_child(socket)
	socket.global_position = Vector2(12 * TILE, FLOOR_ROW * TILE - 96.0)
	await _frames(2)
	_player.start_dash(1)
	await _frames(20)
	_check(not barrier.is_vulnerable_to(&"undertow"), "dash breaks the undertow barrier")
	_check(
		_player.global_position.x > barrier.global_position.x, "dash carries through the barrier"
	)
	_check(socket.is_vulnerable_to(&"missile"), "dash does not open a harpoon socket")
	socket.queue_free()
	var hopper := HOPPER_SCENE.instantiate() as CombatEnemy
	_world.add_child(hopper)
	_player.reset_for_spawn(Vector2(3 * TILE, FLOOR_ROW * TILE))
	hopper.global_position = Vector2(6 * TILE, FLOOR_ROW * TILE - 40.0)
	await _frames(3)
	var before := hopper.health
	hopper.set_physics_process(false)
	_player.start_dash(1)
	await _frames(12)
	_check(
		before - hopper.health == Catalog.UNDERTOW_DAMAGE,
		"dash damages an enemy once (%d)" % (before - hopper.health)
	)
	hopper.queue_free()
	await _frames(20)


func _frames(count: int) -> void:
	for index in count:
		await get_tree().physics_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok  ", label)
	else:
		failures.append(label)
		print("  FAIL ", label)
