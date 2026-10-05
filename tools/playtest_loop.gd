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
const Campaign = preload("res://tools/playtest_campaign.gd")
const Dodge = preload("res://tools/playtest_dodge.gd")
const LOGGED_FALLBACKS := 5
## A streamed decision log is flushed this often, so a long run can be followed from outside.
const LOG_FLUSH_EVERY := 200

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
## Kept in memory unless `open_log` streams them to a file (campaign runs are long).
var decision_log: Array[String] = []
## Campaign mode (tools/playtest_campaign.gd): adds the goal and the route candidates; null otherwise.
var campaign: Campaign
var _log_file: FileAccess
var _policy: Policy
var _root: Node
var _player: Player
var _fallbacks_logged := 0
## The boss attack plan seen when the running program was chosen. A new telegraph ends the program
## so the answer to it starts at once: in r6-min-s1b 5 of 20 Ember Fan hits came in stage 4 while
## a Vent Burst dodge still waited out its pillars, and 5 more while a retreat ran on past the
## point the fan was aimed at.
var _seen_plan: Variant = null
## Whether the boss could be hurt when the running program was chosen. An opening ends a program
## that keeps her standing in place, so the Harpoon is offered at once: in r6-full-s4 a
## stand-still Crosscurrent dodge ran on through a 2 s Tidal Heart Echo window.
var _seen_open := false


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
		# Through a room change the held inputs stay held and the program waits: the fade-in
		# runs the player with a north door's entry boost, and a released jump cuts it (the PR 12
		# review and round 10 smoke runs fell back out of nexus_01 into nexus_07 for 225 s and
		# 860 s). A respawn or death still lets go of everything.
		if not _changing_room():
			if not driver.held().is_empty():
				driver.release_all()
			current = {}
		telemetry.tick(delta, false, "")
		return
	if driver.done() or _new_telegraph() or _new_opening():
		_decide()
	driver.step()
	var kind := String(current.get("kind", ""))
	telemetry.tick(delta, kind in Actions.MOVING_KINDS, kind)


func finish(summary: Dictionary) -> void:
	driver.release_all()
	telemetry.detach()
	if bridge != null:
		bridge.close(summary)
	if _log_file != null:
		_log_file.close()
		_log_file = null


## Streams decision lines to `path` instead of keeping them; returns false when it cannot open it.
func open_log(path: String) -> bool:
	_log_file = FileAccess.open(path, FileAccess.WRITE)
	return _log_file != null


func streaming() -> bool:
	return _log_file != null


func _busy() -> bool:
	return (
		GameState.health <= 0
		or _root.get("_busy") == true
		or _root.get("_respawning") == true
		or _player.get_tree().paused
	)


## True during a room change (not a respawn, not dead) while the running program holds inputs.
func _changing_room() -> bool:
	return (
		_root.get("_busy") == true
		and _root.get("_respawning") != true
		and GameState.health > 0
		and not driver.held().is_empty()
	)


func _decide() -> void:
	tick += 1
	var state := exporter.snapshot(_root, _player, tick, telemetry.now)
	var route: Array = []
	if campaign != null:
		state["goal"] = campaign.goal(state)
		_mark_platforms(state)
		route = campaign.candidates(state)
	var options := Actions.candidates(state, _player, route)
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
	_seen_plan = _boss_plan()
	_seen_open = _boss_open()
	if _player.is_ball and current["kind"] in Programs.STANDING_KINDS:
		driver.start(Programs.StandFirst.new(current["program"]))
	else:
		driver.start(current["program"])
	telemetry.record_decision(policy_name, latency, fallback, current["kind"])
	var line := (
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
	if _log_file != null:
		_log_file.store_line(line)
		if tick % LOG_FLUSH_EVERY == 0:
			_log_file.flush()
	else:
		decision_log.append(line)


func _boss_plan() -> Variant:
	var boss := _player.get_tree().get_first_node_in_group(&"bosses")
	return boss.get("_attack_plan") if boss != null else null


func _new_telegraph() -> bool:
	var boss := _player.get_tree().get_first_node_in_group(&"bosses")
	return (
		boss != null
		and boss.get("_attack_state") == &"telegraph"
		and not is_same(boss.get("_attack_plan"), _seen_plan)
	)


func _boss_open() -> bool:
	var boss := _player.get_tree().get_first_node_in_group(&"bosses")
	return (
		boss != null and boss.get("_branch_open") == true and int(boss.get("_opening_damage")) > 0
	)


func _new_opening() -> bool:
	if _seen_open or not _boss_open():
		return false
	# A move in progress (a jump over the boss, a curl under a line) is left to finish.
	return current.get("kind") == "idle" or Dodge.stays_put(current)


func _log_fallback(reason: String) -> void:
	if _fallbacks_logged >= LOGGED_FALLBACKS:
		return
	_fallbacks_logged += 1
	print("playtest: external policy %s at tick %d; used the heuristic" % [reason, tick])


## A frost floater the route stands on is a platform, not a target, frozen or not: r6-min-s1 froze
## the vaults_02 floaters, then Jev switched to the seed bolt and shot all four down.
func _mark_platforms(state: Dictionary) -> void:
	var ids := {}
	for floater in campaign.platforms():
		ids[exporter.label_for(floater)] = true
	for enemy in state["enemies"]:
		if ids.has(enemy["id"]):
			enemy["platform"] = true
