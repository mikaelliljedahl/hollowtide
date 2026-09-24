# E06 — Wall jump

**Status:** in progress

## Goal

Add skill-based vertical movement that lets the player climb shafts without making the basic jump arc stronger.

## Why

Wall jumping should reward contact, timing and movement reading. It should feel like a new use of the basic jump, not a separate superpower.

## Delimitation

- Wall contact, sliding, kick-off and brief control protection after kick-off.
- Wall coyote window and repeated use of the same wall.
- Integration with apex hang and existing animation.
- No wall jumping in ball form.
- No new wall-sliding pose until behavior is verified.

## Acceptance criteria

- Jump input near wall contact produces a kick-off without requiring opposite-direction input.
- Sliding occurs only during falls and while the player presses against the wall.
- The same wall can be used repeatedly for climbing.
- Upward movement follows the intent of the basic jump.
- Visual testing shows release from the wall, correct timing and no form collision.

## Conclusion

[docs/game-feel.md](../game-feel.md) is the normative conclusion for wall-jump behavior and constants.