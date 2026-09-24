extends Node

const Catalog = preload("res://scripts/progression/content_catalog.gd")
const TestShutdown = preload("res://tools/test_shutdown.gd")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const HUD_SCENE: PackedScene = preload("res://scenes/ui/hud.tscn")
const DEV_PANEL_SCRIPT = preload("res://scripts/ui/dev_panel.gd")

var _failures: Array[String] = []
var _player: Player


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(_action_has_key("jump", KEY_A), "InputMap maps A to jump")
	_check(_action_has_key("slipstream", KEY_Z), "InputMap maps Z to Slipstream")
	_check(_action_has_key("jump", KEY_SPACE), "InputMap maps Space to jump")
	_check(not _action_has_key("slipstream", KEY_A), "InputMap rejects A as Slipstream")
	_check(not _action_has_key("jump", KEY_Z), "InputMap rejects Z as jump")
	_check(_action_has_key("cycle_flux", KEY_Q), "InputMap maps Q to Flux select")
	_check(_action_has_key("activate_flux", KEY_F), "InputMap maps F to Flux activate")
	_check(InputMap.has_action("cycle_flux"), "Q cycle action is registered")
	_check(InputMap.has_action("activate_flux"), "F activate action is registered")
	_check(not Catalog.PICKUP_KINDS.has(&"flux_refill"), "Flux refill is not in base kinds")
	_check(Catalog.is_flux_pickup_kind(&"flux_refill"), "Flux refill is catalogued once")
	for kind in [&"flux_shield", &"burst_beam", &"echo_scan", &"flux_tank", &"flux_refill"]:
		_check(ResourceLoader.exists(Catalog.pickup_icon_path(kind)), "%s has icon" % kind)
	_check(Catalog.FLUX_TANK_CONTENT_IDS.size() == 4, "four stable Flux Tank content IDs")
	_check(
		Catalog.WEAPON_DATA[&"flux_burst"]["kind"] == &"beam", "Burst preserves beam damage kind"
	)
	await _spawn_player()
	await _test_flux_controls()
	await _test_exclusivity_and_shield()
	await _test_burst()
	await _test_echo_scan()
	_test_refill_and_catalog_state()
	await _test_hud_and_panel()
	_player.queue_free()
	await get_tree().process_frame
	GameState.reset_progress()
	if _failures.is_empty():
		print("check_flux_runtime: PASS")
	else:
		for failure in _failures:
			push_error("check_flux_runtime: " + failure)
	await TestShutdown.finish(get_tree(), 0 if _failures.is_empty() else 1)


func _spawn_player() -> void:
	_player = PLAYER_SCENE.instantiate() as Player
	add_child(_player)
	await get_tree().process_frame
	_player.reset_for_spawn(Vector2(320.0, 480.0))


func _test_flux_controls() -> void:
	GameState.reset_progress()
	GameState.unlock_ability(&"flux_shield")
	GameState.unlock_ability(&"burst_beam")
	GameState.unlock_ability(&"echo_scan")
	GameState.set_active_flux_module(&"flux_shield")
	Input.action_press("cycle_flux")
	_player._handle_weapon_input()
	Input.action_release("cycle_flux")
	_check(GameState.active_flux_module == &"burst_beam", "Q selects next owned Flux module")
	Input.action_press("activate_flux")
	_player._handle_weapon_input()
	Input.action_release("activate_flux")
	_check(GameState.flux_enabled, "F activates selected Flux module")
	GameState.set_flux_enabled(false)


