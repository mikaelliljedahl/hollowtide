extends RefCounted
## Round 10 review cases of the playtest agent check (tools/check_playtest_agent.gd runs them in
## its scene). A mini-boss fight left behind never blocks a required objective, and a route with a
## required objective nothing can open ends as `route_blocked`, not `route_done`. A running
## takeoff from a hop whose first cell is its own start keeps its plan on the ground and jumps.
## Sealed heat is no hazard and an enemy shot in heat is credited to the shot, and an updraft bob
## of 78 px in one place is recorded as a stall.

const CampaignCheck = preload("res://tools/check_playtest_campaign.gd")
const Progress = preload("res://tools/playtest_progress.gd")
const Telemetry = preload("res://tools/playtest_telemetry.gd")
const Nav = preload("res://tools/playtest_nav.gd")
const Policy = preload("res://tools/playtest_policy.gd")
const Hazards = preload("res://tools/playtest_hazards.gd")
const HeatZone = preload("res://scripts/campaign/heat_zone.gd")
const ENEMY_PROJECTILE_SCENE: PackedScene = preload("res://scenes/combat/enemy_projectile.tscn")

var _host: Node
var _root: Node
var _player: Player
var _campaign: CampaignCheck


## `host` is the check scene: it owns `_check`, `_root` and `_player`.
func _init(host: Node) -> void:
	_host = host
	_root = host.get("_root")
	_player = host.get("_player")
	_campaign = CampaignCheck.new(host)


func run() -> void:
	_test_left_mini_does_not_block()
	_test_blocked_route_is_named()
	_test_running_takeoff_jumps()
	await _test_heat_is_not_the_hit()
	_test_bob_is_a_stall()
	_test_room_entries()
	_test_dodge_jump_is_offered()
	_test_entry_bounce_is_no_attempt()
	GameState.reset_progress()
	GameState.unlock_ability(&"beam")
	GameState.reset_health()


func _check(condition: bool, label: String) -> void:
	_host.call(&"_check", condition, label)


## r10-run1 and run2: the Tollwing (optional) timed out, and every later objective listed
## `mini:tollwing`, the required ones too; next_index found none ready and the run ended as
## `route_done` with 43 objectives open.
func _test_left_mini_does_not_block() -> void:
	var mini := CampaignCheck._objective(0, "mini", "tollwing", "mini:tollwing", [], [])
	mini["optional"] = true
	var reward := CampaignCheck._objective(1, "pickup", "check.reward", "", [], ["mini:tollwing"])
	reward["optional"] = true
	var route: RefCounted = (
		_campaign
		. _route(
			[
				mini,
				reward,
				CampaignCheck._objective(
					2, "pickup", "check.ice", "ice_beam", [], ["mini:tollwing"]
				),
				CampaignCheck._objective(3, "ending", "ending", "", ["ice_beam"], []),
			],
			[]
		)
	)
	GameState.reset_progress()
	_check(route.next_index(false, {}) == 0, "the mini-boss is played first")
	var next: int = route.next_index(false, {0: 1})
	_check(next == 2, "a left mini-boss does not block the required objective after it (%d)" % next)
	GameState.set_world_flag("mini:tollwing")
	_check(route.next_index(false, {}) == 1, "a won mini-boss leads to its reward")


## A required objective whose kit can no longer be had: the run says it is blocked.
func _test_blocked_route_is_named() -> void:
	var route: RefCounted = (
		_campaign
		. _route(
			[
				CampaignCheck._objective(0, "pickup", "check.ice", "ice_beam", ["high_jump"], []),
				CampaignCheck._objective(1, "ending", "ending", "", ["ice_beam"], []),
			],
			[]
		)
	)
	GameState.reset_progress()
	var reason := Progress.new().update(0.0, route, Telemetry.new(), -1, false)
	_check(
		reason == "route_blocked", "a required objective never ready blocks the run (%s)" % reason
	)


