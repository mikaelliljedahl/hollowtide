class_name DevStationLayout
extends RefCounted

const PICKUP_SCENE: PackedScene = preload("res://scenes/pickups/pickup.tscn")
const ContentCatalog = preload("res://scripts/progression/content_catalog.gd")
const REFILL_SCRIPT = preload("res://scripts/dev/dev_refill_pad.gd")
const CHECKPOINT_SCRIPT = preload("res://scripts/dev/dev_checkpoint_pad.gd")
const HAZARD_SCRIPT = preload("res://scripts/dev/dev_hazard.gd")
const FINAL_GATE_SCRIPT = preload("res://scripts/dev/dev_final_gate.gd")
const PASSAGE_SCRIPT = preload("res://scripts/dev/dev_passage.gd")
const FLOOR_SURFACE_Y := 1152.0
const CEILING_BOTTOM_Y := 64.0
const STATION_SIZE := Vector2(2048, 1216)


static func create_pickups(owner: Node2D, origins: Dictionary) -> void:
	# Ability stations stay on the open floor. Tanks use side galleries/platforms so they do not
	# become progression gates or obstruct the station's main traversal line.
	var pickups := [
		["S1", "S1.ability.slipstream", &"slipstream", Vector2(360, 1020)],
		["S1", "S1.ability.high_jump", &"high_jump", Vector2(620, 1020)],
		["S1", "S1.capacity.energy_01", &"energy_tank", Vector2(1720, 640)],
		["S2", "S2.ability.beam", &"beam", Vector2(420, 1020)],
		["S2", "S2.capacity.missile_01", &"missile_tank", Vector2(720, 1020)],
		["S2", "S2.capacity.missile_02", &"missile_tank", Vector2(1850, 1020)],
		["S2", "S2.capacity.energy_02", &"energy_tank", Vector2(1700, 700)],
		["S3", "S3.ability.bombs", &"bombs", Vector2(480, 1020)],
		["S3", "S3.capacity.missile_03", &"missile_tank", Vector2(1750, 1020)],
		["S3", "S3.capacity.missile_04", &"missile_tank", Vector2(1950, 1020)],
		["S3", "S3.capacity.energy_03", &"energy_tank", Vector2(1420, 700)],
		["S4", "S4.ability.long_beam", &"long_beam", Vector2(400, 1020)],
		["S4", "S4.ability.pressure_seal", &"pressure_seal", Vector2(700, 1020)],
		["S4", "S4.capacity.missile_05", &"missile_tank", Vector2(1100, 1020)],
		["S4", "S4.capacity.missile_06", &"missile_tank", Vector2(1600, 820)],
		["S4", "S4.capacity.energy_04", &"energy_tank", Vector2(1450, 700)],
		["S5", "S5.ability.ice_beam", &"ice_beam", Vector2(680, 1020)],
		["S5", "S5.capacity.missile_07", &"missile_tank", Vector2(900, 1020)],
		["S5", "S5.capacity.missile_08", &"missile_tank", Vector2(1950, 1020)],
		["S5", "S5.capacity.energy_05", &"energy_tank", Vector2(1450, 560)],
		["S6", "S6.ability.wave_beam", &"wave_beam", Vector2(500, 1020)],
		["S6", "S6.ability.undertow_dash", &"undertow_dash", Vector2(760, 1020)],
		["S6", "S6.capacity.missile_09", &"missile_tank", Vector2(1050, 1020)],
		["S6", "S6.capacity.missile_10", &"missile_tank", Vector2(1850, 1020)],
		["S6", "S6.capacity.energy_06", &"energy_tank", Vector2(1700, 640)],
		["S7", "S7.capacity.missile_11", &"missile_tank", Vector2(1900, 1020)],
		["S9", "S9.ability.flux_shield", &"flux_shield", Vector2(480, 900)],
		["S9", "S9.ability.burst_beam", &"burst_beam", Vector2(760, 900)],
		["S10", "S10.ability.echo_scan", &"echo_scan", Vector2(520, 820)],
		["S9", "S9.capacity.flux_01", &"flux_tank", Vector2(1280, 820)],
		["S9", "S9.capacity.flux_02", &"flux_tank", Vector2(1500, 820)],
		["S10", "S10.capacity.flux_03", &"flux_tank", Vector2(1320, 520)],
		["S10", "S10.capacity.flux_04", &"flux_tank", Vector2(1700, 520)],
	]
	for pickup in pickups:
		spawn_pickup(owner, pickup[1], pickup[2], origins[pickup[0]] + pickup[3])