func _test_exclusivity_and_shield() -> void:
	GameState.reset_progress()
	GameState.unlock_ability(&"flux_shield")
	GameState.unlock_ability(&"burst_beam")
	GameState.unlock_ability(&"echo_scan")
	GameState.unlock_ability(&"pressure_seal")
	GameState.set_active_flux_module(&"flux_shield")
	GameState.set_flux_enabled(true)
	var before_health := GameState.health
	var before_velocity := _player.velocity
	_player.take_damage(11, Vector2.RIGHT)
	_check(GameState.health == before_health, "full Shield absorbs post-Pressure Seal damage")
	_check(
		GameState.flux_current == Catalog.FLUX_BASE_MAX - 6,
		"Shield drains exact post-Pressure Seal amount"
	)
	_check(_player.velocity == before_velocity, "full Shield preserves knockback")
	GameState.refill_flux()
	GameState.spend_flux(GameState.flux_current - 1)
	_player.velocity = Vector2.ZERO
	_player.take_damage(11, Vector2.RIGHT)
	_check(GameState.health == before_health - 5, "partial Shield passes exact remainder")
	_check(GameState.flux_current == 0 and not GameState.flux_enabled, "zero Flux disables module")
	GameState.set_active_flux_module(&"burst_beam")
	_check(not GameState.flux_enabled, "module switch never leaves old module enabled")
	_check(GameState.set_active_flux_module(&"echo_scan"), "Q-cycled module remains selectable")
	GameState.set_active_flux_module(&"flux_shield")
	GameState.refill_flux()
	GameState.set_flux_enabled(true)
	await get_tree().physics_frame
	await get_tree().process_frame
	_check(
		_player.get_node_or_null("FluxShieldAura") != null,
		"Shield aura appears while Flux is active"
	)
	_player.reset_for_spawn(_player.global_position)
	await get_tree().physics_frame
	await get_tree().process_frame
	_check(_player.get_node_or_null("FluxShieldAura") == null, "reset removes Shield aura")
	GameState.set_active_flux_module(&"flux_shield")
	GameState.set_flux_enabled(true)
	GameState.spend_flux(GameState.flux_current)
	_player.take_damage(GameState.health)
	await get_tree().physics_frame
	await get_tree().process_frame
	_check(not GameState.flux_enabled, "death disables Flux")
	_check(_player.get_node_or_null("FluxShieldAura") == null, "death removes Shield aura")
	_player.reset_for_spawn(_player.global_position)


func _test_burst() -> void:
	GameState.reset_progress()
	GameState.unlock_ability(&"burst_beam")
	GameState.set_active_flux_module(&"burst_beam")
	GameState.set_flux_enabled(true)
	Weapons.reset_runtime()
	Input.action_press("fire_beam")
	_player._handle_weapon_input(1.0 / 60.0)
	var shots := get_tree().get_nodes_in_group(&"transient")
	_check(not shots.is_empty(), "Burst spawns dedicated projectile")
	var burst_shot: Node = shots.back()
	var successful_shots := shots.size()
	_check(burst_shot.get("damage_kind") == &"beam", "Burst projectile damage kind is beam")
	_check(
		burst_shot.get("damage_amount") == Catalog.BURST_BEAM_DAMAGE, "Burst damage is catalogued"
	)
	Input.action_release("fire_beam")
	var charge := GameState.flux_current
	for _frame in 60:
		Weapons._physics_process(1.0 / 60.0)
		Input.action_press("fire_beam")
		_player._handle_weapon_input(1.0 / 60.0)
	_check(
		get_tree().get_nodes_in_group(&"transient").size() > successful_shots,
		"Burst maintains successful cadence while held"
	)
	_check(charge - GameState.flux_current == 8, "Burst drains exactly 8 Flux per second")
	Input.action_release("fire_beam")
	var blocked := StaticBody2D.new()
	blocked.collision_layer = 1
	var blocked_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(32.0, 32.0)
	blocked_shape.shape = rectangle
	blocked.add_child(blocked_shape)
	add_child(blocked)
	blocked.global_position = _player.get_node("Muzzle").global_position
	await get_tree().physics_frame
	var blocked_charge := GameState.flux_current
	Input.action_press("fire_beam")
	_player._handle_weapon_input(1.0)
	Input.action_release("fire_beam")
	_check(GameState.flux_current == blocked_charge, "blocked muzzle does not drain Burst")
	blocked.queue_free()
	await get_tree().process_frame