## r10 kiln_06 (17, 7): the hop's first cell was its start, rising, so the ground frame passed it
## (progress 1) and every refresh took her for back on the start after a fall and restarted the
## hop: the running takeoff's edge frames began again each frame and jump was never pressed.
func _test_running_takeoff_jumps() -> void:
	var where := Nav.Navigator.locate(_root, _player)
	var room := String(where["room"])
	var cell: Vector2i = where["cell"]
	var hop := [
		[room, cell.x, cell.y, 0, 1],
		[room, cell.x + 1, cell.y, 0, 1],
		[room, cell.x + 1, cell.y - 1, 0, 1],
		[room, cell.x + 2, cell.y - 2, 0, 0],
	]
	var route: RefCounted = _campaign._route(
		[CampaignCheck._objective(0, "pickup", "check.none", "", [], [])],
		[{"%s:%d:%d:0" % [room, cell.x, cell.y]: [4, hop]}]
	)
	var nav := Nav.Navigator.new(route)
	var jumped := false
	for _frame in Nav.EDGE_FRAMES + 8:
		nav.refresh(where, 0)
		jumped = jumped or nav.control(where, _player).has(&"jump")
	_check(
		where["grounded"] and jumped,
		"a running takeoff from its own start cell jumps after its run-up (%s)" % [where["cell"]]
	)


func _frames(count: int) -> void:
	for _index in count:
		await _host.get_tree().physics_frame


## r10 kiln_08: the Emberkite arena lies inside Heat01, and with the Pressure Seal owned 26 of 27
## boss hits were credited to "hazard:heat" (the death's killer too), and the agent avoided the
## harmless heat. Sealed heat is no hazard; a shot in heat is the shot's; heat's own tick is heat.
func _test_heat_is_not_the_hit() -> void:
	GameState.reset_progress()
	GameState.unlock_ability(&"beam")
	GameState.unlock_ability(&"pressure_seal")
	GameState.reset_health()
	var zone := HeatZone.new()
	zone.zone_size = Vector2(1024, 512)
	_root.current_room.add_child(zone)
	zone.global_position = _player.global_position + Vector2(0, -200)
	var telemetry := Telemetry.new()
	telemetry.attach(_root, _player, [])
	await _frames(90)
	var body := Hazards.body_rect(_player)
	var kinds: Array = Hazards.near(_host.get_tree(), body, 0.0, true).map(
		func(h: Dictionary) -> String: return h["kind"]
	)
	_check(not kinds.has("heat"), "sealed heat is no hazard (%s)" % [kinds])
	await _shoot()
	_check(
		telemetry.hits.size() == 1 and telemetry.hits[-1]["source"] == "shot:orb",
		"a shot in sealed heat is the shot's (%s)" % [telemetry.hits]
	)
	GameState.reset_progress()
	GameState.unlock_ability(&"beam")
	await _frames(90)
	var seen := telemetry.hits.size()
	await _shoot()
	var shot: Array = telemetry.hits.slice(seen).filter(
		func(h: Dictionary) -> bool: return int(h["amount"]) != 4
	)
	_check(
		not shot.is_empty() and shot[0]["source"] == "shot:orb",
		"a shot in live heat is the shot's (%s)" % [telemetry.hits.slice(seen)]
	)
	var ticks: Array = telemetry.hits.filter(func(h: Dictionary) -> bool: return h["amount"] == 4)
	_check(
		not ticks.is_empty() and ticks.all(func(h): return h["source"] == "hazard:heat"),
		"heat's own drain is the heat's (%s)" % [ticks]
	)
	telemetry.detach()
	zone.queue_free()
	GameState.reset_progress()
	GameState.unlock_ability(&"beam")
	GameState.reset_health()
	await _frames(90)


## A shot at her chest from 90 px, then 30 frames for it to land.
func _shoot() -> void:
	var shot := ENEMY_PROJECTILE_SCENE.instantiate() as EnemyProjectile
	_root.add_child(shot)
	shot.global_position = _player.global_position + Vector2(90.0, -80.0)
	shot.launch(Vector2.LEFT, 12)
	await _frames(30)
	if is_instance_valid(shot):
		shot.queue_free()


