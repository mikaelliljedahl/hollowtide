extends RefCounted
## Playtest agent decision loop (docs/features/playtest-agent.md): export state, offer candidates,
## ask the policy, play the chosen program through input events, record telemetry. Shared by the
## launch scene (tools/playtest_agent.gd) and the check (tools/check_playtest_agent.gd).
## `root` needs `current_room`, `current_room_id` and optionally `room_changed`, like CampaignRoot.

const State = preload("res://tools/playtest_state.gd")
const Actions = preload("res://tools/playtest_actions.gd")
const Programs = preload("res://tools/playtest_programs.gd")
const Policy = preload("res://tools/playtest_policy.gd")
const Bridge = preload("res://tools/playtest_bridge.gd")
const Telemetry = preload("res://tools/playtest_telemetry.gd")
const LOGGED_FALLBACKS := 5

var policy_name := Policy.HEURISTIC
var timeout_ms := 1000
var telemetry: Telemetry = Telemetry.new()
var exporter: State = State.new()
var driver := Programs.Driver.new()
var bridge: Bridge
var tick := 0
## The candidate being played ({key, kind, label, program}).
var current: Dictionary = {}
## One JSON line per decision: tick, time, state, candidates, choice, policy, latency, fallback.
var decision_log: Array[String] = []
var _policy: Policy
var _root: Node
var _player: Player
var _fallbacks_logged := 0


func _init(root: Node, player: Player, policy: String, seed_value: int, break_specs: Array) -> void:
	_root = root
	_player = player
	policy_name = policy
	_policy = Policy.new(seed_value)
	telemetry.attach(root, player, break_specs)


## Opens the external policy connection; on failure every decision falls back to the heuristic.
func connect_external(port: int, hello: Dictionary) -> bool:
	bridge = Bridge.new()
	if bridge.connect_to(port, hello):
		return true
	print("playtest: external policy on port %d unavailable (%s)" % [port, bridge.error])
	return false


## Call once per physics frame, before the player processes.
func physics_step(delta: float) -> void:
	if _busy():
		if not driver.held().is_empty():
			driver.release_all()
		current = {}
		telemetry.tick(delta, false, "")
		return
	if driver.done():
		_decide()
	driver.step()
	var kind := String(current.get("kind", ""))
	telemetry.tick(delta, kind in Actions.MOVING_KINDS, kind)


func finish(summary: Dictionary) -> void:
	driver.release_all()
	telemetry.detach()
	if bridge != null:
		bridge.close(summary)


func _busy() -> bool:
	return (
		GameState.health <= 0
		or _root.get("_busy") == true
		or _root.get("_respawning") == true
		or _player.get_tree().paused
	)


func _decide() -> void:
	tick += 1
	var state := exporter.snapshot(_root, _player, tick, telemetry.now)
	var options := Actions.candidates(state, _player)
	var offered := Actions.public(options)
	var stuck := telemetry.is_stuck()
	var started := Time.get_ticks_usec()
	var key := ""
	var fallback := ""
	match policy_name:
		Policy.RANDOM:
			key = _policy.random_choice(offered)
		Policy.EXTERNAL:
			var hint := _policy.heuristic(state, offered, stuck)
			if bridge == null or not bridge.connected:
				fallback = "not_connected"
			else:
				key = bridge.decide(tick, state, offered, hint, timeout_ms)
				fallback = bridge.error
			if fallback.is_empty() and Actions.find(options, key).is_empty():
				fallback = "unknown_key"
			if not fallback.is_empty():
				key = hint
				_log_fallback(fallback)
		_:
			key = _policy.heuristic(state, offered, stuck)
	var latency := Time.get_ticks_usec() - started
	current = Actions.find(options, key)
	if current.is_empty():
		current = options[0]
	driver.start(current["program"])
	telemetry.record_decision(policy_name, latency, fallback, current["kind"])
	(
		decision_log
		. append(
			(
				JSON
				. stringify(
					{
						"tick": tick,
						"t": state["t"],
						"policy": policy_name,
						"key": current["key"],
						"fallback": fallback,
						"latency_ms": snappedf(latency / 1000.0, 0.01),
						"state": state,
						"candidates": offered,
					}
				)
			)
		)
	)


func _log_fallback(reason: String) -> void:
	if _fallbacks_logged >= LOGGED_FALLBACKS:
		return
	_fallbacks_logged += 1
	print("playtest: external policy %s at tick %d; used the heuristic" % [reason, tick])