func _test_echo_scan() -> void:
	GameState.reset_progress()
	GameState.unlock_ability(&"echo_scan")
	GameState.set_active_flux_module(&"echo_scan")
	var target := Node2D.new()
	target.add_to_group(&"dev_pickup")
	target.global_position = _player.global_position + Vector2(100.0, 0.0)
	add_child(target)
	GameState.set_active_flux_module(&"echo_scan")
	Input.action_press("activate_flux")
	_player._handle_weapon_input()
	Input.action_release("activate_flux")
	_check(
		GameState.flux_current == Catalog.FLUX_BASE_MAX - Catalog.ECHO_SCAN_COST,
		"Echo costs exact 20"
	)
	_check(get_tree().get_nodes_in_group(&"flux_echo_scan").size() == 1, "one Echo pulse runs")
	_check(target.get_child_count() == 1, "nearby gameplay target gets transient marker")
	Input.action_press("activate_flux")
	_player._handle_weapon_input()
	Input.action_release("activate_flux")
	_check(
		GameState.flux_current == Catalog.FLUX_BASE_MAX - Catalog.ECHO_SCAN_COST,
		"Echo cannot repeat while active"
	)
	await get_tree().create_timer(1.7).timeout
	_check(get_tree().get_nodes_in_group(&"flux_echo_scan").is_empty(), "Echo pulse cleans up")
	_check(target.get_child_count() == 0, "Echo marker restores target by cleanup")
	target.queue_free()


func _test_refill_and_catalog_state() -> void:
	GameState.reset_progress()
	GameState.unlock_ability(&"flux_shield")
	GameState.spend_flux(50)
	var ids_before := GameState.collected_pickup_ids.size()
	_check(
		GameState.collect_pickup("", &"flux_refill"), "Flux refill collects without persistent ID"
	)
	_check(GameState.flux_current == 60, "Flux refill adds exact ten")
	_check(GameState.collected_pickup_ids.size() == ids_before, "Flux refill is nonpersistent")
	_check(
		not GameState.collect_pickup("", &"flux_refill") or GameState.flux_current == 70,
		"repeat refill remains consumable"
	)


func _test_hud_and_panel() -> void:
	var hud := HUD_SCENE.instantiate()
	add_child(hud)
	await get_tree().process_frame
	var hud_text := _tree_text(hud)
	_check(hud_text.contains("Z             Slipstream"), "pause help assigns Slipstream to Z")
	_check(hud_text.contains("A / SPACE     Jump"), "pause help assigns jump to A and Space")
	_check(hud_text.contains("Q             Cycle Flux module"), "pause help shows Q Flux select")
	_check(
		hud_text.contains("F             Activate / toggle Flux"),
		"pause help shows F Flux activate"
	)
	_check_echo_help(hud_text, "pause help")
	_check(
		not hud_text.contains("A             Slipstream"), "pause help removes stale A Slipstream"
	)
	var panel := DEV_PANEL_SCRIPT.new() as DevPanel
	add_child(panel)
	await get_tree().process_frame
	var panel_text := _tree_text(panel)
	_check(panel_text.contains("Flux Shield"), "dev panel exposes Flux abilities")
	_check(panel_text.contains("Flux Tanks"), "dev panel exposes Flux tanks")
	_check(panel_text.contains("Z Slipstream"), "dev panel assigns Slipstream to Z")
	_check(panel_text.contains("A/Space jump"), "dev panel assigns jump to A and Space")
	_check_echo_help(panel_text, "dev panel")
	_check(not panel_text.contains("A Slipstream"), "dev panel removes stale A Slipstream")
	hud.queue_free()
	panel.queue_free()
	await get_tree().process_frame


func _tree_text(node: Node) -> String:
	var text := ""
	if node is Label or node is Button or node is CheckButton:
		text += node.text
	for child in node.get_children():
		text += "\n" + _tree_text(child)
	return text


func _check_echo_help(help_text: String, surface: String) -> void:
	_check(help_text.contains("Echo Scan is one-shot"), surface + " identifies Echo as one-shot")
	_check(
		help_text.contains("F toggles Shield/Burst"),
		surface + " identifies Shield/Burst as toggles"
	)
	_check(
		help_text.contains("%d Flux" % Catalog.ECHO_SCAN_COST),
		surface + " derives the Echo Flux cost"
	)
	_check(
		help_text.contains("nearby enemies, bosses, pickups, gates, and stations"),
		surface + " describes Echo targets"
	)


func _action_has_key(action: StringName, keycode: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == keycode:
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
