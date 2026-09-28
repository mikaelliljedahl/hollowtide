"""Campaign-mode goal for Jev's compact state (tools/playtest/jev_backend.py): the `goal` block the
game's campaign mode exports (tools/playtest_campaign.gd) as a few plain facts, arithmetic done here.
"""

from __future__ import annotations

from typing import Any


def facts(goal: dict[str, Any]) -> dict[str, Any]:
    """The campaign goal in words (tools/playtest_campaign.gd): what, how far along, which way."""
    doors = goal.get("doors") or []
    result: dict[str, Any] = {
        "now": goal["objective"],
        "progress": f"{goal['done']} of {goal['count']} objectives done",
        "route": (
            "the objective is in this room"
            if not doors
            else f"next door {doors[0]}, {len(doors)} room change(s) to go"
        ),
        "heading": goal.get("heading") or "unknown",
        "on_route": goal.get("route_status") in ("on_field", "airborne"),
        "minutes_on_it": round(float(goal.get("seconds_on_objective", 0.0)) / 60.0, 1),
    }
    gate = goal.get("gate_ahead")
    if gate:
        owned = "owned" if gate.get("owned") else "not owned"
        result["gate_ahead"] = (
            f"a closed {gate['name']} blocks the route; it needs {gate['opens_with']} ({owned})"
        )
    return result
