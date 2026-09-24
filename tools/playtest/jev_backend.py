"""Hosted Jev (TypeSafe System One) backend for the Hollowtide playtest agent.

Each decision is one POST {base_url}/v1/systemone with a compact state (tiles relative to the
player, facts precomputed in code) and three questions: a `choice` over the legal candidate keys,
a `score` for danger and a `noul` for "stuck or unsure". Any error, timeout or low confidence
returns the game's heuristic `hint` and records why. Standard library only; the contract and the
data boundary are in docs/features/playtest-agent.md ("Jev backend").

The API key is read from the environment inside `Client.post`, at the moment of each request, and
is never stored, printed, logged or written; error text from the server is scrubbed of it.
"""

from __future__ import annotations

import http.client
import json
import os
import time
from collections import deque
from dataclasses import dataclass
from typing import Any
from urllib.parse import urlsplit

from policy_server import Backend

KEY_ENV = "TYPESAFE_API_KEY"
BASE_URL_ENV = "TYPESAFE_BASE_URL"
DEFAULT_BASE_URL = "https://api.typesafe.ai"
# Pinned: the API accepted it, and jev-latest answered as jev-1.13.0 (checked 2026-09-24).
DEFAULT_MODEL = "jev-1.13.0"
ENDPOINT = "/v1/systemone"
TILE = 64.0
REQUESTS_PER_MINUTE = 1200
MAX_THREATS = 3
MAX_SHOTS = 3
SHOT_ALERT_TILES = 6.0
ERROR_TEXT_LIMIT = 300
RETRY_AFTER_CAP = 10.0
QUESTION_ACTION = "action"
QUESTION_DANGER = "danger"
QUESTION_UNSURE = "unsure"
MOVING_KINDS = (
    "approach",
    "retreat",
    "go_to_exit",
    "go_to_ambush",
    "pick_up",
    "jump",
    "go_to_refill",
)
MAX_HAZARDS = 2
HAZARD_ALERT_TILES = 4.0
BEAM_NAMES = {"base": "seed bolt", "ice": "Snare (ice)", "wave": "Echo (wave)"}
# One line of guidance per candidate kind, appended to the game's own label.
RUBRIC = {
    "idle": "Right only when nothing threatens the player and waiting helps.",
    "approach": "Closes distance; right when the target is in sight, reachable and safe to near.",
    "retreat": "Gains distance; right when a threat is close, winding up, or health is low.",
    "shoot": "Right when the target is in line, the crossbow hurts it, and no hit is imminent.",
    "harpoon": "Limited ammo; right for an open boss or an enemy the crossbow cannot hurt.",
    "jump_shoot": "Right for a target too high for a standing shot, when no hit is imminent.",
    "open_boss": "Opens a closed boss shell for the Harpoon; right when the boss is not about to hit.",
    "select_beam": "Right when the equipped bolt cannot hurt or open the target and this one can.",
    "pulse": "Right for a close, level enemy that only the Resonance Pulse hurts.",
    "go_to_refill": "Right when out of Harpoons or low on health and no hit is imminent.",
    "jump_over": "Right when a ground enemy is about to touch the player.",
    "dash_through": "Dashing into a shot deflects it; right when a shot is about to hit.",
    "wall_jump": "Right when clinging to a wall and the way on is upward.",
    "go_to_ambush": "Starts the arena fight, which the goal needs; right unless a hit is imminent.",
    "pick_up": "Right when the area is safe.",
    "go_to_exit": "Leaves the room; right only when nothing here is left to fight.",
    "jump": "Right to clear an obstacle or to break out of a stall.",
}
DANGER_CRITERIA = [
    "low: nothing can hit the player within the next second",
    "medium: a threat is close or winding up, but there is time to react",
    "high: the player will be hit unless the next action avoids it",
]


class JevConfigError(RuntimeError):
    """The backend cannot run (missing key); the message names the variable, never a value."""


@dataclass
class JevConfig:
    base_url: str = DEFAULT_BASE_URL
    model: str = DEFAULT_MODEL
    timeout_ms: int = 800
    min_confidence: float = 0.35
    max_hz: float = 5.0


def api_key_present() -> bool:
    return bool(os.environ.get(KEY_ENV))


def require_key() -> None:
    if not api_key_present():
        raise JevConfigError(
            f"the jev backend needs the environment variable {KEY_ENV} (the user's TypeSafe key)"
        )


def scrub(text: str) -> str:
    """Removes the API key from `text` (a server may echo it) and caps its length."""
    key = os.environ.get(KEY_ENV, "")
    if key:
        text = text.replace(key, "[redacted]")
    return text[:ERROR_TEXT_LIMIT]


def redacted_headers(headers: dict[str, str]) -> dict[str, str]:
    return {
        name: ("Bearer [redacted]" if name.lower() == "authorization" else value)
        for name, value in headers.items()
    }


