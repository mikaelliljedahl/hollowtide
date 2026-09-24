# E07 — Level design: scene 1 feasibility

**Status:** in progress

## Goal

Make the first cave a coherent, visually comprehensible playthrough from start to finish, including the first combat encounter.

## Why

The stage integrates movement, graphics, ability gating, sound and combat. It must teach through placement and contrast, not instructions.

## Delimitation

- Start in the right section, walk toward the left alcove and return.
- Orb, low passage, weapon pickup and crawler in a clear order.
- Terrain collision, camera borders, lighting and sound to support readability.
- No HUD, tutorial text or extra rooms.

## Acceptance criteria

- A player can complete the entire flow without editor assistance or text instructions.
- The orb is marked, unlocks the correct ability and the return path confirms its benefit.
- Weapon pickup and crawler are reached after the return path and can be tested there.
- TileSet visuals and TileSet collision coincide throughout the playable stretch.
- The full scene is visually verified with sound, effects and camera active.

## Conclusion

[docs/code-contract.md](../code-contract.md) is the normative conclusion for scene structure and coupling; [game-feel.md](../game-feel.md) governs the player experience.