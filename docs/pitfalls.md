# Hollowtide — traps

These problems have already cost time. Read the reason before changing, not just the rule.

## Graphics post-processing

- **Cause:** The chroma key was using the distance to the magenta background as the opacity at
un-premultiplication. Despill was also applied to the entire picture.
- **Consequence:** Opaque color pixels were treated as partial background; the red channel
was reset and the figure turned green. Despill also ruined correct interior colors.
- **Countermeasure:** Only process semi-transparent border pixels and use alpha as
coverage rate. Follow [asset-contract.md](asset-contract.md).

## Uneven poses in source images

- **Reason:** The poses of the source image were divided into evenly wide columns despite the image model being placed
them at uneven intervals.
- **Consequence:** Legs and feet were cut, or ended up as loose parts in the neighboring box. The
higher resolution made the error more apparent in motion.
- **Countermeasure:** Find actual voids between poses and check each box visually before
imports. Use the layout in [asset-contract.md](asset-contract.md).

## Collision layers are bit masks

- **Cause:** Godot's `collision_layer` was treated as a stock number instead of one
  bitmask.
- **Consequence:** Projectiles and enemies could miss each other even though layers looked correct
in the editor; pickup detection could also be omitted.
- **Countermeasure:** Use the values and relations in [code-contract.md](code-contract.md),
never layer index as a replacement for bitmask value.

## The origin of the TileSet collision

- **Reason:** Collision polygons were written from tile vertices, while Godot measures tile-local
coordinates from the center of the tile.
- **Consequence:** Feet sank below the ground and walls ended up displaced, creating
invisible obstacles. A test with standalone `StaticBody2D` missed the error completely.
- **Countermeasure:** Test the real TileMap collision in playable scene and check
  the origin of the polygon towards [code-contract.md](code-contract.md).

## Hard `preload()` errors

- **Reason:** `preload()` tries to read the resource when the script is parsed.
- **Consequence:** A missing or misspelled asset becomes a parse error and can block the entire game
from starting, even if the function is never used.
- **Countermeasure:** Use `load()` for optional or independently delivered assets and
check the result for null before use.

## Copyright in sound

- **Reason:** An uploader's CC mark does not prove that the uploader owns the composition.
- **Consequence:** A sound track may be illegal to distribute despite an apparently valid one
  license label.
- **Countermeasure:** Create your own material. Capture a mood of your own; never copy existing
melodies or recognizable compositions.

## Metrics do not replace visual inspection

- **Reason:** Previous verification checked dimensions, hash values, or a simplified
test scene but didn't look at the real playing surface.
- **Consequence:** Feet under ground, misplaced walls and weak animation could pass
  numerical controls.
- **Countermeasure:** Run headless check and then do a visual playthrough of affected
scene. See also [asset-contract.md](asset-contract.md).
