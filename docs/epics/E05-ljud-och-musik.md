# E05 — Sound and music

**Status:** done

## Goal

Create a restrained sound layer that reinforces cave isolation and makes important game events audible without placing text over the world.

## Why

Sound should give weight to jumps, hits and ability gains while holding the room together when the image is dark and sparse.

## Delimitation

- Original cave music with looping.
- Movement, weapon, hit, pickup and Slipstream sound effects.
- Runtime loading, separate music and effects buses, and overlapping effects.
- No reuse of protected melodies, samples or recognizable themes.

## Acceptance criteria

- Music starts when the scene becomes active and loops without an audible interruption.
- Events provide appropriate feedback even when several effects overlap.
- Missing audio resources do not stop the game.
- Material is original and does not depend on an uploader's unverified license label.
- Sound balance is verified in the actual scene, not only through file metadata.

## Conclusion

[docs/code-contract.md](../code-contract.md) is the normative conclusion for ownership and runtime integration; [pitfalls.md](../pitfalls.md) controls copyright risk.