"""Movement graph of the campaign route planner (tools/playtest/campaign_route.py), cached per room.

The route solver's moves from a state depend only on the cells of its own room and of the rooms its
exits lead into, plus two kit-wide abilities (High Jump sets the jump height, Slipstream allows the
curl). So the weighted successors of every state are kept per room under a key of just the kit
items that room can feel (its gates, flag gates, timed doors, floaters, heat, and those of its exit
rooms). A new pickup or boss flag then only recomputes the rooms it changes. Round 9's planner
recomputed every move for every objective, which took over two minutes on the 48-room world.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from campaign_layout import room_at_world  # noqa: E402
from check_campaign_graph import GATE_NEEDS, Solver, World, timed_flag  # noqa: E402

State = tuple[str, int, int, bool, int, int]
Edge = tuple[State, int]
# Kit items every room feels: the jump height and the curl.
GLOBAL_ITEMS = frozenset({"high_jump", "slipstream"})
UNREACHED = 1 << 30
# Extra cost per solver step in Slipstream form, per change of form, and per step on a lava basin.
BALL_COST = 3
TOGGLE_COST = 2
LAVA_COST = 20
MAX_STEP = 1 + BALL_COST + TOGGLE_COST + LAVA_COST


class RouteSolver(Solver):
    """The graph check's solver, minus a move the game does not allow: the player curls into
    Slipstream form only standing on a floor (scripts/player/player.gd, _handle_slip_input).
    With `terrain` (room id -> memo dict, shared by kits that leave the room's own items alone)
    the cell tests are looked up once per cell instead of on every move."""

    def __init__(self, *args, terrain: dict[str, dict] | None = None, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.terrain = terrain

    def solid(self, room, x, y):
        if self.terrain is None:
            return super().solid(room, x, y)
        memo = self.terrain[room.room_id]
        found = memo.get((x, y))
        if found is None:
            found = memo[(x, y)] = super().solid(room, x, y)
        return found

    def body_clear(self, room, x, y, ball):
        if self.terrain is None:
            return super().body_clear(room, x, y, ball)
        memo = self.terrain[room.room_id]
        found = memo.get((x, y, ball))
        if found is None:
            found = memo[(x, y, ball)] = super().body_clear(room, x, y, ball)
        return found

    def neighbours(self, state):
        result = super().neighbours(state)
        if state[3] or resting(self, state):
            return result
        return [nxt for nxt in result if not nxt[3]]


def resting(solver: Solver, state: State) -> bool:
    room_id, x, y, _ball, up, side = state
    return up == 0 and side == 0 and solver.platform(solver.world.rooms[room_id], x, y + 1)


def step_cost(solver: Solver, state: State, nxt: State) -> int:
    """Solver steps weighted the way a player moves: Slipstream form only where it is needed (it
    cannot shoot), and never along a lava basin when there is another way."""
    cost = 1
    if nxt[3]:
        cost += BALL_COST
    if nxt[3] != state[3]:
        cost += TOGGLE_COST
    room = solver.world.rooms[nxt[0]]
    if solver.lava(room, nxt[1], nxt[2] + 1) or solver.lava(room, nxt[1], nxt[2]):
        cost += LAVA_COST
    return cost


def _room_items(world: World, room_id: str) -> set[str]:
    room = world.rooms[room_id]
    items: set[str] = set()
    for char, entry in room.legend.items():
        if entry.kind == "gate":
            items.add(GATE_NEEDS[entry.args[0]])
        elif entry.kind == "flaggate":
            items.update(entry.args[0].split(","))
        elif entry.kind == "timeddoor":
            items.add(timed_flag(room_id, char))
    if world.floaters[room_id]:
        items.add("ice_beam")
    if world.heat[room_id]:
        items.add("pressure_seal")
    return items


def _exit_rooms(world: World, room_id: str) -> set[str]:
    room = world.rooms[room_id]
    found: set[str] = set()
    edge_cells = [(x, -1) for x in range(room.width)] + [
        (x, room.height) for x in range(room.width)
    ]
    edge_cells += [(-1, y) for y in range(room.height)] + [
        (room.width, y) for y in range(room.height)
    ]
    for x, y in edge_cells:
        target = room_at_world(world.rooms, room.origin[0] + x, room.origin[1] + y)
        if target is not None:
            found.add(target.room_id)
    return found


class RouteGraph:
    """Weighted successors per state, shared by every kit that leaves a room's items unchanged."""

    def __init__(self, world: World) -> None:
        self.world = world
        self.items: dict[str, frozenset[str]] = {}
        for room_id in world.rooms:
            felt = _room_items(world, room_id)
            for other in _exit_rooms(world, room_id):
                felt |= _room_items(world, other)
            self.items[room_id] = frozenset(felt) | GLOBAL_ITEMS
        self.own: dict[str, frozenset[str]] = {
            room_id: frozenset(_room_items(world, room_id)) for room_id in world.rooms
        }
        self._tables: dict[tuple[str, frozenset[str]], dict[State, tuple[Edge, ...]]] = {}
        self._terrain: dict[tuple[str, frozenset[str]], dict] = {}
        self.felt = frozenset().union(*self.items.values())

    def kit(self, abilities: set[str], flags: set[str]) -> Kit:
        return Kit(self, abilities, flags)

    def moves_key(self, abilities: set[str], flags: set[str]) -> frozenset[str]:
        """The kit items any room's moves depend on: kits with the same key share one graph."""
        return (frozenset(abilities) | frozenset(flags)) & self.felt


class Kit:
    """The movement graph with one kit and flag set: successors, the states reachable from the
    start, and shortest weighted distances over them."""

    def __init__(self, graph: RouteGraph, abilities: set[str], flags: set[str]) -> None:
        self.graph = graph
        self.world = graph.world
        self.key = graph.moves_key(abilities, flags)
        owned = frozenset(abilities) | frozenset(flags)
        terrain = {
            room_id: graph._terrain.setdefault((room_id, owned & items), {})
            for room_id, items in graph.own.items()
        }
        self.solver = RouteSolver(
            graph.world,
            set(abilities),
            set(flags),
            set(),
            crumble_gone=True,
            breaks=False,
            terrain=terrain,
        )
        self._tables = {
            room_id: graph._tables.setdefault((room_id, owned & items), {})
            for room_id, items in graph.items.items()
        }
        self.states: list[State] = []
        self.index: dict[State, int] = {}
        self.rest: list[bool] = []
        self._after: list[list[tuple[int, int]]] = []
        self._before: list[list[tuple[int, int]]] = []
        self._rooms: dict[str, list[int]] = {}

    def successors(self, state: State) -> tuple[Edge, ...]:
        table = self._tables[state[0]]
        found = table.get(state)
        if found is None:
            solver = self.solver
            found = tuple(
                (nxt, step_cost(solver, state, nxt))
                for nxt in solver.neighbours(state)
                if solver.inside(nxt)
            )
            table[state] = found
        return found

    def reach(self, start: State) -> list[State]:
        """States reachable from `start`, numbered in `index`, with numbered moves both ways and
        `rest` (feet on a floor); built once per kit."""
        if self.states:
            return self.states
        states = [start]
        index = {start: 0}
        after: list[list[tuple[int, int]]] = []
        before: list[list[tuple[int, int]]] = [[]]
        position = 0
        while position < len(states):
            moves = []
            for nxt, cost in self.successors(states[position]):
                number = index.get(nxt)
                if number is None:
                    number = index[nxt] = len(states)
                    states.append(nxt)
                    before.append([])
                before[number].append((position, cost))
                moves.append((number, cost))
            after.append(moves)
            position += 1
        self.states = states
        self.index = index
        self._after = after
        self._before = before
        self.rest = [resting(self.solver, state) for state in states]
        for number, state in enumerate(states):
            self._rooms.setdefault(state[0], []).append(number)
        return states

    def covering(self, room_id: str, cells: set[tuple[int, int]]) -> list[int]:
        """Reached states whose body covers one of `cells` in `room_id`."""
        result = []
        for number in self._rooms.get(room_id, ()):
            _room, x, y, ball, _up, _side = self.states[number]
            rows = (y,) if ball else (y, y - 1, y - 2)
            if any((x, row) in cells for row in rows):
                result.append(number)
        return result

    def moves(self, number: int) -> list[tuple[int, int]]:
        """(next state number, weighted cost) for every move from state `number`."""
        return self._after[number]

    def distances_to(self, goal: list[int]) -> list[int]:
        """Weighted steps from every reached state to the nearest `goal` state (UNREACHED when
        it has no path). Costs are small integers, so a bucket per distance replaces the heap."""
        return _buckets(self._before, len(self.states), goal, None)[0]

    def nearest(self, start: State, wanted) -> tuple[int, list[State]] | None:
        """Search from `start` (reached) to the first state for which `wanted(state, steps)`
        holds: (weighted steps, the path's states from `start` to it), or None."""
        states = self.states
        distance, parent, found = _buckets(
            self._after,
            len(states),
            [self.index[start]],
            lambda number, steps: wanted(states[number], steps),
        )
        if found < 0:
            return None
        path = [found]
        while parent[path[-1]] >= 0:
            path.append(parent[path[-1]])
        return distance[found], [states[number] for number in reversed(path)]


def _buckets(moves, count: int, starts: list[int], wanted) -> tuple[list[int], list[int], int]:
    """Shortest weighted steps over `moves` from `starts` (Dial's algorithm), stopping at the
    first state `wanted` accepts: (distances, parents, that state or -1)."""
    distance = [UNREACHED] * count
    parent = [-1] * count
    buckets: list[list[int]] = [list(starts)]
    for number in starts:
        distance[number] = 0
    pending = len(starts)
    steps = 0
    while pending:
        if len(buckets) < steps + MAX_STEP + 1:
            buckets.extend([] for _ in range(MAX_STEP + 1))
        bucket = buckets[steps]
        pending -= len(bucket)
        for number in bucket:
            if distance[number] != steps:
                continue
            if wanted is not None and wanted(number, steps):
                return distance, parent, number
            for other, cost in moves[number]:
                total = steps + cost
                if total < distance[other]:
                    distance[other] = total
                    parent[other] = number
                    buckets[total].append(other)
                    pending += 1
        buckets[steps] = []
        steps += 1
    return distance, parent, -1
