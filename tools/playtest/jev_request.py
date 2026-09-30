"""Request building for the Jev playtest backend (tools/playtest/jev_backend.py): the compact state
Jev sees (tiles relative to the player, ranges in words, arithmetic done here because Jev is weak at
numbers), the legal candidate filter and the three questions. Pure functions over the exported
state; the contract is in docs/features/playtest-agent.md ("Jev backend").
"""

from __future__ import annotations

from typing import Any

import jev_objective

TILE = 64.0
MAX_THREATS = 3
MAX_SHOTS = 3
SHOT_ALERT_TILES = 6.0
QUESTION_ACTION = "action"
QUESTION_DANGER = "danger"
QUESTION_UNSURE = "unsure"
MAX_HAZARDS = 2
HAZARD_ALERT_TILES = 4.0
BOLT_KINDS = ("beam", "ice", "wave")  # hurt_by kinds the crossbow fires (playtest_policy.gd)
BEAM_NAMES = {"base": "seed bolt", "ice": "Snare (ice)", "wave": "Echo (wave)"}
# One line of guidance per candidate kind, appended to the game's own label.
RUBRIC = {
    "idle": "Right only when nothing threatens the player and waiting helps.",
    "approach": "Closes distance; right when the target is in sight, reachable and safe to near.",
    "retreat": "Gains distance; right when a threat is close, winding up, or health is low.",
    "shoot": "Right when the target is in line, the crossbow hurts it, and no hit is imminent.",
    "harpoon": "Limited ammo; right for an open boss or an enemy the crossbow cannot hurt.",
    "jump_shoot": "Right for a target too high for a standing shot, when no hit is imminent.",
    "crouch_shot": (
        "A standing shot flies over a target this low (below_standing_shot); crouched fire hits it."
        " Right for such a target when no hit is imminent."
    ),
    "open_boss": "Opens a closed boss shell for the Harpoon; right when the boss is not about to hit.",
    "select_beam": "Right when the equipped bolt cannot hurt or open the target and this one can.",
    "pulse": "Right for a close, level enemy that only the Resonance Pulse hurts.",
    "go_to_refill": "Right when out of Harpoons or low on health and no hit is imminent.",
    "jump_over": "Right when a ground enemy is about to touch the player.",
    "dash_through": "Dashing into a shot deflects it; right when a shot is about to hit.",
    "duck": "Curling into a ball lets a shot at body height fly over; right just before it hits.",
    "dodge": (
        "The answer that avoids the boss attack winding up now, timed for you; choose it over"
        " retreat or approach while it is offered."
    ),
    "wall_jump": "Right when clinging to a wall and the way on is upward.",
    "go_to_ambush": "Starts the arena fight, which the goal needs; right unless a hit is imminent.",
    "pick_up": "Right when the area is safe.",
    "go_to_exit": "Leaves the room; right only when nothing here is left to fight.",
    "jump": "Right to clear an obstacle or to break out of a stall.",
    "go_to_objective": (
        "Follows the planned route toward the current objective; right unless a threat must be"
        " dealt with first."
    ),
    "go_to_door": "Leaves through this door; right when it is the door on the route.",
    "open_gate": "Opens the closed gate on the route; right when it blocks the way and no hit is imminent.",
    "freeze": "Freezes a frost floater the route stands on; right before jumping onto it.",
    "fast_travel": (
        "Travels to another shrine; right when the objective is far from here and much nearer there."
    ),
}
DANGER_CRITERIA = [
    "low: nothing can hit the player within the next second",
    "medium: a threat is close or winding up, but there is time to react",
    "high: the player will be hit unless the next action avoids it",
]


def tiles(value: float) -> int:
    return round(value / TILE)


def side(rel: list[float]) -> str:
    horizontal = "right" if rel[0] > TILE / 2 else "left" if rel[0] < -TILE / 2 else ""
    vertical = "below" if rel[1] > TILE else "above" if rel[1] < -TILE else ""
    return ", ".join(part for part in (horizontal, vertical) if part) or "on top of the player"


def range_word(distance_tiles: float) -> str:
    if distance_tiles < 1.5:
        return "touching"
    if distance_tiles < 4:
        return "close"
    if distance_tiles < 10:
        return "mid range"
    return "far"


def legal(candidates: list[dict[str, Any]], state: dict[str, Any], hint: str) -> list[dict]:
    """Drops candidates the current state makes impossible; the hint always stays."""
    player = state.get("player") or {}
    kit = state.get("kit") or {}
    enemies = {enemy.get("id"): enemy for enemy in state.get("enemies", [])}
    refill_first = _refill_first(candidates, state)
    kept = []
    for candidate in candidates:
        kind = candidate.get("kind", "")
        target = enemies.get((candidate.get("key", "").split(":") + [""])[1]) or {}
        blocked = (
            (kind == "harpoon" and int(kit.get("missiles", 0)) <= 0)
            or (kind in ("shoot", "jump_shoot") and not _bolt_matters(target, kit))
            or (kind in ("shoot", "jump_shoot") and "beam" not in kit.get("abilities", []))
            or (kind == "crouch_shot" and not _crouch_shot_legal(candidate, target, player, kit))
            or (kind == "pulse" and "bombs" not in kit.get("abilities", []))
            or (kind == "dash_through" and not player.get("dash_ready", False))
            or (kind in ("duck", "dodge") and not player.get("grounded", False))
            or (kind == "wall_jump" and not player.get("on_wall", False))
            or (kind == "jump_over" and not player.get("grounded", False))
            or (kind == "approach" and refill_first and bool(target.get("is_boss")))
        )
        if not blocked or candidate.get("key") == hint:
            kept.append(candidate)
    return kept


