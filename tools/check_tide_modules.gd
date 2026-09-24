extends Node

## Tide Sockets and Glyphs (docs/features/tide-modules.md): catalog agreement, capacity limits,
## socketing only during a save-shrine session, every glyph's gain and cost through the real
## weapon/damage paths, the Ebb Mend ambush heal, save round-trip and old saves, and the campaign
## flow (pickup in a room, Up at a shrine without travel targets opens the socket screen directly
## through the shared shrine menu logic, a changed loadout is saved).
## godot --headless --path . res://tools/check_tide_modules.tscn -- --test-mode

const Catalog = preload("res://scripts/progression/content_catalog.gd")
const TideCatalog = preload("res://scripts/progression/tide_catalog.gd")
const TideModules = preload("res://scripts/progression/tide_modules.gd")
const FluxRuntime = preload("res://scripts/player/player_flux_runtime.gd")
const HookScript = preload("res://scripts/campaign/tide_hook.gd")
const FastTravel = preload("res://scripts/campaign/fast_travel.gd")
const ArenaScript = preload("res://scripts/world/dynamic/ambush_arena.gd")
const CAMPAIGN := preload("res://scenes/campaign/campaign.tscn")
const TILE := 64.0
const FIRE_ORIGIN := Vector2(-40000, -40000)
const FORBIDDEN_NAMES := ["charm", "notch", "overcharm", "badge", "shard", "chip"]

var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog()
	_test_capacity()
	_test_station_gate()
	await _test_crossbow_glyphs()
	await _test_harpoon_and_pulse_glyphs()
	_test_damage_taken_glyphs()
	await _test_ebb_mend_heal()
	_test_save_round_trip()
	_test_old_saves()
	await _test_campaign_flow()
	GameState.reset_progress()
	if _failures.is_empty():
		print("check_tide_modules: PASS (%d checks)" % _checks)
	else:
		for failure in _failures:
			push_error("check_tide_modules: " + failure)
	await TestShutdown.finish(get_tree(), 0 if _failures.is_empty() else 1)


func _test_catalog() -> void:
	var expected: Array = [TideCatalog.SOCKET_KIND]
	for id: StringName in TideCatalog.GLYPHS:
		expected.append(TideCatalog.pickup_kind(id))
	_check(Catalog.TIDE_PICKUP_KINDS == expected, "content catalog lists every Tide pickup kind")
	_check(TideCatalog.GLYPHS.size() >= 6 and TideCatalog.GLYPHS.size() <= 8, "six to eight glyphs")
	_check(TideCatalog.MAX_CAPACITY == 5 and TideCatalog.BASE_CAPACITY == 2, "capacity 2 to 5")
	for id: StringName in TideCatalog.GLYPHS:
		var data: Dictionary = TideCatalog.GLYPHS[id]
		var cost := int(data["cost"])
		_check(cost >= 1 and cost <= 3, "%s costs 1-3" % id)
		_check(not String(data["upside"]).is_empty(), "%s states its gain" % id)
		_check(not String(data["downside"]).is_empty(), "%s states its cost" % id)
		_check((data["mods"] as Dictionary).size() >= 2, "%s has a gain and a downside" % id)
		for stat: StringName in data["mods"]:
			_check(TideCatalog.STATS.has(stat), "%s modifies known stat %s" % [id, stat])
		var name := String(data["name"]).to_lower()
		for word: String in FORBIDDEN_NAMES:
			_check(not name.contains(word), "%s name avoids '%s'" % [id, word])
		_check(Catalog.pickup_texture(TideCatalog.pickup_kind(id)) != null, "%s icon loads" % id)


