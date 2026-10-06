extends RefCounted
## Round 10 review cases of the playtest agent check (tools/check_playtest_agent.gd runs them in
## its scene). A mini-boss fight left behind never blocks a required objective, and a route with a
## required objective nothing can open ends as `route_blocked`, not `route_done`. A running
## takeoff from a hop whose first cell is its own start keeps its plan on the ground and jumps.

const CampaignCheck = preload("res://tools/check_playtest_campaign.gd")
const Progress = preload("res://tools/playtest_progress.gd")
const Telemetry = preload("res://tools/playtest_telemetry.gd")
const Nav = preload("res://tools/playtest_nav.gd")

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
