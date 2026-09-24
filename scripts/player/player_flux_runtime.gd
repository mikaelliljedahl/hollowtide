class_name PlayerFluxRuntime
extends RefCounted

const Catalog = preload("res://scripts/progression/content_catalog.gd")
const FLUX_AURA_SCENE: PackedScene = preload("res://scenes/effects/flux/flux_shield_aura.tscn")
const ECHO_SCAN_SCENE: PackedScene = preload("res://scenes/effects/flux/echo_scan_pulse.tscn")

var _host: Node2D
var _play_sfx: Callable
var _flux_aura: Node2D
var _burst_drain_accumulator: float = 0.0
var _flux_empty_cue_played: bool = false
var _cycle_action_latched: bool = false
var _activate_action_latched: bool = false


func _init(host: Node2D, play_sfx: Callable) -> void:
	_host = host
	_play_sfx = play_sfx


func handle_input() -> void:
	var cycle_pressed := Input.is_action_pressed("cycle_flux")
	if cycle_pressed and not _cycle_action_latched:
		cycle_module()
	_cycle_action_latched = cycle_pressed
	var activate_pressed := Input.is_action_pressed("activate_flux")
	var activate_edge := activate_pressed and not _activate_action_latched
	_activate_action_latched = activate_pressed
	if not activate_edge:
		return
	if GameState.active_flux_module == &"echo_scan":
		GameState.set_flux_enabled(false)
		spawn_echo_scan()
		return
	if not GameState.has_ability(GameState.active_flux_module):
		return
	var enabling := not GameState.flux_enabled
	if not GameState.set_flux_enabled(enabling):
		return
	_flux_empty_cue_played = false
	if enabling:
		var cue := (
			&"flux_burst" if GameState.active_flux_module == &"burst_beam" else &"flux_shield"
		)
		_play_optional_sfx(cue)


func cycle_module() -> void:
	var owned: Array[StringName] = []
	for module in Catalog.FLUX_ABILITY_IDS:
		if GameState.has_ability(module):
			owned.append(module)
	if owned.is_empty():
		return
	var index := owned.find(GameState.active_flux_module)
	GameState.set_active_flux_module(owned[(index + 1) % owned.size()])


func shield_active() -> bool:
	return (
		GameState.active_flux_module == &"flux_shield"
		and GameState.flux_enabled
		and GameState.has_ability(&"flux_shield")
		and GameState.flux_current > 0
	)


func absorb_damage(amount: int) -> int:
	if not shield_active():
		return amount
	var absorbed := mini(amount, GameState.flux_current)
	if absorbed <= 0:
		return amount
	var was_enabled := GameState.flux_enabled
	GameState.spend_flux(absorbed)
	_play_optional_sfx(&"flux_shield")
	if was_enabled and GameState.flux_current == 0:
		on_flux_empty()
	return amount - absorbed


func burst_active() -> bool:
	return (
		GameState.active_flux_module == &"burst_beam"
		and GameState.flux_enabled
		and GameState.has_ability(&"burst_beam")
	)


func drain_burst_flux(delta: float) -> void:
	_burst_drain_accumulator += Catalog.BURST_BEAM_DRAIN_PER_SECOND * delta
	var spend := mini(floori(_burst_drain_accumulator), GameState.flux_current)
	if spend <= 0:
		return
	_burst_drain_accumulator -= spend
	var was_enabled := GameState.flux_enabled
	GameState.spend_flux(spend)
	if was_enabled and GameState.flux_current == 0:
		on_flux_empty()


func reset_burst_drain() -> void:
	_burst_drain_accumulator = 0.0


func on_flux_empty() -> void:
	reset_burst_drain()
	if not _flux_empty_cue_played:
		_flux_empty_cue_played = true
		_play_optional_sfx(&"flux_empty")
	sync_aura(false)


func spawn_echo_scan() -> void:
	if not GameState.has_ability(&"echo_scan") or GameState.flux_current < Catalog.ECHO_SCAN_COST:
		return
	if not _host.get_tree().get_nodes_in_group(&"flux_echo_scan").is_empty():
		return
	var pulse := ECHO_SCAN_SCENE.instantiate() as Node2D
	if pulse == null or not GameState.spend_flux(Catalog.ECHO_SCAN_COST):
		return
	pulse.global_position = _host.global_position + Vector2(0.0, -88.0)
	var parent := (
		_host.get_tree().current_scene
		if _host.get_tree().current_scene != null
		else _host.get_tree().root
	)
	parent.add_child(pulse)
	_play_optional_sfx(&"echo_scan")


func sync_aura(can_display: bool) -> void:
	var active := can_display and shield_active()
	if active and not is_instance_valid(_flux_aura):
		_flux_aura = FLUX_AURA_SCENE.instantiate() as Node2D
		if _flux_aura != null:
			_flux_aura.name = "FluxShieldAura"
			_host.add_child(_flux_aura)
			_flux_aura.position = Vector2.ZERO
	elif not active and is_instance_valid(_flux_aura):
		_flux_aura.queue_free()
		_flux_aura = null


func on_death() -> void:
	reset_burst_drain()
	if GameState.flux_enabled:
		GameState.set_flux_enabled(false)
	sync_aura(false)


func reset() -> void:
	reset_burst_drain()
	if GameState.flux_enabled:
		GameState.set_flux_enabled(false)
	_flux_empty_cue_played = false
	_cycle_action_latched = false
	_activate_action_latched = false
	sync_aura(false)


func cleanup() -> void:
	reset_burst_drain()
	if is_instance_valid(_flux_aura):
		_flux_aura.queue_free()
	_flux_aura = null


func _play_optional_sfx(id: StringName) -> void:
	if _play_sfx.is_valid():
		_play_sfx.call(id)