# --- Request building -------------------------------------------------------------------------


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
    kept = []
    for candidate in candidates:
        kind = candidate.get("kind", "")
        blocked = (
            (kind == "harpoon" and int(kit.get("missiles", 0)) <= 0)
            or (kind in ("shoot", "jump_shoot") and "beam" not in kit.get("abilities", []))
            or (kind == "pulse" and "bombs" not in kit.get("abilities", []))
            or (kind == "dash_through" and not player.get("dash_ready", False))
            or (kind == "wall_jump" and not player.get("on_wall", False))
            or (kind == "jump_over" and not player.get("grounded", False))
        )
        if not blocked or candidate.get("key") == hint:
            kept.append(candidate)
    return kept


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
    return {
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


# --- HTTP -------------------------------------------------------------------------------------


class Client:
    """One keep-alive connection to {base_url}; reconnects after any error. No retries."""

    def __init__(self, base_url: str, timeout_s: float) -> None:
        parts = urlsplit(base_url)
        if parts.scheme not in ("http", "https") or not parts.hostname:
            raise JevConfigError(f"jev base URL must be http(s)://host[:port], got {base_url!r}")
        self._https = parts.scheme == "https"
        self._host = parts.hostname
        self._port = parts.port
        self._prefix = parts.path.rstrip("/")
        self._timeout = timeout_s
        self._connection: http.client.HTTPConnection | None = None
        self.url = f"{base_url.rstrip('/')}{ENDPOINT}"

    def _open(self) -> http.client.HTTPConnection:
        if self._connection is None:
            kind = http.client.HTTPSConnection if self._https else http.client.HTTPConnection
            self._connection = kind(self._host, self._port, timeout=self._timeout)
        return self._connection

    def warm(self) -> None:
        """Opens the connection ahead of the first decision so it does not pay the handshake."""
        try:
            self._open().connect()
        except OSError:
            self.close()

    def close(self) -> None:
        if self._connection is not None:
            self._connection.close()
            self._connection = None

    def post(self, body: bytes) -> tuple[int, dict[str, str], bytes]:
        key = os.environ.get(KEY_ENV)
        if not key:
            raise JevConfigError(f"environment variable {KEY_ENV} is not set")
        connection = self._open()
        try:
            connection.request(
                "POST",
                self._prefix + ENDPOINT,
                body=body,
                headers={
                    "Authorization": f"Bearer {key}",
                    "Content-Type": "application/json",
                    "Accept": "application/json",
                },
            )
            response = connection.getresponse()
            payload = response.read()
        except BaseException:
            self.close()
            raise
        headers = {name.lower(): value for name, value in response.getheaders()}
        if headers.get("connection", "").lower() == "close":
            self.close()
        return response.status, headers, payload


# --- Backend ----------------------------------------------------------------------------------


class JevBackend(Backend):
    """Asks hosted Jev (or any /v1/systemone server) for each decision, at most `max_hz`."""

    name = "jev"

    def __init__(self, config: JevConfig | None = None) -> None:
        self.config = config or JevConfig()
        self.client = Client(self.config.base_url, self.config.timeout_ms / 1000.0)
        self.records: list[dict[str, Any]] = []
        self.request_sample: dict[str, Any] | None = None
        # Set once on a rejection that retrying cannot fix (4xx, missing key); later decisions
        # use the hint without calling. Holds status and a scrubbed message, never the key.
        self.fatal: dict[str, Any] | None = None
        self._last_call_t = -1e9
        self._cooldown_until = 0.0
        self._sent: deque[float] = deque()
        self._last: dict[str, Any] = {}

    def start(self, hello: dict[str, Any]) -> None:
        require_key()
        self.client.warm()

    def close(self, summary: dict[str, Any]) -> None:
        self.client.close()

    def decide(self, state: dict[str, Any], candidates: list[dict[str, Any]], hint: str) -> str:
        record = self._base_record(state, hint)
        skip = self._skip_reason(float(state.get("t", 0.0)))
        if skip is not None or state.get("room") is None:
            record["source"] = skip or "skip:no_room"
            return self._finish(record, hint, state)
        offered = legal(candidates, state, hint)
        record["removed"] = sorted({c["key"] for c in candidates} - {c["key"] for c in offered})
        if len(offered) == 1:
            record["source"] = "skip:single_option"
            return self._finish(record, offered[0]["key"], state)
        request = build_request(self.config.model, state, offered, self._last)
        self._last_call_t = float(state.get("t", 0.0))
        key = self._ask(request, record, {c["key"] for c in offered}, hint)
        return self._finish(record, key, state)

    def _base_record(self, state: dict[str, Any], hint: str) -> dict[str, Any]:
        player = state.get("player") or {}
        enemies = state.get("enemies") or []
        boss = next((enemy for enemy in enemies if enemy.get("is_boss")), None)
        return {
            "tick": state.get("tick"),
            "t": state.get("t"),
            "room": (state.get("room") or {}).get("id"),
            "cell": player.get("cell"),
            "hint": hint,
            "threat": enemies[0]["type"] if enemies else None,
            "boss_attack": (boss.get("attack") or None) if boss else None,
        }

    def _skip_reason(self, game_t: float) -> str | None:
        if self.fatal is not None:
            return "fallback:disabled"
        if game_t - self._last_call_t < 1.0 / self.config.max_hz:
            return "skip:rate"
        now = time.monotonic()
        if now < self._cooldown_until:
            return "fallback:cooldown"
        while self._sent and now - self._sent[0] > 60.0:
            self._sent.popleft()
        if len(self._sent) >= REQUESTS_PER_MINUTE:
            return "fallback:rate_limit"
        return None

    def _ask(self, request: dict, record: dict[str, Any], keys: set[str], hint: str) -> str:
        body = json.dumps(request, separators=(",", ":")).encode("utf-8")
        if self.request_sample is None:
            self.request_sample = {
                "url": self.client.url,
                "headers": redacted_headers(
                    {"Authorization": "", "Content-Type": "application/json"}
                ),
                "body": request,
            }
        self._sent.append(time.monotonic())
        started = time.perf_counter()
        try:
            status, headers, payload = self.client.post(body)
        except JevConfigError as error:
            self.fatal = {"status": None, "message": str(error)}
            return self._fallback(record, "missing_key", hint)
        except TimeoutError:
            return self._fallback(record, "timeout", hint, started)
        except (OSError, http.client.HTTPException) as error:
            record["error"] = scrub(type(error).__name__)
            return self._fallback(record, "network", hint, started)
        record["latency_ms"] = round((time.perf_counter() - started) * 1000.0, 1)
        if status != 200:
            return self._http_error(record, status, headers, payload, hint)
        try:
            answer = json.loads(payload)
            return self._read_answer(answer, record, keys, hint)
        except (ValueError, KeyError, TypeError, AttributeError):
            return self._fallback(record, "bad_response", hint)

    def _http_error(
        self, record: dict, status: int, headers: dict[str, str], payload: bytes, hint: str
    ) -> str:
        message = scrub(payload.decode("utf-8", "replace"))
        record["error"] = f"HTTP {status}: {message}"
        if status in (429, 529):
            try:
                wait = float(headers.get("retry-after", "2"))
            except ValueError:
                wait = 2.0
            self._cooldown_until = time.monotonic() + min(RETRY_AFTER_CAP, max(0.5, wait))
            return self._fallback(record, f"http_{status}", hint)
        if 400 <= status < 500:
            self.fatal = {"status": status, "message": message}
        return self._fallback(record, f"http_{status}", hint)

    def _read_answer(self, answer: dict, record: dict[str, Any], keys: set[str], hint: str) -> str:
        answers = answer["answers"]
        action = answers[QUESTION_ACTION]
        probabilities = {k: round(float(v), 4) for k, v in action["probabilities"].items()}
        choice = action["choice"]
        confidence = float(action.get("confidence", max(probabilities.values())))
        danger = answers.get(QUESTION_DANGER) or {}
        unsure = answers.get(QUESTION_UNSURE) or {}
        usage = answer.get("usage") or {}
        record.update(
            {
                "model": answer.get("model"),
                "choice": choice,
                "confidence": round(confidence, 4),
                "probabilities": probabilities,
                "danger": round(float(danger["score"]), 3) if "score" in danger else None,
                "unsure": round(float(unsure["noul"]), 4) if "noul" in unsure else None,
                "input_tokens": int(usage.get("input_tokens", 0)),
                "output_tokens": int(usage.get("output_tokens", 0)),
            }
        )
        if choice not in keys:
            return self._fallback(record, "bad_choice", hint)
        if confidence < self.config.min_confidence:
            return self._fallback(record, "low_confidence", hint)
        record["source"] = "jev"
        return choice

    def _fallback(
        self, record: dict[str, Any], reason: str, hint: str, started: float | None = None
    ) -> str:
        if started is not None:
            record["latency_ms"] = round((time.perf_counter() - started) * 1000.0, 1)
        record["source"] = f"fallback:{reason}"
        return hint

    def _finish(self, record: dict[str, Any], key: str, state: dict[str, Any]) -> str:
        record["key"] = key
        self.records.append(record)
        # `last_action` for the next request: the kind just chosen plus how far the previous
        # choice moved the player, and a stall flag after three moving choices that went nowhere.
        cell = (state.get("player") or {}).get("cell")
        previous = self._last.get("cell")
        moved = (
            abs(cell[0] - previous[0]) + abs(cell[1] - previous[1]) if cell and previous else None
        )
        stalled = moved == 0 and self._last.get("kind") in MOVING_KINDS
        run = self._last.get("stalled_run", 0) + 1 if stalled else 0
        kind = key.split(":", 1)[0]
        self._last = {
            "cell": cell,
            "kind": kind,
            "stalled": run >= 3,
            "stalled_run": run,
            "summary": kind if moved is None else f"{kind} (previous action moved {moved} tiles)",
        }
        return key
