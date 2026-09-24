# E04 — Combat

**Status:** done

## Goal

Give the player simple ranged combat with two weapons and an initial enemy that teaches a problem the basic weapon cannot solve.

## Why

The crawler should create clear, textless progression: hits, resistance and the correct tool should be communicated through its response in the world.

## Delimitation

- Beam and missile projectiles with shared spawn and hit paths.
- Weapon state and ammunition in the intended autoload.
- Crawler surface tracking, contact and death feedback.
- Beam immunity with ricochet feedback.
- No general player health; it belongs to planned E08.

## Acceptance criteria

- Weapons without unlocked abilities do nothing quietly and safely.
- Beam leaves the crawler alive and provides clear rejection.
- Missiles hit, damage and can kill the crawler.
- The crawler follows the terrain contour without chasing the player.
- Projectiles do not lock player movement, and everything is visible in playtesting.

## Conclusion

[docs/code-contract.md](../code-contract.md) is the normative conclusion for weapons, enemies and collisions.