static func spawn_pickup(
	owner: Node2D, instance_id: String, kind: StringName, location: Vector2
) -> void:
	if GameState.collected_pickup_ids.has(instance_id):
		return
	if not ContentCatalog.is_pickup_kind(kind):
		return
	var pickup := PICKUP_SCENE.instantiate() as Area2D
	if pickup == null:
		return
	pickup.name = "Pickup_" + instance_id.replace(".", "_")
	pickup.set("instance_id", instance_id)
	pickup.set("kind", kind)
	pickup.global_position = location
	owner.add_child(pickup)
	pickup.add_to_group("dev_owned")
	pickup.add_to_group("dev_pickup")


static func create_station_mechanics(owner: Node2D, origins: Dictionary) -> void:
	_create_passages(owner, origins)
	_add_gate(
		owner,
		origins,
		"S2",
		&"missile",
		"dev:S2:missile_gate",
		Vector2(1180, 700),
		Vector2(64, 192)
	)
	_add_gate(
		owner, origins, "S2", &"wave", "dev:S2:wave_gate", Vector2(1510, 640), Vector2(64, 192)
	)
	var wave_grate := WaveGrate.new()
	wave_grate.grate_size = Vector2(36, 192)
	wave_grate.position = origins["S2"] + Vector2(1740, 640)
	owner.add_child(wave_grate)
	wave_grate.add_to_group("dev_owned")
	wave_grate.add_to_group("dev_gate")
	_add_gate(
		owner, origins, "S3", &"bomb", "dev:S3:bomb_block", Vector2(1420, 700), Vector2(128, 128)
	)
	_add_gate(
		owner,
		origins,
		"S6",
		&"undertow",
		"dev:S6:undertow_gate",
		Vector2(1480, 700),
		Vector2(64, 192)
	)
	_add_gate(
		owner,
		origins,
		"S6",
		&"missile",
		"dev:S6:crawler_gate",
		Vector2(1760, 640),
		Vector2(64, 192)
	)
	_add_final_gate(owner, origins)
	_add_s3_ambush(owner, origins)
	_add_refill(owner, origins, "S4", Vector2(880, 1114), true, true)
	_add_refill(owner, origins, "S4", Vector2(1500, 1114), true, false)
	_add_checkpoint(owner, origins, "S5", Vector2(840, 1114))
	_add_refill(owner, origins, "S5", Vector2(1080, 1114), true, true)
	_add_checkpoint(owner, origins, "S7", Vector2(640, 1114))
	_add_refill(owner, origins, "S7", Vector2(880, 1114), true, true)
	_add_refill(owner, origins, "S8", Vector2(380, 1114), true, true)
	_add_checkpoint(owner, origins, "S8", Vector2(760, 1114))
	_add_refill(owner, origins, "S8", Vector2(1540, 1114), false, true)
	_add_refill(owner, origins, "S9", Vector2(420, 1114), true, true)
	_add_checkpoint(owner, origins, "S9", Vector2(960, 1114))
	_add_refill(owner, origins, "S9", Vector2(1600, 1114), false, false, true)
	# Fluid basins and industrial vents all terminate on real floor/platform contact lines.
	_add_hazard(owner, origins, "S4", Vector2(1240, 864), Vector2(320, 64), 18, &"steam_embers")
	_add_hazard(owner, origins, "S6", Vector2(1056, 1184), Vector2(320, 64), 18, &"lava_surface")
	_add_hazard(owner, origins, "S6", Vector2(1504, 1184), Vector2(320, 64), 18, &"lava_surface")
	_add_hazard(owner, origins, "S6", Vector2(1280, 1104), Vector2(96, 96), 0, &"fire_small", false)
	_add_hazard(
		owner, origins, "S6", Vector2(1760, 1072), Vector2(128, 160), 0, &"fire_vent", false
	)
	_add_hazard(
		owner, origins, "S6", Vector2(720, 1088), Vector2(128, 128), 0, &"steam_vent", false
	)
	_add_hazard(owner, origins, "S7", Vector2(1120, 1184), Vector2(320, 64), 18, &"lava_surface")
	_add_hazard(
		owner,
		origins,
		"S10",
		Vector2(1500, 672),
		Vector2(320, 64),
		8,
		&"steam_embers",
		true,
		&"depths_pressure"
	)


static func _create_passages(owner: Node2D, origins: Dictionary) -> void:
	for existing in owner.get_tree().get_nodes_in_group(&"dev_passage"):
		if is_instance_valid(existing) and owner.is_ancestor_of(existing):
			existing.get_parent().remove_child(existing)
			existing.free()
	for index in range(1, 11):
		var room_id := "S%d" % index
		var origin: Vector2 = origins.get(room_id, Vector2.ZERO)
		if origin == Vector2.ZERO:
			continue
		var passage := PASSAGE_SCRIPT.new() as Node2D
		if passage == null:
			continue
		passage.name = "DevPassage_%s" % room_id
		passage.position = Vector2(origin.x, FLOOR_SURFACE_Y)
		owner.add_child(passage)