func _test_capacity() -> void:
	GameState.reset_progress()
	var tide: TideModules = GameState.tide
	_check(tide.capacity() == 2, "capacity starts at 2")
	for index in 3:
		_check(
			GameState.collect_pickup("tide.socket.%d" % index, &"tide_socket"),
			"socket %d collects" % (index + 1)
		)
	_check(tide.capacity() == 5, "three sockets raise capacity to 5")
	_check(
		not GameState.collect_pickup("tide.socket.extra", &"tide_socket"), "a fourth socket rejects"
	)
	_check(tide.capacity() == 5, "capacity caps at 5")
	_check(GameState.collect_pickup("tide.glyph.q", &"glyph_quickstring"), "glyph collects")
	_check(tide.owns(&"quickstring"), "glyph is owned")
	_check(not GameState.collect_pickup("tide.glyph.q", &"glyph_quickstring"), "same ID rejects")
	_check(
		not GameState.collect_pickup("tide.glyph.q2", &"glyph_quickstring"),
		"second copy of an owned glyph rejects"
	)
	_check(not GameState.collect_pickup("tide.glyph.x", &"glyph_unknown"), "unknown glyph rejects")
	_check(GameState.collected_pickup_ids.has("tide.socket.0"), "socket pickup ID is recorded")


func _test_station_gate() -> void:
	var tide := _fresh_owning_all(0)
	_check(not tide.equip(&"quickstring"), "no socketing outside a shrine session")
	tide.open_station()
	_check(tide.equip(&"quickstring"), "socketing works at a shrine")
	_check(tide.equip(&"brine_hide"), "second 1-cost glyph fits capacity 2")
	_check(not tide.equip(&"farcast"), "a glyph over capacity is refused (no overload)")
	_check(tide.used() == 2 and tide.equipped.size() == 2, "refusal changes nothing")
	_check(not tide.equip(&"spring_tide"), "a 3-cost glyph never fits capacity 2")
	tide.close_station()
	_check(not tide.unequip(&"quickstring"), "no removal outside a shrine session")
	_check(tide.is_equipped(&"quickstring"), "loadout stays after the session")
	tide.open_station()
	_check(tide.toggle(&"quickstring") and not tide.is_equipped(&"quickstring"), "toggle removes")
	tide.close_station()


func _test_crossbow_glyphs() -> void:
	GameState.reset_progress()
	GameState.unlock_ability(&"beam")
	var base: ProjectileBase = await _fire(&"beam")
	var base_cooldown := _cooldown(&"beam")
	_check(base != null and base.damage_amount == Catalog.BEAM_DAMAGE, "plain bolt keeps damage")
	if base == null:
		return
	var base_speed := base.speed
	var base_lifetime := base.lifetime
	_equip_only([&"quickstring"])
	var quick: ProjectileBase = await _fire(&"beam")
	_check(quick != null and quick.damage_amount == 7, "Quickstring: bolt damage 10 -> 7")
	_check(quick != null and is_equal_approx(quick.speed, base_speed * 1.35), "Quickstring: faster")
	_check(is_equal_approx(_cooldown(&"beam"), base_cooldown * 0.6), "Quickstring: reload x0.6")
	_equip_only([&"farcast"])
	var far: ProjectileBase = await _fire(&"beam")
	_check(
		far != null and is_equal_approx(far.lifetime, base_lifetime * 1.4), "Farcast: range x1.4"
	)
	_check(far != null and far.damage_amount == Catalog.BEAM_DAMAGE, "Farcast keeps damage")
	_check(is_equal_approx(_cooldown(&"beam"), base_cooldown * 1.6), "Farcast: reload x1.6")
	_equip_only([&"spring_tide"])
	var spring: ProjectileBase = await _fire(&"beam")
	_check(spring != null and spring.damage_amount == 14, "Spring Tide: bolt damage 10 -> 14")
	_equip_only([&"brine_hide"])
	var brine: ProjectileBase = await _fire(&"beam")
	_check(brine != null and brine.damage_amount == 8, "Brine Hide: bolt damage 10 -> 8")
	_equip_only([&"brine_hide", &"quickstring"])
	var stacked: ProjectileBase = await _fire(&"beam")
	_check(
		stacked != null and stacked.damage_amount == 6, "multipliers stack by product (10*0.8*0.7)"
	)


