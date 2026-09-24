# E02 — Slipstream and first-scene ability gate

**Status:** done

## Goal

Have the player find the orb, transform, and use the transformation to return through a previously unavailable route.

## Why

This is the project's first concrete proof of ability gating: an ability should change an already viewed location, not merely open a new menu or path.

## Delimitation

- Orb pickup with world-based feedback.
- Ability state and transition between standing form and ball form.
- Silent height control when returning to standing form.
- First-stage alcove and low return path.
- No inventory, save or health logic.

## Acceptance criteria

- The player reaches the orb in the left section from the stage's right-side start.
- Contact unlocks ball form without text or a popup.
- Momentum and control remain coherent through the transition.
- Standing form is blocked by the return path while ball form passes through.
- The effect is understandable through space, light and movement alone.

## Conclusion

[docs/code-contract.md](../code-contract.md) is the normative conclusion for ability state and scene connections; movement behavior follows [game-feel.md](../game-feel.md).