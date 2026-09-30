#!/usr/bin/env python3
"""Jev feedback for the playtest agent (tools/playtest/jev_feedback.py): confusion hotspots, danger
peaks and disagreement from Jev's decisions, and their cross-run aggregate. Run by the
`playtest bridge` suite through tools/check_playtest_bridge.py, which shares `report`."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "playtest"))

import aggregate  # noqa: E402
import jev_feedback  # noqa: E402


def report(boss_outcome: str, stage: int, killer: str, ambush_seconds: float) -> dict:
    return {
        "meta": {"end_reason": "time"},
        "telemetry": {
            "deaths": [{"killer": killer}] if boss_outcome == "died" else [],
            "damage_by_source": {killer: 40},
            "stuck": [{"room": "fringe_03", "cell": [30, 14], "seconds": 6.0}],
            "decisions": {"external": {"fallbacks": {"timeout": 2}}},
            "bosses": [
                {
                    "id": "stone_guardian",
                    "outcome": boss_outcome,
                    "stage_reached": stage,
                    "damage_by_source": {killer: 40},
                }
            ],
            "ambushes": [
                {
                    "id": "fringe_03.ambush.beam_trial",
                    "outcome": "cleared",
                    "seconds": ambush_seconds,
                    "damage_taken": 10,
                }
            ],
        },
    }


class JevFeedbackTest(unittest.TestCase):
    def record(self, t, cell, probabilities, confidence, danger, hint="shoot:e1:forward"):
        choice = max(probabilities, key=probabilities.get)
        return {
            "tick": int(t * 10),
            "t": t,
            "room": "vaults_03",
            "cell": cell,
            "hint": hint,
            "threat": "stone_guardian",
            "boss_attack": "boulder_volley",
            "source": "jev" if confidence >= 0.35 else "fallback:low_confidence",
            "choice": choice,
            "key": choice,
            "confidence": confidence,
            "probabilities": probabilities,
            "danger": danger,
            "latency_ms": 200.0,
            "input_tokens": 1000,
        }

    def test_findings_are_design_actionable(self):
        split = {"retreat": 0.4, "harpoon:e1:forward": 0.35, "idle": 0.25}
        records = [
            self.record(1.0, [12, 9], split, 0.3, 0.2),
            self.record(1.5, [13, 10], split, 0.3, 0.3),
            self.record(4.0, [20, 9], {"shoot:e1:forward": 0.9, "idle": 0.1}, 0.9, 1.9),
            self.record(6.0, [20, 9], {"shoot:e1:forward": 0.9, "idle": 0.1}, 0.9, 1.8),
        ]
        hits = [{"t": 2.0, "source": "stone_guardian:boulder_volley", "amount": 12}]
        summary = jev_feedback.stats(records)
        analysis = jev_feedback.analyze(records, hits, 0.35)
        text = "\n".join(jev_feedback.describe(summary, analysis))
        self.assertIn("Confusion hotspot vaults_03 around cell (13, 10): 2 of 2", text)
        self.assertIn("harpoon vs retreat (2x)", text)
        self.assertIn("Unreadable hits from stone_guardian:boulder_volley: 1 of 1", text)
        self.assertIn("rated danger high 2 times and 2 passed without damage", text)
        self.assertIn("disagreed with the heuristic in 2 of 4", text)
        extra = jev_feedback.derived(summary)
        self.assertEqual((extra["fallback_rate"], extra["mean_latency_ms"]), (0.5, 200.0))
        self.assertAlmostEqual(extra["cost_usd_estimate"], 0.00017)
        merged = aggregate.aggregate(
            [
                dict(report("defeated", 4, "x", 7.0), jev={"stats": summary, "analysis": analysis}),
                dict(report("defeated", 4, "x", 7.0), jev={"stats": summary, "analysis": analysis}),
            ]
        )
        self.assertIn("4 of 4 Jev decisions", "\n".join(merged["jev"]["findings"]))
        self.assertIn("## Jev policy (2 runs)", aggregate.to_markdown(merged))


if __name__ == "__main__":
    unittest.main(verbosity=2)
