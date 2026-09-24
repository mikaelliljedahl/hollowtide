# E03 — Graphics pipeline

**Status:** done

## Goal

Deliver consistent gameplay graphics from high-resolution source images without post-processing that damages color, edges or pose separation.

## Why

Graphics should carry the atmosphere and withstand scrutiny at the actual game resolution. Pipeline failures become visible in every scene and are expensive to repair after import.

## Delimitation

- Source images for protagonist, ball, orb, environment, weapon and crawler.
- Deterministic cropping, edge processing, scaling and strip construction.
- Tile set with continuous edge pieces and variation in filled stone.
- No game code, level logic or palette post-quantization.

## Acceptance criteria

- The generator can be rerun and produces identical deliveries.
- Source poses are split at actual intervals, not assumed equal columns.
- Transparency and colors read cleanly against the game background.
- Every delivered frame is visually checked, including the running cycle and edges.
- Paths and image layout follow [asset-contract.md](../asset-contract.md).

## Conclusion

[docs/asset-contract.md](../asset-contract.md) is the normative conclusion for graphics format and layout.