def _refill_first(candidates: list[dict[str, Any]], state: dict[str, Any]) -> bool:
    """True while the quiver is empty, a boss is in the room that no bolt hurts, and the refill
    run to Harpoons is offered: closing in on it then only loses time. t4-min-s1b chose `approach`
    at a shut Tidal Heart 1,880 times with the missile refill offered (Jev's own pick at 0.65)."""
    kit = state.get("kit") or {}
    if int(kit.get("max_missiles", 0)) <= 0 or int(kit.get("missiles", 0)) > 0:
        return False
    if not any(e.get("is_boss") and not _bolt_matters(e, kit) for e in state.get("enemies", [])):
        return False
    restores = {
        refill.get("kind"): refill.get("restores", []) for refill in state.get("refills", [])
    }
    return any(
        candidate.get("kind") == "go_to_refill"
        and "harpoons" in restores.get(candidate.get("key", "").partition(":")[2], [])
        for candidate in candidates
    )


def _crouch_shot_legal(
    candidate: dict[str, Any], target: dict[str, Any], player: dict[str, Any], kit: dict[str, Any]
) -> bool:
    """A crouch needs the ground; its Harpoon needs ammo and its bolt a target the bolt changes."""
    if not player.get("grounded", False):
        return False
    if candidate.get("key", "").endswith(":harpoon"):
        return int(kit.get("missiles", 0)) > 0
    return _bolt_matters(target, kit)


def _bolt_matters(target: dict[str, Any], kit: dict[str, Any]) -> bool:
    """False for a shot that cannot change an ordinary enemy: no bolt hurts it, or the Snare at
    one already frozen. The heuristic never fires those; Jev did for minutes (full-jev-a: 40 s of
    seed bolts at a vaults_01 armored guard until the arena's stall abort, 120 s of Snare shots at
    a frozen kiln_01 mimic with the energy tank never taken). A closed boss no bolt hurts is the
    same: its opener is `open_boss`, and t4-min-s1 fired 2,605 bolts at the shut Tidal Heart."""
    if not target:
        return True
    if not any(kind in BOLT_KINDS for kind in target.get("hurt_by", [])):
        return False
    return not (kit.get("beam") == "ice" and target.get("frozen"))


def _threat(enemy: dict[str, Any]) -> dict[str, Any]:
    distance = enemy["dist"] / TILE
    entry: dict[str, Any] = {
        "id": enemy["id"],
        "kind": enemy["type"],
        "dx_tiles": tiles(enemy["rel"][0]),
        "dy_tiles": tiles(enemy["rel"][1]),
        "where": side(enemy["rel"]),
        "range": range_word(distance),
        "health_pct": round(100 * enemy["health"] / max(1, enemy["max_health"])),
        "winding_up": bool(enemy.get("telegraph")),
        "player_can_hurt_it": bool(enemy.get("hurt_by")),
        "in_line_of_sight": bool(enemy.get("visible")),
        "arena_enemy": bool(enemy.get("ambush")),
        "frozen": bool(enemy.get("frozen")),
        "below_standing_shot": bool(enemy.get("low")),
        "route_platform": bool(enemy.get("platform")),
    }
    if enemy.get("switch_to"):
        entry["hurt_by_bolt"] = BEAM_NAMES.get(enemy["switch_to"], enemy["switch_to"])
    if enemy.get("is_boss"):
        entry["boss_stage"] = enemy.get("stage")
        entry["boss_attack"] = enemy.get("attack") or "none"
        entry["boss_attack_state"] = enemy.get("attack_state") or "idle"
        entry["shell"] = shell_text(enemy)
    return entry


def shell_text(boss: dict[str, Any]) -> str:
    """The boss's shell in words: open, or closed and what opens it (tools/playtest_boss.gd)."""
    if boss.get("open", True):
        return "open: the Harpoon hurts it now"
    if not boss.get("opening", True):
        return "closed; nothing hurts it until it recovers after its next attack"
    opener = boss.get("opener")
    if not opener:
        return "closed"
    if opener["via"] == "punish":
        return "closed; it opens while the boss recovers after an attack"
    where = "through the grate in front of it" if opener["via"] == "grate" else "at its body"
    bolt = BEAM_NAMES.get(opener["beam"], opener["beam"])
    article = "an" if bolt[:1].lower() in "aeiou" else "a"
    text = f"closed; {article} {bolt} shot {where} opens it"
    return text if opener.get("owned") else f"{text} (not in the kit)"


