# E01 — Movement and game feel

**Status:** done

## Goal

Give the player a stable and responsive movement base for all subsequent exploration.

## Why

Hollowtide is built on precision, momentum and revisits. Content must not conceal movement that feels wrong.

## Delimitation

- Standing movement, turning, air control and jumping.
- Variable jump height, jump buffering, coyote time and soft apex control.
- Player-oriented camera and defined inputs.
- No wall-jump logic; it belongs to E06.
- No slipstream or health logic; those belong to separate epics.

## Acceptance criteria

- Player movement follows [game-feel.md](../game-feel.md) without local deviations.
- All movement and collision movement takes place in the physics loop.
- Jump works from the ground, after a short ground miss and before landing.
- Visual testing shows stable feet, terrain contact and a camera without obvious jerks.

## Conclusion

[docs/game-feel.md](../game-feel.md) is the normative conclusion for movement behavior and feel.