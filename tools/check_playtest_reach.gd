extends RefCounted
## Reach cases of the playtest agent check (tools/check_playtest_agent.gd runs them in its scene):
## the refill run, a pickup and a room-mode exit are straight steers, so none is offered at a goal
## behind a wall no jump clears, out of a jump's reach from the floor under her or across a deep
## gap, and each is offered beyond a block a jump clears or on her side of the wall. min-jev-c
## wall-jumped in the vaults_02 shaft toward a shrine behind its east wall for 450 s, and a room
## probe there steered 161 of 161 decisions at the energy tank behind the same wall.

const Actions = preload("res://tools/playtest_actions.gd")
const State = preload("res://tools/playtest_state.gd")
const ROOM_ID := "campaign_check"
## A floor with a three-tile block a jump clears.
const BLOCK_GRID := [
	"##############################",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"#...........#####............#",
	"#...........#####............#",
	"#...........#####............#",
	"##############################",
]
## A wall from floor to ceiling, higher than any jump.
const WALL_GRID := [
	"####################",
	"#.........#........#",
	"#.........#........#",
	"#.........#........#",
	"#.........#........#",
	"#.........#........#",
	"####################",
]
## An upper floor with a three-tile gap over a deep hall.
const GAP_GRID := [
	"####################",
	"#..................#",
	"#..................#",
	"#..................#",
	"#..................#",
	"#..................#",
	"######...###########",
	"#..................#",
	"#..................#",
	"#..................#",
	"#..................#",
	"#..................#",
	"####################",
]
## The steers under test: the candidate key each offers for a goal.
const KINDS := ["go_to_refill:save", "pick_up:check.tank", "go_to_exit:east:elsewhere"]

var _host: Node
var _root: Node
var _player: Player


## `host` is the check scene: it owns `_check`, `_root` and `_player`.
func _init(host: Node) -> void:
	_host = host
	_root = host.get("_root")
	_player = host.get("_player")


func run() -> void:
	var old_room: Node = _root.get("current_room")
	var old_id := String(_root.get("current_room_id"))
	var old_feet := _player.global_position
	_root.remove_child(old_room)
	_root.set("current_room_id", ROOM_ID)
	var block := await _build(BLOCK_GRID)
	for key in KINDS:
		_check(_offered(block, key, Vector2i(20, 8), Vector2i(4, 8)), "%s beyond a block" % key)
	await _free(block)
	var walled := await _build(WALL_GRID)
	for key in KINDS:
		_check(_offered(walled, key, Vector2i(8, 5)), "%s on this side of the wall" % key)
		_check(
			not _offered(walled, key, Vector2i(15, 5)),
			"no %s behind a wall no jump clears (vaults_02 shaft)" % key
		)
	await _free(walled)
	var gap := await _build(GAP_GRID)
	for key in KINDS:
		_check(
			not _offered(gap, key, Vector2i(14, 5), Vector2i(2, 5)),
			"no %s across a gap she would fall into (vaults_02 upper floor)" % key
		)
		_check(
			not _offered(gap, key, Vector2i(3, 5), Vector2i(7, 5)),
			"no %s level with her in the air, 384 px above the floor (vaults_02 shaft)" % key
		)
	await _free(gap)
	_root.add_child(old_room)
	_root.set("current_room", old_room)
	_root.set("current_room_id", old_id)
	_player.reset_for_spawn(old_feet)
	GameState.reset_progress()
	GameState.unlock_ability(&"beam")
	GameState.reset_health()
	await _frames(10)


func _check(condition: bool, label: String) -> void:
	_host.call(&"_check", condition, label)


func _frames(count: int) -> void:
	for _index in count:
		await _host.get_tree().physics_frame


func _build(grid: Array) -> CampaignRoom:
	var room := WorldFxTestbed.build_room(_root, &"fringe", grid, ROOM_ID)
	_root.set("current_room", room)
	await _frames(2)
	return room


func _free(room: CampaignRoom) -> void:
	room.queue_free()
	await _frames(2)


## Whether a player with 12 health, no Harpoons and her feet in `from` is offered `key` for a goal
## at `cell`: only that goal is in the state (a health refill, an energy tank or an open door).
func _offered(room: CampaignRoom, key: String, cell: Vector2i, from := Vector2i(4, 5)) -> bool:
	GameState.reset_progress()
	GameState.unlock_ability(&"beam")
	_player.reset_for_spawn(WorldFxTestbed.feet(room, from))
	var state := State.new().snapshot(_root, _player, 1, 0.0)
	state["player"]["health"] = 12
	var rel := WorldFxTestbed.feet(room, cell) - _player.global_position
	var goal := [rel.x, rel.y]
	state["refills"] = []
	state["pickups"] = []
	state["exits"] = []
	if key.begins_with("go_to_refill"):
		state["refills"] = [{"kind": "save", "restores": ["health"], "rel": goal}]
	elif key.begins_with("pick_up"):
		state["pickups"] = [{"id": "check.tank", "kind": "energy_tank", "rel": goal}]
	else:
		state["exits"] = [{"id": "east:elsewhere", "rel": goal, "gated": false, "gate": ""}]
	return Actions.candidates(state, _player).any(
		func(entry: Dictionary) -> bool: return entry["key"] == key
	)