def _hazard(hazard: dict[str, Any]) -> dict[str, Any]:
    entry = {
        "kind": hazard["kind"],
        "where": side(hazard["rel"]),
        "touching": hazard.get("gap", 1) <= 0,
    }
    if hazard.get("state"):
        entry["state"] = hazard["state"]
    return entry


def _shot(shot: dict[str, Any]) -> dict[str, Any]:
    rel, vel = shot["rel"], shot["vel"]
    return {
        "dx_tiles": tiles(rel[0]),
        "dy_tiles": tiles(rel[1]),
        "where": side(rel),
        "approaching": rel[0] * vel[0] + rel[1] * vel[1] < 0,
    }


def goal_text(state: dict[str, Any]) -> str:
    if any(enemy.get("is_boss") for enemy in state.get("enemies", [])):
        return "Defeat the boss in this room without dying."
    arena = state.get("ambush")
    if arena and arena.get("state") == "armed":
        return "Start the arena fight by walking into the arena, then clear every wave alive."
    if arena and arena.get("state") in ("sealing", "fighting", "intermission"):
        return "Clear the arena in this room: defeat every wave without dying."
    goal = state.get("goal")
    if goal:
        return (
            f"Reach the campaign objective: {goal['objective']}. Follow the route; fight only what"
            " threatens or blocks the way."
        )
    return "Explore: reach a pickup or an open exit without taking damage."


def compact_state(state: dict[str, Any], last: dict[str, Any]) -> dict[str, Any]:
    """The state Jev sees: relative tiles, words for ranges, and arithmetic done here."""
    player = state["player"]
    health_pct = round(100 * player["health"] / max(1, player["max_health"]))
    threats = [_threat(enemy) for enemy in state.get("enemies", [])[:MAX_THREATS]]
    shots = [
        _shot(shot)
        for shot in state.get("projectiles", [])
        if abs(shot["rel"][0]) / TILE <= SHOT_ALERT_TILES
    ][:MAX_SHOTS]
    arena = state.get("ambush")
    boss = next((enemy for enemy in state.get("enemies", []) if enemy.get("is_boss")), None)
    kit = state["kit"]
    hazards = [
        _hazard(hazard)
        for hazard in state.get("hazards", [])
        if hazard.get("gap", 0) / TILE <= HAZARD_ALERT_TILES
    ][:MAX_HAZARDS]
    refills = sorted({need for refill in state.get("refills", []) for need in refill["restores"]})
    facts: dict[str, Any] = {
        "health": "healthy" if health_pct >= 60 else "hurt" if health_pct >= 30 else "critical",
        "nearest_threat": threats[0]["range"] if threats else "none",
        "nearest_threat_where": threats[0]["where"] if threats else "none",
        "threat_winding_up": any(threat["winding_up"] for threat in threats),
        "shot_incoming": any(shot["approaching"] for shot in shots),
        "in_arena": bool(arena and arena.get("inside")),
        "stalled": bool(last.get("stalled")),
        "refill_here_for": ", ".join(refills) or "none",
    }
    if arena:
        facts["arena"] = (
            f"{arena['state']}, wave {arena['wave']} of {arena['waves']}, {arena['alive']} left"
        )
    if boss:
        facts["boss_stage"] = boss.get("stage")
        facts["boss_attack"] = boss.get("attack") or "none"
        facts["boss_shell"] = shell_text(boss)
        if int(kit.get("max_missiles", 0)) > 0 and int(kit["missiles"]) <= 0:
            facts["quiver"] = "empty: refill Harpoons before closing in on the boss"
    compact: dict[str, Any] = {
        "goal": goal_text(state),
        "player": {
            "health_pct": health_pct,
            "grounded": player["grounded"],
            "on_wall": player["on_wall"],
            "facing": "right" if player["facing"] > 0 else "left",
            "form": player["form"],
            "dash_ready": player["dash_ready"],
            "harpoons_left": kit["missiles"],
            "bolt": BEAM_NAMES.get(kit.get("beam", "base"), kit.get("beam", "base")),
            "bolts_owned": [BEAM_NAMES.get(beam, beam) for beam in kit.get("beams", [])],
        },
        "threats": threats,
        "incoming_shots": shots,
        "hazards": hazards,
        "facts": facts,
        "last_action": last.get("summary", "none"),
    }
    if state.get("goal"):
        compact["objective"] = jev_objective.facts(state["goal"])
    return compact


def build_request(
    model: str, state: dict[str, Any], candidates: list[dict], last: dict[str, Any]
) -> dict:
    criteria = {
        candidate["key"]: f"{candidate['label']}. {RUBRIC.get(candidate['kind'], '')}".strip()
        for candidate in candidates
    }
    return {
        "model": model,
        "state": compact_state(state, last),
        "questions": {
            QUESTION_ACTION: {
                "type": "choice",
                "instructions": "Pick the player's next action for the goal in `state`.",
                "criteria": criteria,
            },
            QUESTION_DANGER: {
                "type": "score",
                "instructions": "How likely is the player to take damage in the next second?",
                "criteria": DANGER_CRITERIA,
            },
            QUESTION_UNSURE: {
                "type": "noul",
                "instructions": (
                    "Is the player stuck, or is it unclear from `state` which action is right?"
                ),
            },
        },
    }