func _test_harpoon_and_pulse_glyphs() -> void:
	GameState.reset_progress()
	GameState.unlock_ability(&"beam")
	for index in 2:
		GameState.collect_pickup("tide.quiver.%d" % index, &"missile_tank")
	var plain: ProjectileBase = await _fire(&"missile")
	_check(plain != null and plain.damage_amount == Catalog.MISSILE_DAMAGE, "plain harpoon damage")
	_check(GameState.missile_count == 9, "plain harpoon spends one bolt")
	_equip_only([&"heavy_barb"])
	var heavy: ProjectileBase = await _fire(&"missile")
	_check(heavy != null and heavy.damage_amount == 56, "Heavy Barb: harpoon 35 -> 56")
	_check(GameState.missile_count == 7, "Heavy Barb: a shot spends two bolts")
	while GameState.missile_count > 1:
		GameState.spend_missile()
	var dry: ProjectileBase = await _fire(&"missile")
	_check(dry == null and GameState.missile_count == 1, "Heavy Barb: one bolt left fires nothing")
	GameState.refill_missiles(99)
	_equip_only([&"spring_tide"])
	var spring: ProjectileBase = await _fire(&"missile")
	_check(spring != null and spring.damage_amount == 47, "Spring Tide: harpoon 35 -> 47")
	_equip_only([&"brine_hide"])
	var brine: ProjectileBase = await _fire(&"missile")
	_check(brine != null and brine.damage_amount == 28, "Brine Hide: harpoon 35 -> 28")

	GameState.unlock_ability(&"slipstream")
	GameState.unlock_ability(&"bombs")
	_equip_only([])
	var pulse := await _place_pulse()
	_check(pulse != null and pulse.damage_amount == Catalog.BOMB_DAMAGE, "plain pulse keeps damage")
	_check(
		pulse != null and is_equal_approx(pulse.fuse_seconds, Catalog.BOMB_FUSE_SECONDS),
		"plain pulse keeps its fuse"
	)
	_equip_only([&"deep_pulse"])
	pulse = await _place_pulse()
	_check(pulse != null and pulse.damage_amount == 35, "Deep Pulse: pulse 20 -> 35")
	_check(
		pulse != null and is_equal_approx(pulse.fuse_seconds, Catalog.BOMB_FUSE_SECONDS * 1.5),
		"Deep Pulse: fuse x1.5"
	)
	Weapons.reset_runtime()


func _test_damage_taken_glyphs() -> void:
	GameState.reset_progress()
	var host := Node2D.new()
	var flux := FluxRuntime.new(host, Callable())
	_check(flux.absorb_damage(20) == 20, "no glyph: hit unchanged")
	var cases := {&"brine_hide": 15, &"ebb_mend": 24, &"spring_tide": 27}
	for id: StringName in cases:
		_equip_only([id])
		_check(flux.absorb_damage(20) == cases[id], "%s: a 20 hit becomes %d" % [id, cases[id]])
	_equip_only([&"brine_hide"])
	_check(flux.absorb_damage(1) == 1, "a hit never drops to zero")
	host.free()


func _test_ebb_mend_heal() -> void:
	GameState.reset_progress()
	var hook := HookScript.new()
	add_child(hook)
	var arena := ArenaScript.new() as AmbushArena
	arena.flag_id = "tide.test.arena"
	add_child(arena)
	await get_tree().process_frame
	GameState.apply_damage(80)
	arena.cleared.emit()
	_check(GameState.health == 20, "no Ebb Mend: ambush clear heals nothing")
	_equip_only([&"ebb_mend"])
	arena.cleared.emit()
	_check(GameState.health == 70, "Ebb Mend: ambush clear restores 50")
	arena.queue_free()
	hook.queue_free()
	await get_tree().process_frame


