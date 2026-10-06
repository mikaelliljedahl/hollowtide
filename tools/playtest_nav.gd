extends RefCounted
## Campaign-mode path following for the playtest agent (harness:
## docs/features/playtest-agent.md). `Navigator` keeps the hop being followed across decisions (a jump or a room change
## outlives one program) and turns it into held input actions each frame; `Follow` is the live
## program the Driver plays (tools/playtest_programs.gd). Hops come from the route's flow field
## (tools/playtest_route.gd): cells [room, x, y, ball, rising] from one resting spot to the next.
## Only input actions are pressed; nothing moves the player directly.

const Route = preload("res://tools/playtest_route.gd")
const TILE := 64.0
## Feet within this many px of a cell's centre stand in it (the body is 56 px wide).
const CENTER_PX := 10.0
## Steering dead zone while a grounded hop drops to a lower cell.
const DROP_PX := 1.0
## A frozen frost floater can hold her feet up to 34 px into the row below the solver's resting
## row (heur-r1 stood still at vaults_02 (28, 13) with her feet 34 px in, read off the route,
## until the floater thawed under her, five times). Feet on real ground sit 64 px into their row.
const FLOATER_SAG := 48.0
## Half the body's width: feet this close to a column edge can stand on the neighbour column.
const HALF_BODY := 28.0
## Wall jumps are pressed once the rise has slowed to this (px/s, negative is up).
const WALL_JUMP_SPEED := -250.0
## A shaft wall this close (px) to the body is pushed into to start a chimney climb.
const WALL_REACH := 40.0
## Frames a jump press may take to leave the ground (it goes out after the player's step).
const PRESS_GRACE := 3
## Frames after walking off an edge in which a jump still takes (coyote time is 0.1 s; the press
## lands a frame late).
const COYOTE_FRAMES := 4
## Rows one jump climbs (256 px); a ledge higher up is climbed to first, not drifted toward.
const JUMP_ROWS := 4
## Sideways probe (px) for an early drift toward a ledge while rising.
const DRIFT_PROBE := 24.0
## Frames spent walking to an edge before a jump is taken where the player stands.
const EDGE_FRAMES := 24
const SLIP_TAP_FRAMES := 2
const SLIP_COOLDOWN := 14
## Longest a Follow keeps flying a jump past its frame budget.
const AIR_FRAMES := 150
## Follow ends after this many frames without the feet moving 6 px.
const STALL_FRAMES := 30
## Hops looked at past the one being followed, for gates and floaters on the way.
const LOOKAHEAD_HOPS := 3
## Frames in the air without passing a hop cell, with none of its cells left in her room, after
## which the hop is given up: an updraft holding her at the hop's landing (r10: 140-580 s at the
## nexus_07 lip).
const STALE_AIR_FRAMES := 120


