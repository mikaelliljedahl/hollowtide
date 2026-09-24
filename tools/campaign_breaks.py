"""Intended sequence breaks for the campaign graph check (tools/check_campaign_graph.py).

A break is a skilled movement route the conservative solver does not model: a single-wall climb (it
only climbs chimneys) or an air Undertow Dash (it has no dash). Each one is given to the solver as a
single edge from a standing feet cell to a standing feet cell in the same room, usable once the listed
abilities are owned. Its reward pickups must be reachable only through a break edge: the solver with
every ability, every flag and no break edges may never touch them. Design and rationale:
docs/features/sequence-breaks.md. The real-input proof is tools/check_sequence_breaks.gd.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Break:
    break_id: str
    room: str
    start: tuple[int, int]  # standing feet cell where the move begins
    end: tuple[int, int]  # standing feet cell where it lands
    needs: frozenset[str]
    rewards: tuple[str, ...]  # pickup ids only a break edge reaches


BREAKS = (
    Break("breach_ledge", "fringe_01", (5, 13), (3, 6), frozenset(), ("fringe_01.missile_ledge",)),
    Break(
        "pillar_ledge", "vaults_02", (16, 31), (17, 21), frozenset(), ("vaults_02.energy_pillar",)
    ),
    Break("pillar_band", "vaults_02", (21, 31), (20, 14), frozenset(), ()),
    Break(
        "undertow_gap",
        "depths_01",
        (15, 19),
        (23, 19),
        frozenset({"undertow_dash"}),
        ("depths_01.energy_corridor",),
    ),
)


def break_edges() -> dict[tuple[str, int, int], list[tuple[int, int, frozenset[str]]]]:
    edges: dict[tuple[str, int, int], list[tuple[int, int, frozenset[str]]]] = {}
    for item in BREAKS:
        edges.setdefault((item.room, *item.start), []).append((*item.end, item.needs))
    return edges


def break_errors(world, solver_class, all_abilities: set[str], covered_cells) -> list[str]:
    """Static break rules: real standing spots, a start reachable by normal play, exclusive rewards."""
    errors = []
    flags = {f"{prefix}:{boss}" for boss in world.bosses for prefix in ("boss", "regional")}
    flags |= {f"timed:{room_id}:{char}" for room_id, char in world.timed}
    plain = solver_class(world, set(all_abilities), flags, set(), breaks=False)
    starts = [(world.start[0], world.start[1], world.start[2], False, 0, 0)]
    starts += [(room_id, x, y, False, 0, 0) for room_id, x, y in sorted(world.saves)]
    seen, _edges = plain.explore(starts)
    cells = set()
    for state in seen:
        cells.update(covered_cells(state))
    feet = {(state[0], state[1], state[2]) for state in seen if not state[3]}
    pickup_cells = {pickup_id: key for key, (pickup_id, _kind) in world.pickups.items()}
    for item in BREAKS:
        room = world.rooms[item.room]
        for label, (x, y) in (("start", item.start), ("end", item.end)):
            if not plain.body_clear(room, x, y, False) or not plain.solid(room, x, y + 1):
                errors.append(f"break {item.break_id}: {label} {x},{y} is not a standing spot")
        if (item.room, *item.start) not in feet:
            errors.append(
                f"break {item.break_id}: start {item.start} is not reachable by normal play"
            )
        for reward in item.rewards:
            key = pickup_cells.get(reward)
            if key is None:
                errors.append(f"break {item.break_id}: reward {reward} is not a campaign pickup")
            elif key in cells:
                errors.append(
                    f"break {item.break_id}: reward {reward} is reachable without a break"
                )
    return errors