## r10-run3: an updraft bobbed her 78 px up and down at the nexus_07 lip for 580 s with the route
## program running, and the 48 px spread test recorded no stall. A steady walk records none.
func _test_bob_is_a_stall() -> void:
	var home := _player.global_position
	var bob := Telemetry.new()
	bob.attach(_root, _player, [])
	for frame in 600:
		var phase := absf(fmod(frame / 40.0, 2.0) - 1.0)
		_player.global_position = Vector2(6.5 * 64.0, 400.0 + 78.0 * phase)
		bob.tick(1.0 / 60.0, true, "go_to_objective")
	bob.detach()
	var longest := 0.0
	for episode in bob.stuck_episodes:
		longest = maxf(longest, float(episode["seconds"]))
	_check(longest >= 3.0, "a 78 px bob in one place is a stall (%s)" % [bob.stuck_episodes])
	var walk := Telemetry.new()
	walk.attach(_root, _player, [])
	for frame in 300:
		_player.global_position = Vector2(2.5 * 64.0 + frame * 380.0 / 60.0 * 0.25, 480.0)
		walk.tick(1.0 / 60.0, true, "go_to_objective")
	walk.detach()
	_check(walk.stuck_episodes.is_empty(), "a walk is none (%s)" % [walk.stuck_episodes])
	_player.global_position = home


## r10 kiln_02: rooms_visited kept first entries only, so the critic read seven stays (four walks
## back from a respawn) as one 49.5 s visit. Every entry is kept, a respawn's marked.
func _test_room_entries() -> void:
	var route: RefCounted = _campaign._route(
		[CampaignCheck._objective(0, "pickup", "check.none", "", [], [])], []
	)
	GameState.reset_progress()
	var telemetry := Telemetry.new()
	var progress := Progress.new()
	for step in [["kiln_02", 0.0], ["kiln_03", 25.0], ["kiln_02", 101.0], ["kiln_03", 105.0]]:
		if step[1] == 101.0:
			telemetry.deaths.append({"t": 99.0, "room": "kiln_03"})
		telemetry.room = step[0]
		progress.update(step[1], route, telemetry, -1, false)
	var causes: Array = progress.room_entries.map(
		func(e: Dictionary) -> String: return "%s:%s" % [e["room"], e["cause"]]
	)
	_check(
		causes == ["kiln_02:move", "kiln_03:move", "kiln_02:respawn", "kiln_03:move"],
		"every room entry is kept, a respawn's marked (%s)" % [causes]
	)


## r10-run2 kiln_03: a fire shot at rel (197, -41) with her against the right wall, where only
## `jump:left` was offered; the heuristic named `jump:right`, the loop flagged an unknown key and
## played idle through a Heat Ring.
func _test_dodge_jump_is_offered() -> void:
	var state := CampaignCheck._plain_state({"kind": "boss", "gate_ahead": null}, [])
	state["projectiles"] = [{"rel": [197, -41], "vel": [-320, 0], "style": "fire"}]
	var offered := [
		{"key": "idle", "kind": "idle", "label": ""},
		{"key": "jump:left", "kind": "jump", "label": ""},
		{"key": "go_to_objective", "kind": "go_to_objective", "label": ""},
	]
	var policy := Policy.new(1)
	var pick := policy.heuristic(state, offered, false)
	_check(pick == "jump:left", "the shot dodge names an offered jump (%s)" % pick)
	var keys := offered.map(func(e: Dictionary) -> String: return e["key"])
	var stuck := [policy.heuristic(state, offered, true), policy.heuristic(state, offered, true)]
	_check(
		stuck.all(func(k: String) -> bool: return keys.has(k)),
		"a stuck jump names an offered key (%s)" % [stuck]
	)


## r10: riding the steam in and out of kiln_08's floor opening logged 0.7 s Emberkite attempts
## with no attack and no damage; such a pass is no attempt. A real short fight still is.
func _test_entry_bounce_is_no_attempt() -> void:
	var telemetry := Telemetry.new()
	var fight := {
		"id": "emberkite",
		"room": "kiln_08",
		"start": 0.0,
		"stage": 1,
		"stage_start": 0.0,
		"stage_seconds": {},
		"attacks": {},
		"attacks_landed": {},
		"attack_landed": false,
		"damage_by_source": {},
		"node": null,
	}
	telemetry.set("_boss", fight.duplicate(true))
	telemetry.now = 0.7
	telemetry.call("_finish_boss", "left_room")
	_check(telemetry.bosses.is_empty(), "a 0.7 s pass through the arena is no attempt")
	fight["attacks"] = {"flare_dive": 1}
	telemetry.set("_boss", fight.duplicate(true))
	telemetry.call("_finish_boss", "left_room")
	_check(telemetry.bosses.size() == 1, "a short fight with an attack is one")