func _test_save_round_trip() -> void:
	GameState.reset_progress()
	var empty := GameState.snapshot()
	_check(not empty.has(TideModules.SAVE_KEY), "nothing found: no tide key is written")
	GameState.collect_pickup("tide.socket.a", &"tide_socket")
	GameState.collect_pickup("tide.glyph.a", &"glyph_spring_tide")
	GameState.collect_pickup("tide.glyph.b", &"glyph_farcast")
	GameState.tide.open_station()
	GameState.tide.equip(&"spring_tide")
	GameState.tide.close_station()
	var saved := GameState.snapshot()
	_check(saved.has(TideModules.SAVE_KEY), "found items write the tide key")
	_check(int(saved["version"]) == Catalog.SCHEMA_VERSION, "schema version stays 2")
	var parsed: Variant = JSON.parse_string(JSON.stringify(saved))
	GameState.reset_progress()
	_check(parsed is Dictionary and GameState.restore_snapshot(parsed), "JSON round-trip restores")
	var tide: TideModules = GameState.tide
	_check(tide.sockets_found == 1 and tide.capacity() == 3, "sockets restored")
	_check(tide.owns(&"spring_tide") and tide.owns(&"farcast"), "owned glyphs restored")
	_check(tide.equipped.size() == 1 and tide.is_equipped(&"spring_tide"), "loadout restored")
	_check(not tide.at_station(), "restore never leaves a shrine session open")
	_check(GameState.snapshot() == saved, "snapshot after restore matches")

	var bad_cases := {
		"over capacity":
		{"sockets_found": 0, "owned": ["spring_tide"], "equipped": ["spring_tide"]},
		"not owned": {"sockets_found": 1, "owned": ["farcast"], "equipped": ["quickstring"]},
		"unknown glyph": {"sockets_found": 1, "owned": ["nameless_glyph"], "equipped": []},
		"duplicate": {"sockets_found": 1, "owned": ["farcast", "farcast"], "equipped": []},
		"too many sockets": {"sockets_found": 4, "owned": [], "equipped": []},
		"fractional sockets": {"sockets_found": 1.5, "owned": [], "equipped": []},
		"missing field": {"sockets_found": 1, "owned": []},
		"wrong type": ["farcast"],
	}
	for label: String in bad_cases:
		var tampered: Dictionary = saved.duplicate(true)
		tampered[TideModules.SAVE_KEY] = bad_cases[label]
		_check(not GameState.validate_snapshot(tampered), "tampered tide key rejected: %s" % label)
	_check(GameState.snapshot() == saved, "rejected saves leave state unchanged")


func _test_old_saves() -> void:
	GameState.reset_progress()
	GameState.unlock_ability(&"beam")
	var old := GameState.snapshot()
	GameState.collect_pickup("tide.glyph.old", &"glyph_quickstring")
	_check(GameState.restore_snapshot(old), "a v2 save without the tide key loads")
	_check(GameState.tide.owned.is_empty(), "loading it clears Tide state")
	var legacy := old.duplicate(true)
	legacy["version"] = Catalog.LEGACY_SCHEMA_VERSION
	for key in ["flux_current", "flux_max", "flux_tanks", "active_flux_module", "flux_enabled"]:
		legacy.erase(key)
	_check(GameState.restore_snapshot(legacy), "a v1 save still migrates")
	_check(
		GameState.tide.capacity() == TideCatalog.BASE_CAPACITY, "migrated save has base capacity"
	)


