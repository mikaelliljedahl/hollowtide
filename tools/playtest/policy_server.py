"""Out-of-process policy server for the Hollowtide playtest agent.

The game connects to 127.0.0.1 as a TCP client and speaks line-delimited JSON (one UTF-8 object per
line); the wire format is documented in docs/features/playtest-agent.md ("Wire format"). A backend
turns (state, candidates, hint) into one candidate key. Standard library only.
"""

from __future__ import annotations

import json
import socket
import threading
from dataclasses import dataclass, field
from typing import Any

PROTOCOL = 1
HOST = "127.0.0.1"


class Backend:
    """Chooses one candidate key per decision. Subclass and register in BACKENDS."""

    name = "base"

    def start(self, hello: dict[str, Any]) -> None:
        """Called once with the game's hello message (run_id, room, protocol)."""

    def decide(self, state: dict[str, Any], candidates: list[dict[str, Any]], hint: str) -> str:
        raise NotImplementedError

    def close(self, summary: dict[str, Any]) -> None:
        """Called once with the game's bye summary (end_reason, seconds)."""


class HeuristicPassthrough(Backend):
    """Returns the game's own heuristic choice (the `hint`); proves the bridge end to end."""

    name = "passthrough"

    def decide(self, state: dict[str, Any], candidates: list[dict[str, Any]], hint: str) -> str:
        return hint


# Backends that need no configuration. The jev backend (tools/playtest/jev_backend.py) takes its
# settings from the runner's --jev-* flags and is built there.
BACKENDS: dict[str, type[Backend]] = {HeuristicPassthrough.name: HeuristicPassthrough}


@dataclass
class ServerStats:
    decisions: int = 0
    backend_errors: list[str] = field(default_factory=list)
    hello: dict[str, Any] = field(default_factory=dict)
    bye: dict[str, Any] = field(default_factory=dict)


class PolicyServer:
    """Serves one game connection with `backend` on a background thread."""

    def __init__(self, backend: Backend, port: int = 0, accept_timeout: float = 60.0) -> None:
        self.backend = backend
        self.stats = ServerStats()
        self._listener = socket.create_server((HOST, port))
        self._listener.settimeout(accept_timeout)
        self.port: int = self._listener.getsockname()[1]
        self._thread = threading.Thread(target=self._serve, daemon=True)

    def start(self) -> PolicyServer:
        self._thread.start()
        return self

    def join(self, timeout: float | None = None) -> None:
        self._thread.join(timeout)
        self._listener.close()

    def _serve(self) -> None:
        try:
            connection, _address = self._listener.accept()
        except OSError:
            return
        with connection, connection.makefile("rwb") as stream:
            for raw in stream:
                message = json.loads(raw.decode("utf-8"))
                reply = self.handle(message)
                if reply is not None:
                    stream.write((json.dumps(reply) + "\n").encode("utf-8"))
                    stream.flush()
                if message.get("type") == "bye":
                    return

    def handle(self, message: dict[str, Any]) -> dict[str, Any] | None:
        """Answers one game message; returns the reply to send, or None."""
        kind = message.get("type")
        if kind == "hello":
            self.stats.hello = message
            self._guard(lambda: self.backend.start(message))
            return None
        if kind == "bye":
            self.stats.bye = message.get("summary", {})
            self._guard(lambda: self.backend.close(self.stats.bye))
            return None
        if kind != "decide":
            return None
        self.stats.decisions += 1
        key = self._guard(
            lambda: self.backend.decide(message["state"], message["candidates"], message["hint"])
        )
        # A null key makes the game fall back to its heuristic at once and count "bad_reply".
        return {"type": "action", "tick": message["tick"], "key": key}

    def _guard(self, call: Any) -> Any:
        try:
            return call()
        except Exception as error:  # A backend failure must not kill the run; it is reported.
            if len(self.stats.backend_errors) < 20:
                self.stats.backend_errors.append(f"{type(error).__name__}: {error}")
            return None