class Navigator:
	extends RefCounted

	var route: Route
	## Objective whose field is followed; the hop is dropped when it changes.
	var objective := -1
	var hop: Array = []
	var progress := 0
	## "on_field", "at_goal", "off_field" or "airborne" after the last refresh.
	var status := "off_field"
	var steps := -1
	var _jump_frames := 0
	var _jump_release := 0
	var _air_frames := 0
	var _edge_frames := 0
	## Frames airborne since the hop last advanced, and whether she left the ground on this hop.
	var _stale_air := 0
	var _stale_room := ""
	var _left_ground := false
	## Resting cell the hop starts from, and the side a running takeoff goes to (0: jump in place).
	## Side of the next chimney wall after a wall jump (0 outside a climb).
	var _climb_dir := 0
	var _from := Vector2i.ZERO
	var _takeoff := 0
	var _planned := false
	var _slip_tap := 0
	var _slip_cooldown := 0
	## Step to the resting cell's centre before a straight jump (see _takeoff_side).
	var _center := false

	func _init(planner: Route) -> void:
		route = planner

	## Where the player is: room id, room-local feet, feet cell, grounded, ball form; {} without a
	## room.
	static func locate(root: Node, player: Player) -> Dictionary:
		var room := root.get("current_room") as Node2D
		if room == null or player == null:
			return {}
		var local := player.global_position - room.global_position
		return {
			"room": String(root.get("current_room_id")),
			"room_node": room,
			"local": local,
			"cell": Vector2i(floori(local.x / TILE), floori((local.y - 1.0) / TILE)),
			"grounded": player.is_on_floor(),
			"ball": player.is_ball,
		}

	## Re-reads the flow field when the player rests; keeps the hop while she is in the air.
	func refresh(where: Dictionary, index: int) -> String:
		if index != objective:
			objective = index
			hop = []
			progress = 0
		if where.is_empty() or index < 0:
			status = "off_field"
			return status
		if not bool(where["grounded"]):
			# A hop with nothing left in her room that she has hung on to in the air for
			# STALE_AIR_FRAMES in this room steers nowhere: an updraft holds her (r10-run1 rode
			# the kiln_05 steam into kiln_10 on a kiln_05 hop and hovered 290 s with no input;
			# the nexus_07 lip held her 1 px off the floor 6 px from the hop's landing for 140 s).
			# A hop that still goes on in her room is kept however long the air takes, and so is
			# one she will fall back onto: the kiln_01 steam lifts her into nexus_03 and drops her
			# back, and steering her out there stranded her on the nexus_03 floor.
			if not hop.is_empty() and _stale_air > STALE_AIR_FRAMES and passed_in(where):
				drop_hop()
			_chain_in_updraft(where)
			status = "airborne" if not hop.is_empty() else "off_field"
			return status
		var found := rest_entry(where)
		if found.is_empty() and _on_hop(where):
			# Touching down for a frame on a cell the hop passes (the lip of a drop): keep going.
			status = "airborne"
			return status
		if found.is_empty():
			steps = -1
			status = "off_field"
			return status
		steps = int(found[0])
		if steps == 0:
			hop = []
			status = "at_goal"
			return status
		if found[1] != hop or (progress > 0 and _left_ground and found[2] == _from):
			# Standing on the hop's own start again (a jump that fell back down) starts it over:
			# its passed cells lie above her, and with the progress kept the next cell was the
			# next room's, so no jump was pressed (the PR 12 review run s1-full stood under the
			# nexus_07 shaft to nexus_01 for 225 s after its apex jump fell short). Only after
			# she left the ground: a hop whose first cell is its start passes it on the ground,
			# and restarting there every frame reset a running takeoff before its jump (kiln_06
			# (17, 7) in r10, never left the cell).
			hop = found[1]
			_from = found[2]
			progress = 0
			_planned = false
			_left_ground = false
			_stale_air = 0
		status = "on_field"
		return status

	## Lifted by an updraft with every cell of the hop passed, she takes the field's next hop from
	## its last cell, so she keeps walking the planned way through the current instead of holding
	## nothing. Round 12: on the kiln_06 row 5 platform the walk west lifted her off at (15, 4)
	## into the north steam, she held nothing, rose into kiln_08 and fell back, for good (cells
	## 13 to 16 never reached the west door in a probe).
	func _chain_in_updraft(where: Dictionary) -> void:
		if hop.is_empty() or progress < hop.size() or not _in_updraft(where):
			return
		var last: Array = hop[-1]
		if last[0] != where["room"]:
			return
		var next := route.entry(
			objective, String(last[0]), Vector2i(last[1], last[2]), bool(last[3])
		)
		if next.is_empty() or (next[1] as Array).is_empty():
			return
		hop = next[1]
		progress = 0
		_stale_air = 0

	static func _in_updraft(where: Dictionary) -> bool:
		var room_node: Node2D = where["room_node"]
		for node in room_node.get_tree().get_nodes_in_group(&"worldfx_current"):
			var current := node as PushCurrent
			if current != null and current.direction.y < -0.1 and current.player_inside():
				return true
		return false

	## Gives up the hop: the next refresh reads the field again, or reports her off it.
	func drop_hop() -> void:
		hop = []
		progress = 0
		_planned = false
		_left_ground = false
		_stale_air = 0

	## True when the hop has no cell left in her room past the ones she has passed.
	func passed_in(where: Dictionary) -> bool:
		for index in range(progress, hop.size()):
			if hop[index][0] == where["room"]:
				return false
		return true

	## True when the feet cell (or the row above it on a sagging floater) is one the hop being
	## followed still passes through.
	func _on_hop(where: Dictionary) -> bool:
		for cell in _rest_rows(where):
			for index in range(maxi(progress - 1, 0), hop.size()):
				var step: Array = hop[index]
				if (
					step[0] == where["room"]
					and int(step[1]) == cell.x
					and int(step[2]) == cell.y
					and bool(step[3]) == bool(where["ball"])
				):
					return true
		return false

	## The feet cell, then the row above it while the feet sit less than FLOATER_SAG into their
	## row: on a frozen floater caught below its home cell the feet sit just under the solver's row.
	static func _rest_rows(where: Dictionary) -> Array:
		var cell: Vector2i = where["cell"]
		if float(where["local"].y) - cell.y * TILE < FLOATER_SAG:
			return [cell, cell + Vector2i.UP]
		return [cell]

	## The field entry for the spot the player rests on, [steps, hop, cell]: her feet cell, else a
	## neighbour column her body overlaps (standing on a ledge's lip); [] when neither is known.
	## A sagging floater's row above counts as hers for both (t4-full-s1 walked to the lip of the
	## vaults_02 floater at (28, 13) for its running takeoff, read off the route and turned back,
	## for 450 s).
	func rest_entry(where: Dictionary) -> Array:
		var room := String(where["room"])
		var ball := bool(where["ball"])
		var rows := _rest_rows(where)
		for cell in rows:
			var found := route.entry(objective, room, cell, ball)
			if not found.is_empty():
				return [found[0], found[1], cell]
		var x := float(where["local"].x)
		var column: int = (where["cell"] as Vector2i).x
		var lean := -1 if x - column * TILE < (column + 1) * TILE - x else 1
		for cell in rows:
			for side in [lean, -lean]:
				var edge := column * TILE if side < 0 else (column + 1) * TILE
				if absf(x - edge) < HALF_BODY:
					var probe: Vector2i = cell + Vector2i(side, 0)
					var found := route.entry(objective, room, probe, ball)
					if not found.is_empty():
						return [found[0], found[1], probe]
		return []

	## Held actions for this frame along the hop.
	func control(where: Dictionary, player: Player) -> Array:
		var held: Array = []
		_slip_cooldown = maxi(_slip_cooldown - 1, 0)
		if hop.is_empty() or where.is_empty():
			_jump_frames = 0
			return held
		var room := String(where["room"])
		var cell: Vector2i = where["cell"]
		var ball := bool(where["ball"])
		_air_frames = 0 if bool(where["grounded"]) else _air_frames + 1
		var airborne := not bool(where["grounded"])
		_left_ground = _left_ground or airborne
		var passed := progress
		for index in range(progress, hop.size()):
			var step: Array = hop[index]
			# In the air, flying over a hop cell (a row higher than the solver's arc) passes it too;
			# otherwise the target stays behind her and pulls her back.
			if (
				step[0] == room
				and step[1] == cell.x
				and (step[2] == cell.y or (airborne and cell.y < int(step[2])))
				and bool(step[3]) == ball
			):
				progress = index + 1
		var same_room := room == _stale_room
		_stale_room = room
		_stale_air = _stale_air + 1 if airborne and progress == passed and same_room else 0
		var target: Array = hop[_target_index(room, cell, player, where["local"])]
		var aim_x := _aim_x(target, room, where)
		var dx := aim_x - float(where["local"].x)
		var rises := _rises(room, cell)
		var grounded := bool(where["grounded"])
		if grounded and not _planned:
			_planned = true
			_takeoff = _takeoff_side(room, player, float(where["local"].x))
			_edge_frames = 0
		var edge := false
		if grounded and _center and _jump_frames == 0:
			var off := (_from.x + 0.5) * TILE - float(where["local"].x)
			if absf(off) > CENTER_PX:
				dx = off
				# Held like a running takeoff's edge: no jump until she is centred.
				edge = true
			else:
				_center = false
		if _takeoff != 0:
			if grounded and _jump_frames == 0:
				# Run toward the takeoff side and jump off the edge (coyote time) with speed.
				_edge_frames += 1
				edge = _edge_frames <= EDGE_FRAMES
				dx = _takeoff * TILE
			elif not grounded:
				dx = _aim_x(_landing(room), room, where) - float(where["local"].x)
		# Climbing a chimney: after each wall jump keep going to the opposite wall and jump off it
		# again, as long as the hop still climbs; the column target alone would pull her back into
		# the middle and lose the height.
		if grounded or not rises:
			_climb_dir = 0
		elif _climb_dir != 0:
			dx = _climb_dir * TILE
		elif _wall_start(target, where, player):
			dx = _climb_dir * TILE
		# Standing on a ledge's lip above a drop in the next column, the feet can sit within
		# CENTER_PX of the target column and still be held up: step on until she falls.
		var drop: bool = grounded and target[0] == room and int(target[2]) > cell.y
		if absf(dx) > (DROP_PX if drop else CENTER_PX):
			held.append(&"move_right" if dx > 0.0 else &"move_left")
		_press_jump(held, where, player, rises, dx, edge)
		var want_ball := bool(target[3])
		if _slip_tap > 0:
			_slip_tap -= 1
			held.append(&"slipstream")
		elif want_ball != ball and _slip_cooldown == 0:
			if not want_ball or (bool(where["grounded"]) and player.velocity.y >= 0.0):
				_slip_tap = SLIP_TAP_FRAMES - 1
				_slip_cooldown = SLIP_COOLDOWN
				held.append(&"slipstream")
		return held

	## Starts a chimney climb: the jump is peaking below a target straight overhead, which only a
	## wall jump reaches, so she is steered into the nearer wall within WALL_REACH (the solver's
	## wall jump; standing centred in the shaft she never touches it). Sets `_climb_dir` to it.
	func _wall_start(target: Array, where: Dictionary, player: Player) -> bool:
		var cell: Vector2i = where["cell"]
		if (
			bool(where["grounded"])
			or target[0] != where["room"]
			or int(target[1]) != cell.x
			or int(target[2]) >= cell.y
			or player.velocity.y < WALL_JUMP_SPEED
		):
			return false
		var near := -1 if float(where["local"].x) < (cell.x + 0.5) * TILE else 1
		for side in [near, -near]:
			if player.test_move(player.global_transform, Vector2(side * WALL_REACH, 0.0)):
				_climb_dir = side
				return true
		return false

	## Closed ability gate on the next hops in this room, or null.
	func gate_ahead(where: Dictionary, tree: SceneTree) -> AbilityGate:
		if where.is_empty() or objective < 0:
			return null
		var room_node: Node2D = where["room_node"]
		var gates: Array = []
		for node in tree.get_nodes_in_group(&"ability_gates"):
			var gate := node as AbilityGate
			if gate == null or not room_node.is_ancestor_of(gate) or gate.collision_layer == 0:
				continue
			gates.append(gate)
		if gates.is_empty():
			return null
		for step in upcoming(where):
			var rows := [step[2]] if bool(step[3]) else [step[2], step[2] - 1, step[2] - 2]
			for row in rows:
				var center := (
					room_node.global_position + (Vector2(step[1], row) + Vector2(0.5, 0.5)) * TILE
				)
				for gate in gates:
					var body := Rect2(gate.global_position - gate.gate_size * 0.5, gate.gate_size)
					if body.has_point(center):
						return gate
		return null

	## Cells still ahead in this room: the rest of the hop being followed, then the next
	## LOOKAHEAD_HOPS hops from where it lands.
	func upcoming(where: Dictionary) -> Array:
		var cells: Array = []
		for hop_cells in _hops_ahead(where):
			cells.append_array(hop_cells)
		return cells

	## Resting cells the next hops land on in this room, in order.
	func landings(where: Dictionary) -> Array:
		var result: Array = []
		for hop_cells in _hops_ahead(where):
			if not (hop_cells as Array).is_empty():
				result.append(hop_cells[-1])
		return result

	func _hops_ahead(where: Dictionary) -> Array:
		if where.is_empty() or objective < 0 or hop.is_empty():
			return []
		var room := String(where["room"])
		var result: Array = []
		var current: Array = hop.slice(progress).filter(
			func(step: Array) -> bool: return step[0] == room
		)
		result.append(current)
		var last: Array = hop[-1]
		for _look in LOOKAHEAD_HOPS:
			if last[0] != room:
				break
			var next := route.entry(objective, room, Vector2i(last[1], last[2]), bool(last[3]))
			if next.is_empty() or (next[1] as Array).is_empty():
				break
			var cells: Array = (next[1] as Array).filter(
				func(step: Array) -> bool: return step[0] == room
			)
			result.append(cells)
			last = next[1][-1]
		return result

	## The hop cell to steer for: the next one; while the hop rises straight up, already the first
	## cell in another column once the feet are level with or above it, or earlier when drifting
	## there leaves the rise clear (the solver drifts at the top of the jump; the real jump has no
	## time left there).
	func _target_index(room: String, cell: Vector2i, player: Player, local: Vector2) -> int:
		var index := mini(progress, hop.size() - 1)
		var next: Array = hop[index]
		if next[0] != room or int(next[1]) != cell.x or int(next[2]) >= cell.y:
			return index
		for look in range(progress, hop.size()):
			var step: Array = hop[look]
			if step[0] != room:
				break
			if int(step[1]) != cell.x:
				var reach := cell.y - int(step[2]) <= JUMP_ROWS
				if int(step[2]) >= cell.y or (reach and _drift_clear(step, player, local)):
					index = look
				break
		return index

	## True when drifting toward `step` now keeps the rise to its row free: nothing overhead in the
	## next column over (a wall beside her only slides her up; a ceiling would end the jump).
	func _drift_clear(step: Array, player: Player, local: Vector2) -> bool:
		var shift := signf((float(step[1]) + 0.5) * TILE - local.x) * DRIFT_PROBE
		var rise := local.y - (float(step[2]) + 1.0) * TILE
		var moved := player.global_transform.translated(Vector2(shift, 0.0))
		if player.test_move(player.global_transform, Vector2(shift, 0.0)):
			return true
		return not player.test_move(moved, Vector2(0.0, -rise))

	## The side a climbing hop is taken running toward, off the edge (coyote time), or 0 to jump
	## where she stands. Running: when the hop leaves its column sideways before it climbs (the
	## solver drifts at the start of the jump), or when a straight jump from here would hit a ceiling
	## below the hop's top. Standing still, the head would catch the ledge overhead.
	func _takeoff_side(room: String, player: Player, local_x: float) -> int:
		_center = false
		var top := _from.y
		var side := 0
		var first: Array = []
		for step in hop:
			if step[0] != room:
				break
			top = mini(top, int(step[2]))
			if first.is_empty() and (int(step[1]) != _from.x or int(step[2]) != _from.y):
				first = step
			if side == 0 and int(step[1]) != _from.x:
				side = signi(int(step[1]) - _from.x)
		if top >= _from.y or first.is_empty():
			return 0
		# Not curled: the ball rolls at 580 px/s, so a run off the edge carries it under whatever
		# lies past the edge before the coyote jump takes. Round 12: kiln_06 (12, 21) rolled under
		# the west door's ledge and jumped into its underside, round after round (r11-full-s2 chose
		# `go_to_door:west:kiln_02` 5,227 times there); a jump in place drifts up onto the ledge.
		if side != 0 and int(first[2]) == _from.y and bool(first[4]) and not player.is_ball:
			# A wall that way: running into it only delays the jump (kiln_06 (17, 7)).
			return (
				0 if player.test_move(player.global_transform, Vector2(side * 8.0, 0.0)) else side
			)
		var rise := Vector2(0.0, -(_from.y - top) * TILE)
		if not player.test_move(player.global_transform, rise):
			return 0
		# Blocked from where she stands but clear from the resting cell's centre (her body
		# overlaps a wall column above): step to the centre first, then jump straight up.
		var centred := player.global_transform
		centred.origin.x += (_from.x + 0.5) * TILE - local_x
		if not player.test_move(centred, rise):
			_center = true
			return 0
		return side

	## The hop's last cell in `room`: where it lands, or the exit it leaves by.
	func _landing(room: String) -> Array:
		for index in range(hop.size() - 1, -1, -1):
			if hop[index][0] == room:
				return hop[index]
		return hop[-1]

	## True while the hop still climbs above the feet row: a jump or wall jump is wanted.
	func _rises(room: String, cell: Vector2i) -> bool:
		for index in range(progress, hop.size()):
			var step: Array = hop[index]
			if step[0] != room:
				return false
			if int(step[2]) < cell.y:
				return true
			if not bool(step[4]):
				return false
		return false

	## Holds jump while the hop climbs: pressed on the ground (or just off an `edge` the hop leaves
	## sideways), or against a wall when the way on is up or away from it, then kept to the top of
	## the rise (letting go early cuts the jump short).
	## A press still on the ground or wall after PRESS_GRACE frames did not take (the driver sends
	## it after the player's step), so it is released and pressed again.
	func _press_jump(
		held: Array, where: Dictionary, player: Player, rises: bool, dx: float, edge: bool
	) -> void:
		if _jump_release > 0:
			_jump_release -= 1
			_jump_frames = 0
			return
		var grounded := bool(where["grounded"])
		var side := int(player.get("_wall_side"))
		var wall := (
			rises
			and not grounded
			and not bool(where["ball"])
			and side != 0
			and player.velocity.y > WALL_JUMP_SPEED
			and (_climb_dir == side or absf(dx) <= CENTER_PX or signf(dx) != float(side))
		)
		if _jump_frames > 0:
			if (grounded or wall) and _jump_frames > PRESS_GRACE:
				_jump_release = 1
				_jump_frames = 0
				return
			if (
				not grounded
				and not wall
				and player.velocity.y >= 0.0
				and _jump_frames > PRESS_GRACE
			):
				_jump_frames = 0
				return
			_jump_frames += 1
		elif rises and grounded and edge:
			return
		elif (
			rises
			and (grounded or wall or (_air_frames <= COYOTE_FRAMES and player.velocity.y >= 0.0))
		):
			_jump_frames = 1
			if wall:
				_climb_dir = -side
		else:
			return
		held.append(&"jump")

	## Where to steer: the target cell's centre, or past the room edge when the hop leaves (from
	## its last cell in this room, or from the feet when it leaves at once).
	func _aim_x(target: Array, room: String, where: Dictionary) -> float:
		if target[0] == room:
			return (float(target[1]) + 0.5) * TILE
		var size: Vector2 = (where["room_node"] as Node2D).call("size_px")
		var column: int = (where["cell"] as Vector2i).x
		for index in range(hop.size() - 1, -1, -1):
			if hop[index][0] == room:
				column = int(hop[index][1])
				break
		if column <= 0:
			return -TILE
		if (column + 1) * TILE >= size.x:
			return size.x + TILE
		return (float(column) + 0.5) * TILE