func _test_campaign_flow() -> void:
	CampaignEntry.prepare_new_game()
	var root := CAMPAIGN.instantiate()
	add_child(root)
	await _frames(30)
	var hook := root.find_child("TideHook", true, false)
	_check(hook != null, "campaign root adds the Tide hook")
	if hook == null:
		root.queue_free()
		return
	var menu := hook.get("menu") as CanvasLayer

	root.call("teleport", "fringe_03", Vector2(22.5 * TILE, 8 * TILE))
	await _frames(20)
	_check(GameState.tide.owns(&"quickstring"), "Quickstring pickup collects in fringe_03")
	_check(GameState.collected_pickup_ids.has("fringe_03.quickstring"), "room pickup ID recorded")

	root.call("teleport", "fringe_02", Vector2(14.5 * TILE, 32 * TILE))
	await _frames(20)
	await _tap(&"move_up")
	_check(not menu.call("is_open"), "Up away from a shrine opens nothing")

	root.call("teleport", "fringe_02", Vector2(17.5 * TILE, 32 * TILE))
	await _frames(40)
	var shrine := FastTravel.station_near("fringe_02", Vector2(17.5 * TILE, 32 * TILE))
	var offered: Array = root.call("shrine_options", shrine)
	_check(
		offered.size() == 1 and offered[0] == &"tide",
		"a shrine with no travel target offers only Tide Sockets"
	)
	await _tap(&"move_up")
	_check(menu.call("is_open"), "Up on the save shrine opens the socket menu")
	var shrine_menu := root.get("shrine_menu") as CanvasLayer
	_check(not shrine_menu.call("is_open"), "a single option skips the shrine menu")
	_check(get_tree().paused, "the menu pauses the game")
	_check(GameState.tide.at_station(), "the menu opens a shrine session")
	_check(bool(menu.call("press", &"quickstring")), "menu press sockets the glyph")
	var badge := hook.find_child("TideBadge", true, false)
	_check(badge != null and int(badge.call("icon_count")) == 1, "HUD strip shows one glyph")
	var had_save := SaveStore.has_save()
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.physical_keycode = KEY_ESCAPE
	escape.keycode = KEY_ESCAPE
	Input.parse_input_event(escape)
	await _frames(4)
	_check(not menu.call("is_open") and not get_tree().paused, "Esc closes the menu and resumes")
	_check(not GameState.tide.at_station(), "closing ends the shrine session")
	_check(not had_save and SaveStore.has_save(), "a changed loadout is saved at the shrine")
	GameState.reset_progress()
	_check(SaveStore.load_game() == OK, "the saved slot loads")
	_check(GameState.tide.is_equipped(&"quickstring"), "the saved slot keeps the loadout")
	root.queue_free()
	await _frames(4)


func _fresh_owning_all(sockets: int) -> TideModules:
	GameState.reset_progress()
	var tide: TideModules = GameState.tide
	for index in sockets:
		tide.collect(TideCatalog.SOCKET_KIND)
	for id: StringName in TideCatalog.GLYPHS:
		tide.collect(TideCatalog.pickup_kind(id))
	return tide


func _equip_only(ids: Array) -> void:
	var tide: TideModules = GameState.tide
	tide.sockets_found = TideCatalog.MAX_SOCKETS_FOUND
	tide.open_station()
	for id: StringName in tide.equipped.duplicate():
		tide.unequip(id)
	for id: StringName in ids:
		tide.collect(TideCatalog.pickup_kind(id))
		_check(tide.equip(id), "test loadout sockets %s" % id)
	tide.close_station()


func _fire(kind: StringName) -> ProjectileBase:
	Weapons.reset_runtime()
	await get_tree().process_frame
	var before := _projectiles()
	Weapons.fire(kind, FIRE_ORIGIN, Vector2.RIGHT)
	for shot in _projectiles():
		if not before.has(shot):
			return shot
	return null


func _place_pulse() -> Bomb:
	Weapons.reset_runtime()
	await get_tree().process_frame
	Weapons.fire(&"bomb", FIRE_ORIGIN, Vector2.RIGHT)
	for node in get_tree().get_nodes_in_group(&"bombs"):
		if node is Bomb and not node.is_queued_for_deletion():
			return node
	return null


func _projectiles() -> Array[ProjectileBase]:
	var result: Array[ProjectileBase] = []
	for node in get_tree().get_nodes_in_group(&"transient"):
		if node is ProjectileBase and not node.is_queued_for_deletion():
			result.append(node)
	return result


func _cooldown(kind: StringName) -> float:
	var cooldowns: Dictionary = Weapons.get("_cooldown_remaining")
	return float(cooldowns[kind])


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await _frames(3)
	Input.action_release(action)
	await _frames(3)


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