## S3's ambush: seals both ground-level doorways and runs three waves. Scripted evidence routes
## cannot fight, so it is not built during `--evidence-run=` sessions.
static func _add_s3_ambush(owner: Node2D, origins: Dictionary) -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence-run="):
			return
	var centre := STATION_SIZE * 0.5
	var arena := AmbushArena.new()
	arena.name = "DevAmbush_S3"
	arena.arena_size = STATION_SIZE
	arena.area_override = &"nexus"
	arena.flag_id = "dev:S3:ambush"
	arena.wave = PackedStringArray(["hopper", "hopper"])
	arena.extra_waves = [
		PackedStringArray(["hopper", "hopper", "spitter"]),
		PackedStringArray(["armored_guard", "vent_flyer", "vent_flyer"]),
	]
	# Station-local points in spawn order: floor walkers, the spitter on the high platform, and
	# open air for the flyers.
	arena.spawn_offsets = PackedVector2Array()
	var points := [
		Vector2(400, 1112),
		Vector2(1800, 1112),
		Vector2(400, 1112),
		Vector2(1150, 1112),
		Vector2(1540, 736),
		Vector2(1150, 1112),
		Vector2(700, 500),
		Vector2(1000, 600),
	]
	for point in points:
		arena.spawn_offsets.append(point - centre)
	# Ground-level doorways in both side walls, rows 14-17.
	arena.door_rects = [
		Rect2(Vector2(0, 896) - centre, Vector2(64, 256)),
		Rect2(Vector2(1984, 896) - centre, Vector2(64, 256)),
	]
	# Trigger stops short of the raised bomb-block platform (x 1280+).
	arena.trigger_rect = Rect2(Vector2(704, 768) - centre, Vector2(512, 384))
	arena.position = origins["S3"] + centre
	owner.add_child(arena)
	arena.add_to_group("dev_owned")
	arena.add_to_group("dev_ambush")


static func _add_gate(
	owner: Node2D,
	origins: Dictionary,
	room_id: String,
	kind: StringName,
	flag_id: String,
	local_position: Vector2,
	size: Vector2
) -> void:
	var gate := AbilityGate.new()
	gate.gate_kind = kind
	gate.flag_id = flag_id
	gate.gate_size = size
	gate.position = origins[room_id] + local_position
	owner.add_child(gate)
	gate.add_to_group("dev_owned")
	gate.add_to_group("dev_gate")


static func _add_final_gate(owner: Node2D, origins: Dictionary) -> void:
	var gate := FINAL_GATE_SCRIPT.new() as StaticBody2D
	if gate == null:
		return
	gate.gate_size.y = FLOOR_SURFACE_Y - CEILING_BOTTOM_Y
	gate.position = origins["S9"] + Vector2(1780, (FLOOR_SURFACE_Y + CEILING_BOTTOM_Y) * 0.5)
	owner.add_child(gate)


static func _add_refill(
	owner: Node2D,
	origins: Dictionary,
	room_id: String,
	local_position: Vector2,
	health: bool,
	missiles: bool,
	flux: bool = false
) -> void:
	var pad := REFILL_SCRIPT.new() as Area2D
	if pad == null:
		return
	pad.refill_health = health
	pad.refill_missiles = missiles
	pad.refill_flux = flux
	pad.position = origins[room_id] + local_position
	owner.add_child(pad)


static func _add_checkpoint(
	owner: Node2D, origins: Dictionary, room_id: String, local_position: Vector2
) -> void:
	var pad := CHECKPOINT_SCRIPT.new() as Area2D
	if pad == null:
		return
	pad.position = origins[room_id] + local_position
	pad.player_entered.connect(
		func(): owner.call("_on_station_checkpoint_entered", room_id, pad.global_position)
	)
	pad.player_left.connect(func(): owner.call("_on_station_checkpoint_left"))
	owner.add_child(pad)


static func _add_hazard(
	owner: Node2D,
	origins: Dictionary,
	room_id: String,
	local_position: Vector2,
	size: Vector2,
	damage: int,
	profile: StringName = &"steam_embers",
	contacts := true,
	ambient: StringName = &""
) -> void:
	var hazard := HAZARD_SCRIPT.new() as Area2D
	if hazard == null:
		return
	hazard.configure_profile(profile, size, damage, contacts, true, ambient)
	hazard.position = origins[room_id] + local_position
	owner.add_child(hazard)
	hazard.add_to_group("dev_optional_fixture")
