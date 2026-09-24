"""Boss shortcut rule for the campaign graph check (tools/check_campaign_graph.py).

Each branch boss room must hold a shortcut back to the hub: a flag gate on that boss's flag within
SHORTCUT_DEPTH cells of a door into a hub room, which the movement solver cannot pass before the
boss flag and can walk through once it is set (docs/features/fast-travel.md, section 6).
"""

from __future__ import annotations

from campaign_layout import link_doors

HUB_AREA = "nexus"
# A shortcut gate may stand this many cells inside the room from its hub door.
SHORTCUT_DEPTH = 4


def shortcut_errors(world, stages, label: str, regional: set[str], covered_cells) -> list[str]:
    """Each branch boss opens a gate at a door into the hub (phase-2-campaign.md, graph notes)."""
    errors = []
    doors, _ = link_doors(world.rooms)
    for boss in sorted(regional & world.bosses.keys()):
        room_id = world.bosses[boss][0]
        room = world.rooms[room_id]
        flag = f"boss:{boss}"
        gate_cells = {
            cell
            for char, entry in room.legend.items()
            if entry.kind == "flaggate" and flag in entry.args[0].split(",")
            for cell in room.cells_of(char)
        }
        hub_cells = [
            (door.edge, cell)
            for door in doors
            if door.room == room_id
            and door.target is not None
            and world.rooms[door.target].area == HUB_AREA
            for cell in door.cells
        ]
        at_hub_door = any(
            (gy == dy and abs(gx - dx) <= SHORTCUT_DEPTH)
            if edge in ("west", "east")
            else (gx == dx and abs(gy - dy) <= SHORTCUT_DEPTH)
            for gx, gy in gate_cells
            for edge, (dx, dy) in hub_cells
        )
        if not at_hub_door:
            errors.append(f"[{label}] {room_id}: no {flag} shortcut gate at a door into the hub")
            continue

        def crossed(stage) -> bool:
            return any(
                cell[0] == room_id and (cell[1], cell[2]) in gate_cells
                for state in stage[3]
                for cell in covered_cells(state)
            )

        before = [stage for stage in stages if flag not in stage[1]]
        after = [stage for stage in stages if flag in stage[1]]
        if any(crossed(stage) for stage in before):
            errors.append(f"[{label}] {room_id}: {flag} shortcut is passable before the boss")
        if not after or not crossed(after[-1]):
            errors.append(f"[{label}] {room_id}: {flag} shortcut never becomes walkable")
    return errors
