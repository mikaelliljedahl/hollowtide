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

from jev_feedback import PRICE_PER_INPUT_TOKEN
from jev_request import QUESTION_ACTION, QUESTION_DANGER, QUESTION_UNSURE, build_request, legal
from policy_server import Backend

KEY_ENV = "TYPESAFE_API_KEY"
BASE_URL_ENV = "TYPESAFE_BASE_URL"
DEFAULT_BASE_URL = "https://api.typesafe.ai"
# Pinned: the API accepted it, and jev-latest answered as jev-1.13.0 (checked 2026-09-24).
DEFAULT_MODEL = "jev-1.13.0"
ENDPOINT = "/v1/systemone"
REQUESTS_PER_MINUTE = 1200
ERROR_TEXT_LIMIT = 300
RETRY_AFTER_CAP = 10.0
# Backoff after a transient failure (502/503/504, timeout, network), in game seconds: doubles per
# failure in a row from 1 s up to this cap, and resets on an answer. r10 sent 634 requests into a
# seven-minute "no healthy upstream" outage, one per decision.
TRANSIENT_STATUSES = (502, 503, 504)
BACKOFF_CAP = 15.0
MOVING_KINDS = (
    "approach",
    "go_to_exit",
    "go_to_ambush",
    "pick_up",
    "jump",
    "go_to_refill",
    "go_to_objective",
    "go_to_door",
)


class JevConfigError(RuntimeError):
    """The backend cannot run (missing key); the message names the variable, never a value."""


@dataclass
class JevConfig:
    base_url: str = DEFAULT_BASE_URL
    model: str = DEFAULT_MODEL
    timeout_ms: int = 800
    min_confidence: float = 0.35
    max_hz: float = 5.0
    # Estimated spend (input tokens at the published price) after which the hint is played.
    budget_usd: float | None = None


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
        # Game time (state["t"]) before which no request is sent. Game time, not wall time: the
        # headless game runs as fast as the policy answers, so a 10 s wall-clock cooldown after a
        # 529 cost r10-run1 120-200 game seconds of play (1363 of 2549 decisions).
        self._cooldown_until_t = 0.0
        self._failures = 0
        self._sent: deque[float] = deque()
        self._last: dict[str, Any] = {}
        self._input_tokens = 0
        # Jev's last answered key, repeated on rate skips while it is offered.
        self._intent = ""

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
            # Between calls Jev's last answer is kept while it is still offered: playing the
            # heuristic's hint here made the two alternate (route one step, arena the next).
            keys = {c["key"] for c in legal(candidates, state, hint)}
            if skip == "skip:rate" and self._intent in keys:
                record["held"] = True
                return self._finish(record, self._intent, state)
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
        budget = self.config.budget_usd
        if budget is not None and self._input_tokens * PRICE_PER_INPUT_TOKEN >= budget:
            return "skip:budget"
        if game_t < self._cooldown_until_t:
            return "fallback:cooldown"
        now = time.monotonic()
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
            self._back_off(record)
            return self._fallback(record, "timeout", hint, started)
        except (OSError, http.client.HTTPException) as error:
            record["error"] = scrub(type(error).__name__)
            self._back_off(record)
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
            self._cool_down(record, min(RETRY_AFTER_CAP, max(0.5, wait)))
            return self._fallback(record, f"http_{status}", hint)
        if status in TRANSIENT_STATUSES:
            self._back_off(record)
            return self._fallback(record, f"http_{status}", hint)
        if 400 <= status < 500:
            self.fatal = {"status": status, "message": message}
        return self._fallback(record, f"http_{status}", hint)

    def _cool_down(self, record: dict[str, Any], seconds: float) -> None:
        """No request for `seconds` of game time from this decision's."""
        self._cooldown_until_t = float(record.get("t") or 0.0) + seconds
        record["cooldown_s"] = round(seconds, 2)

    def _back_off(self, record: dict[str, Any]) -> None:
        self._failures += 1
        self._cool_down(record, min(BACKOFF_CAP, 2.0 ** (self._failures - 1)))

    def _read_answer(self, answer: dict, record: dict[str, Any], keys: set[str], hint: str) -> str:
        answers = answer["answers"]
        self._failures = 0
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
        self._input_tokens += record["input_tokens"]
        if choice not in keys:
            return self._fallback(record, "bad_choice", hint)
        if confidence < self.config.min_confidence:
            return self._fallback(record, "low_confidence", hint)
        record["source"] = "jev"
        self._intent = choice
        return choice

    def _fallback(
        self, record: dict[str, Any], reason: str, hint: str, started: float | None = None
    ) -> str:
        if started is not None:
            record["latency_ms"] = round((time.perf_counter() - started) * 1000.0, 1)
        record["source"] = f"fallback:{reason}"
        self._intent = ""
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