## Live program: follows the navigator's hops for `frames` physics frames, then until she stands
## again; ends early at the objective, off the field, or when the feet stop moving.
class Follow:
	extends RefCounted

	var finished := false
	var _nav: Navigator
	var _root: Node
	var _player: Player
	var _index := -1
	var _frames_left := 0
	var _air_left := AIR_FRAMES
	var _still := 0
	var _last := Vector2.INF

	func _init(nav: Navigator, root: Node, player: Player, index: int, frames: int) -> void:
		_nav = nav
		_root = root
		_player = player
		_index = index
		_frames_left = frames

	func next() -> Array:
		_frames_left -= 1
		_air_left -= 1
		# A jump on the route is flown to its landing: the frame budget ends a program only on
		# the ground (or after AIR_FRAMES in the air), so no decision drops her mid-leap.
		if (_frames_left <= 0 and _player.is_on_floor()) or _air_left <= 0:
			finished = true
			return []
		var where := Navigator.locate(_root, _player)
		var status := _nav.refresh(where, _index)
		if status == "at_goal" or status == "off_field":
			finished = true
			return []
		var position := _player.global_position
		_still = _still + 1 if position.distance_to(_last) < 6.0 else 0
		if _still == 0:
			_last = position
		if _still >= STALL_FRAMES:
			# Held still in the air (an updraft at a lip): the same hop would only hold her there
			# again, so the next decision reads the field or rejoins it.
			if not _player.is_on_floor() and _nav.passed_in(where):
				_nav.drop_hop()
			finished = true
			return []
		return _nav.control(where, _player)
