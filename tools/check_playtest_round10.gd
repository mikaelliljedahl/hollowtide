extends RefCounted
## Round 10 review cases of the playtest agent check (tools/check_playtest_agent.gd runs them in
## its scene). A mini-boss fight left behind never blocks a required objective, and a route with a
## required objective nothing can open ends as `route_blocked`, not `route_done`.

const CampaignCheck = preload("res://tools/check_playtest_campaign.gd")
const Progress = preload("res://tools/playtest_progress.gd")
const Telemetry = preload("res://tools/playtest_telemetry.gd")

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
