#!/usr/bin/env python3
"""Assemble Hollowtide's high-resolution sprite strips without destructive effects.

The generated sources use a flat magenta studio background because the built-in
image generator currently flattens requested transparency.  ``chroma_matte``
turns colour distance into a continuous alpha value and mathematically removes
the magenta spill.  It never creates a binary alpha mask.  The only resampling
is a direct, Lanczos-quality resize from the larger source to the contracted
final size; there is no palette conversion or intermediate down/up-sampling.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tools" / "source_art"
DEST = ROOT / "assets" / "sprites"
MAGENTA = (255, 0, 255)


def smoothstep(lo: float, hi: float, value: float) -> float:
    value = min(1.0, max(0.0, (value - lo) / (hi - lo)))
    return value * value * (3.0 - 2.0 * value)


def chroma_matte(image: Image.Image, background: tuple[int, int, int] = MAGENTA) -> Image.Image:
    """Return a spill-free RGBA cutout with a continuous, antialiased matte."""
    src = image.convert("RGB")
    br, bg, bb = (component / 255.0 for component in background)
    output: list[tuple[int, int, int, int]] = []
    for red8, green8, blue8 in src.get_flattened_data():
        red, green, blue = red8 / 255.0, green8 / 255.0, blue8 / 255.0
        # Maximum channel distance gives an exact coverage estimate for a solid
        # chroma backdrop while retaining fractional coverage at painted edges.
        raw = max(abs(red - br), abs(green - bg), abs(blue - bb))
        alpha = smoothstep(0.012, 0.16, raw)
        if alpha <= 0.0:
            output.append((0, 0, 0, 0))
            continue
        # Undo C = alpha*foreground + (1-alpha)*background.
        #
        # Koefficienten MÅSTE vara alfa, inte `raw`. `raw` är ett AVSTÅNDSMÅTT
        # från bakgrundsfärgen, inte en täckningsgrad: en helt ogenomskinlig blå
        # pixel rgb(74,91,129) ligger 0.71 från magenta, och med raw som
        # koefficient behandlas den som 29 % bakgrund. Då subtraheras en
        # magentaandel som aldrig fanns där, rödkanalen nollas och figuren blir
        # grön. Med alfa blir inre pixlar coverage = 1, uttrycket blir identitet,
        # och de kopieras oförändrade — bara halvgenomskinliga kantpixlar
        # dekontamineras, vilket är hela poängen.
        coverage = max(alpha, 1.0 / 255.0)
        foreground = (
            (red - (1.0 - coverage) * br) / coverage,
            (green - (1.0 - coverage) * bg) / coverage,
            (blue - (1.0 - coverage) * bb) / coverage,
        )
        output.append(tuple(round(255 * min(1.0, max(0.0, c))) for c in foreground) + (round(alpha * 255),))
    result = Image.new("RGBA", src.size)
    result.putdata(output)
    return despill_edges(result)


def despill_edges(image: Image.Image, cutoff: int = 250) -> Image.Image:
    """Ta bort magentaspill ur HALVGENOMSKINLIGA kantpixlar — och bara dem.

    Med en enda chroma-bakgrund är alfa matematiskt underbestämt för färger som
    liknar bakgrunden, så un-premultipliceringen ensam lämnar kvar en lila frans
    på kanterna. Detta steg drar ner R och B mot G där magenta dominerar.

    Cutoffen är hela poängen: pixlar med alfa >= cutoff räknas som inre och rörs
    ALDRIG. Att despilla hela bilden nollställer rödkanalen och gör figuren grön,
    vilket är exakt det fel som uppstod tidigare.
    """
    px = image.load()
    width, height = image.size
    for y in range(height):
        for x in range(width):
            red, green, blue, alpha = px[x, y]
            if alpha == 0:
                continue
            # Nyckeln lämnar ett nästan osynligt dis (alfa 1-10) över stora ytor
            # som läser som en ljus rektangel runt figuren mot mörk bakgrund.
            # Det är brus från nyckeln, inte bildinnehåll.
            if alpha < 12:
                px[x, y] = (0, 0, 0, 0)
                continue
            if alpha >= cutoff:
                continue
            spill = min(red, blue) - green
            if spill > 0:
                px[x, y] = (max(0, red - spill), green, max(0, blue - spill), alpha)
    return image


@dataclass
class _Component:
    area: int
    bbox: tuple[int, int, int, int]
    pixels: list[tuple[int, int]]


def _connected_components(alpha: Image.Image, threshold: int):
    """Find artwork components without changing source pixels."""
    width, height = alpha.size
    values = alpha.load()
    seen = bytearray(width * height)
    result: list[_Component] = []

    for y in range(height):
        for x in range(width):
            index = y * width + x
            if seen[index] or values[x, y] < threshold:
                continue
            seen[index] = 1
            pending = [(x, y)]
            pixels: list[tuple[int, int]] = []
            left = right = x
            top = bottom = y
            while pending:
                current_x, current_y = pending.pop()
                pixels.append((current_x, current_y))
                left = min(left, current_x)
                right = max(right, current_x)
                top = min(top, current_y)
                bottom = max(bottom, current_y)
                for next_x, next_y in (
                    (current_x - 1, current_y - 1),
                    (current_x, current_y - 1),
                    (current_x + 1, current_y - 1),
                    (current_x - 1, current_y),
                    (current_x + 1, current_y),
                    (current_x - 1, current_y + 1),
                    (current_x, current_y + 1),
                    (current_x + 1, current_y + 1),
                ):
                    if not (0 <= next_x < width and 0 <= next_y < height):
                        continue
                    next_index = next_y * width + next_x
                    if not seen[next_index] and values[next_x, next_y] >= threshold:
                        seen[next_index] = 1
                        pending.append((next_x, next_y))
            result.append(_Component(len(pixels), (left, top, right + 1, bottom + 1), pixels))
    return result


def _bbox_distance(first: tuple[int, int, int, int], second: tuple[int, int, int, int]):
    first_left, first_top, first_right, first_bottom = first
    second_left, second_top, second_right, second_bottom = second
    horizontal = max(first_left - second_right, second_left - first_right, 0)
    vertical = max(first_top - second_bottom, second_top - first_bottom, 0)
    return (horizontal * horizontal + vertical * vertical) ** 0.5


def source_cells(name: str, count: int) -> list[Image.Image]:
    image = Image.open(SOURCE / name).convert("RGB")
    # GPT Image occasionally leaves a few non-background pixels on the outer
    # canvas boundary.  Removing only that empty studio margin prevents it from
    # affecting object bounds; no artwork reaches this margin.
    image = image.crop((8, 8, image.width - 8, image.height - 8))
    matte = chroma_matte(image)

    # Poses do not always have an empty x-column between them: an outstretched
    # leg can pass under the next pose.  Equal-width slicing then cuts that leg
    # in half.  Instead, use large connected components as pose anchors.  This
    # also handles round, tightly packed ball frames, where projection gaps are
    # unreliable.  Threshold 32 keeps solid artwork while excluding chroma-key
    # noise and tiny antialiased details that must not become pose anchors.
    alpha = matte.getchannel("A")
    components = _connected_components(alpha, 32)
    anchors = sorted(components, key=lambda component: component.area, reverse=True)[:count]
    if len(anchors) != count:
        raise ValueError(f"{name}: found {len(anchors)} pose anchors, expected {count}")
    anchors.sort(key=lambda component: (component.bbox[0] + component.bbox[2]) / 2)

    # Keep nearby disconnected details (hair wisps, soles, orb sparks) with
    # their nearest anchor, but reject isolated studio specks.  Pixels below
    # the anchor threshold are attached only within a narrow edge radius, so
    # fractional antialiasing survives without recreating a noisy backdrop.
    assignments: list[list[tuple[int, int]]] = [[] for _ in anchors]
    anchor_indexes = {id(anchor): index for index, anchor in enumerate(anchors)}
    for component in components:
        anchor_index = anchor_indexes.get(id(component))
        if anchor_index is None:
            distances = [_bbox_distance(component.bbox, anchor.bbox) for anchor in anchors]
            anchor_index = min(range(count), key=distances.__getitem__)
            if distances[anchor_index] > 48:
                continue
        assignments[anchor_index].extend(component.pixels)

    values = alpha.load()
    width, height = matte.size
    for y in range(height):
        for x in range(width):
            value = values[x, y]
            if value == 0 or value >= 32:
                continue
            distances = []
            for anchor in anchors:
                left, top, right, bottom = anchor.bbox
                horizontal = max(left - x, x - right + 1, 0)
                vertical = max(top - y, y - bottom + 1, 0)
                distances.append(horizontal * horizontal + vertical * vertical)
            anchor_index = min(range(count), key=distances.__getitem__)
            if distances[anchor_index] <= 8 * 8:
                assignments[anchor_index].append((x, y))

    # Build masked cells instead of x-crops.  A cell receives only pixels
    # assigned to its anchor, so overlapping silhouettes cannot leak a foot or
    # another limb into a neighbour's frame.
    cells: list[Image.Image] = []
    source_values = matte.load()
    pad = 4
    for points in assignments:
        if not points:
            raise ValueError(f"{name}: pose anchor has no assigned pixels")
        left = min(x for x, _ in points)
        top = min(y for _, y in points)
        right = max(x for x, _ in points) + 1
        bottom = max(y for _, y in points) + 1
        cell = Image.new("RGBA", (right - left, bottom - top), (0, 0, 0, 0))
        cell_values = cell.load()
        # Copy RGBA values directly; alpha and colour must remain those
        # produced by chroma_matte, including all fractional edge coverage.
        for x, y in points:
            cell_values[x - left, y - top] = source_values[x, y]
        full = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        full.alpha_composite(cell, (left, top))
        cells.append(full.crop((max(0, left - pad), 0, min(width, right + pad), height)))
    return cells


def visible_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    # A low cutoff is used only to locate the crop; it does not alter the alpha
    # channel.  This ignores imperceptible generator noise in the flat backdrop
    # while every retained edge pixel keeps its original fractional coverage.
    box = image.getchannel("A").point(lambda alpha: 255 if alpha >= 192 else 0).getbbox()
    if box is None:
        raise ValueError("source cell has no visible artwork")
    return box


def fit(
    image: Image.Image,
    max_width: int,
    max_height: int,
    *,
    scale: float | None = None,
) -> Image.Image:
    art = image.crop(visible_bbox(image))
    if scale is None:
        scale = min(max_width / art.width, max_height / art.height)
    size = (max(1, round(art.width * scale)), max(1, round(art.height * scale)))
    return art.resize(size, Image.Resampling.LANCZOS)


def shared_scale(
    cells: Iterable[Image.Image],
    target_height: int,
    *,
    max_width: int | None = None,
):
    boxes = [visible_bbox(cell) for cell in cells]
    heights = [bottom - top for _, top, _, bottom in boxes]
    scale = target_height / max(heights)
    if max_width is not None:
        widths = [right - left for left, _, right, _ in boxes]
        scale = min(scale, max_width / max(widths))
    return scale


def frame(art: Image.Image, size: tuple[int, int], *, bottom: int | None = None) -> Image.Image:
    result = Image.new("RGBA", size, (0, 0, 0, 0))
    x = (size[0] - art.width) // 2
    y = (size[1] - art.height) // 2 if bottom is None else bottom - art.height + 1
    result.alpha_composite(art, (x, y))
    return result


def strip(frames: Iterable[Image.Image]) -> Image.Image:
    items = list(frames)
    result = Image.new("RGBA", (sum(item.width for item in items), items[0].height), (0, 0, 0, 0))
    x = 0
    for item in items:
        result.alpha_composite(item, (x, 0))
        x += item.width
    return result


def player_strip(source_name: str, count: int) -> Image.Image:
    cells = source_cells(source_name, count)
    # Scale from tallest source pose only.  A wide pose is allowed to overflow
    # its 256 px frame; it must never receive a second, non-uniform scale.
    scale = shared_scale(cells, 192)
    arts = [fit(cell, 256, 192, scale=scale) for cell in cells]
    return strip(frame(art, (256, 256), bottom=240) for art in arts)


def object_strip(source_name: str, count: int, frame_size: tuple[int, int], art_box: tuple[int, int]) -> Image.Image:
    cells = source_cells(source_name, count)
    # Keep one aspect-preserving scale for all poses.  art_box remains shared
    # strip budget, never an excuse to rescale an individual frame.
    scale = shared_scale(cells, art_box[1], max_width=art_box[0])
    arts = [fit(cell, *art_box, scale=scale) for cell in cells]
    return strip(frame(art, frame_size) for art in arts)


def tileset() -> Image.Image:
    source = Image.open(SOURCE / "tileset_cave_hd.png").convert("RGB")
    xs = [round(i * source.width / 4) for i in range(5)]
    ys = [round(i * source.height / 3) for i in range(4)]
    cells = [[source.crop((xs[x], ys[y], xs[x + 1], ys[y + 1])) for x in range(4)] for y in range(3)]
    atlas = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    for y in range(3):
        for x in range(4):
            tile = cells[y][x].resize((64, 64), Image.Resampling.LANCZOS).convert("RGBA")
            # Edge/corner cells contain open cave space.  Key that space with a
            # continuous dark-background matte so rock silhouettes retain soft
            # antialiased edges; filled variants remain completely solid.
            if (x, y) in {(1, 0), (2, 0), (3, 0), (0, 1), (1, 1), (2, 1)}:
                sample_xy = {
                    (1, 0): (32, 52), (2, 0): (46, 42), (3, 0): (18, 42),
                    (0, 1): (45, 30), (1, 1): (32, 15), (2, 1): (18, 30),
                }[(x, y)]
                bg = tile.convert("RGB").getpixel(sample_xy)
                tile = chroma_matte(tile, bg)
            atlas.alpha_composite(tile, (x * 64, y * 64))
    return atlas


def save(image: Image.Image, name: str) -> None:
    DEST.mkdir(parents=True, exist_ok=True)
    path = DEST / name
    image.save(path, "PNG", optimize=False, compress_level=9)
    print(f"wrote {path.relative_to(ROOT)} {image.width}x{image.height}")


def main() -> None:
    save(player_strip("player_idle_hd.png", 4), "player_idle.png")
    save(player_strip("player_run_hd.png", 8), "player_run.png")
    save(player_strip("player_jump_hd.png", 3), "player_jump.png")
    save(player_strip("player_idle_armed_hd.png", 4), "player_idle_armed.png")
    save(player_strip("player_run_armed_hd.png", 8), "player_run_armed.png")
    save(player_strip("player_jump_armed_hd.png", 3), "player_jump_armed.png")
    save(player_strip("player_aim_up_hd.png", 1), "player_aim_up.png")
    save(player_strip("player_aim_diag_up_hd.png", 1), "player_aim_diag_up.png")
    save(player_strip("player_aim_diag_down_hd.png", 1), "player_aim_diag_down.png")
    save(player_strip("player_aim_down_hd.png", 1), "player_aim_down.png")
    save(object_strip("orb_hd.png", 6, (128, 128), (88, 80)), "orb.png")
    save(tileset(), "tileset_cave.png")
    save(object_strip("weapon_pickup_hd.png", 6, (128, 128), (88, 80)), "weapon_pickup.png")
    save(object_strip("beam_shot_hd.png", 4, (64, 32), (60, 26)), "beam_shot.png")
    save(object_strip("crawler_hd.png", 8, (128, 128), (116, 64)), "crawler.png")


if __name__ == "__main__":
    main()
