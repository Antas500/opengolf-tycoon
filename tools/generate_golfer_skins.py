#!/usr/bin/env python3
"""Write the part layers for the golfer art, and the skin catalogue.

The game ships two hand-made golfer skins - Weekend Beginner and Club Casual.
Their frames were drawn by hand rather than by this tool, so they carry no
record of which body part each pixel belongs to. This tool authors that record
and writes it beside every frame:

  assets/sprites/golfer/<id>/animations/<anim>/<dir>/frame_NNN.layer.bin

A *part layer* is one byte per pixel of the 48x48 canvas - the part the artist
drew that pixel as, and in which of the five shades. It is what lets the game
re-colour "the trousers" without guessing from colours: a pixel changes colour
only when the part the layer names is the one the player changed (see
``GolferSkinLibrary``, which reads the very same bytes).

The layer is worked out from the art itself, using the key of tones and figure
bands in ``CASUAL_ART`` / ``BEGINNER_ART`` below, and the tool finishes by
writing ``data/golfer_skins.json``: the catalogue of skins the game ships.

Run from the repository root:

    python3 tools/generate_golfer_skins.py

The output is deterministic, so re-running the tool after an art or key tweak
shows up as a plain diff of ``.layer.bin`` files and the JSON.
"""

from __future__ import annotations

import json
import os
import struct
import sys
import zlib
from dataclasses import dataclass, field


# ---------------------------------------------------------------------------
# Frame layout
# ---------------------------------------------------------------------------

DIRECTIONS = [
    "south", "south-east", "east", "north-east",
    "north", "north-west", "west", "south-west",
]

ANIM_FRAMES = {"idle": 4, "walk": 4, "swing": 6}


# ---------------------------------------------------------------------------
# Part layers
# ---------------------------------------------------------------------------
# Every sprite ships with a *part layer*: one byte per pixel of the 48x48
# canvas saying which body part that pixel was drawn as, and in which of the
# artist's five shades. The game re-colours a skin by walking this layer, so a
# pixel only ever changes colour when the part it belongs to is one the player
# changed - the eyes, the highlights and any pixel the layer marks 0 are left
# exactly as they were drawn.
#
# The byte is the same value the Skin Designer stores for a painted pixel
# (see GolferSkinLibrary.pixel_index):
#
#     0                      no part - never re-coloured (also: transparent)
#     1 + part_index * 5 + shade
#
# The file lives beside the sprite it describes - ``frame_000.png`` has a
# ``frame_000.layer.bin`` - deflated, so the 224 layers of the two looks come
# to about 45 KB rather than half a megabyte.

PART_ORDER = ["shirt", "pants", "cap", "hair", "skin", "shoes", "accent", "gear",
              "eye", "shine"]
SHADE_COUNT = 5
LAYER_SUFFIX = ".layer.bin"


def layer_index(part: str, shade: int) -> int:
    """The stored byte for one part/shade pair (0 = no part)."""
    if part not in PART_ORDER:
        return 0
    return 1 + PART_ORDER.index(part) * SHADE_COUNT + max(0, min(SHADE_COUNT - 1, shade))


def write_layer(path: str, layer: bytes) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(zlib.compress(bytes(layer), 9))


def read_png(path: str) -> list[list[tuple[int, int, int, int]]]:
    """Read the hand-made art back in: 8-bit RGB or RGBA, no interlace (what
    the artists and every earlier version of this tool wrote)."""
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("%s is not a PNG" % path)
    pos = 8
    idat = b""
    width = height = depth = colour_type = 0
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        payload = data[pos + 8:pos + 8 + length]
        pos += length + 12
        if kind == b"IHDR":
            width, height, depth, colour_type, _, _, interlace = struct.unpack(">IIBBBBB", payload)
            if depth != 8 or interlace != 0 or colour_type not in (2, 6):
                raise ValueError("%s: unsupported PNG (depth %d, colour type %d, interlace %d)"
                                 % (path, depth, colour_type, interlace))
        elif kind == b"IDAT":
            idat += payload
        elif kind == b"IEND":
            break
    channels = 4 if colour_type == 6 else 3
    stride = width * channels
    raw = zlib.decompress(idat)
    rows: list[bytearray] = []
    previous = bytearray(stride)
    at = 0
    for _ in range(height):
        filter_type = raw[at]
        line = bytearray(raw[at + 1:at + 1 + stride])
        at += stride + 1
        for i in range(stride):
            left = line[i - channels] if i >= channels else 0
            up = previous[i]
            up_left = previous[i - channels] if i >= channels else 0
            if filter_type == 1:
                line[i] = (line[i] + left) & 0xFF
            elif filter_type == 2:
                line[i] = (line[i] + up) & 0xFF
            elif filter_type == 3:
                line[i] = (line[i] + (left + up) // 2) & 0xFF
            elif filter_type == 4:
                estimate = left + up - up_left
                pa, pb, pc = abs(estimate - left), abs(estimate - up), abs(estimate - up_left)
                predictor = left if (pa <= pb and pa <= pc) else (up if pb <= pc else up_left)
                line[i] = (line[i] + predictor) & 0xFF
        rows.append(line)
        previous = line
    pixels: list[list[tuple[int, int, int, int]]] = []
    for line in rows:
        row: list[tuple[int, int, int, int]] = []
        for x in range(width):
            if colour_type == 6:
                row.append((line[x * 4], line[x * 4 + 1], line[x * 4 + 2], line[x * 4 + 3]))
            else:
                row.append((line[x * 3], line[x * 3 + 1], line[x * 3 + 2], 255))
        pixels.append(row)
    return pixels

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------


def rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16))


def mix(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def ramp(base_hex: str) -> list[tuple[int, int, int]]:
    """base, light, dark, outline (the outline keeps a fifth stop for parts
    that need an extra level of shading)."""
    base = rgb(base_hex)
    return [
        base,
        mix(base, (255, 255, 255), 0.24),
        mix(base, (10, 8, 12), 0.30),
        mix(base, (6, 6, 10), 0.62),
        mix(base, (255, 255, 255), 0.42),
    ]


# ---------------------------------------------------------------------------
# Parts
# ---------------------------------------------------------------------------

CUSTOM_PARTS = ["shirt", "pants", "cap", "hair", "skin", "shoes", "accent", "gear"]

PART_LABELS = {
    "shirt": "Top",
    "pants": "Trousers",
    "cap": "Headwear",
    "hair": "Hair / beard",
    "skin": "Skin",
    "shoes": "Footwear",
    "accent": "Trim",
    "gear": "Equipment",
    "eye": "Eyes",
    "shine": "Highlights",
}


# ---------------------------------------------------------------------------
# Part layers for the hand-made tier art
# ---------------------------------------------------------------------------
# The tier looks the game shipped with were not drawn by this tool, so their
# pixels carry no parts. Their layers are authored here instead, as a *key*:
# the colours the artist actually drew each part in, plus - for the handful of
# tones shared between two parts (the same dark outline runs under the chin and
# along the soles) - the band of the figure the pixel has to sit in to belong to
# one or the other.
#
# Every key colour is tagged with its part; a pixel whose colour is not in the
# table (the artist's blends, a stray shade) takes the part of the nearest key
# colour, so the layer always covers the whole figure. The shade is the ramp
# stop closest to the tone the pixel was drawn in, which is what keeps the
# art's light and dark sides apart once the player changes a colour.
#
# The layer is written beside every frame of the art, exactly like the drawn
# skins: ``frame_000.png`` gets a ``frame_000.layer.bin``.


@dataclass
class LegacyArt:
    id: str
    name: str
    description: str
    root: str                       # res:// folder holding the art
    spawn_tiers: list[str]
    palette: dict[str, str]         # part -> the colour the art was drawn in
    # "#rrggbb" -> the part that tone belongs to. Every tone the artist drew the
    # figure in is listed; anything else takes the part of the nearest tone, so
    # the layer always covers the whole figure.
    keys: dict[str, str]
    # The bands of the figure, top down, as a fraction of the drawn figure's
    # height: (where the band starts, its name).
    regions: list[tuple[float, str]]
    # Band -> {part as keyed above: the part a pixel in this band really is}.
    # The artist re-used one tone for several parts - the same dark brown is the
    # hair's outline, the shirt's creases and the belt - so a shared tone is
    # told apart by the band of the figure the pixel sits in.
    region_parts: dict[str, dict[str, str]] = field(default_factory=dict)
    # The pupils are drawn in the hair's outline tone (Club Casual) and have to
    # be found by eye instead: a dark pixel inside the face is an eye.
    pupils: bool = False
    parts: list[str] = field(default_factory=lambda: list(CUSTOM_PARTS))

    def region_for(self, y_fraction: float, keys: dict[str, str]) -> str:
        name = self.regions[0][1] if self.regions else ""
        for top, band in self.regions:
            if y_fraction + 1e-9 >= top:
                name = band
        return name

    def part_for(self, colour: tuple[int, int, int], y_fraction: float,
                 keys: dict[str, str]) -> str | None:
        hexvalue = "#%02x%02x%02x" % colour[:3]
        part = self.keys.get(hexvalue) or self._nearest_key(colour)
        if part is None:
            return None
        band = self.region_for(y_fraction, keys)
        part = self.region_parts.get(band, {}).get(part, part)
        if self.pupils and band == "head" and part in ("hair", "eye", "shine"):
            if sum(1 for other in _neighbours(colour, keys).values() if other == "skin") >= 2:
                return "eye"
        return part

    def _nearest_key(self, colour: tuple[int, int, int]) -> str | None:
        best: str | None = None
        best_distance = float("inf")
        for hexvalue, part in self.keys.items():
            other = rgb(hexvalue)
            distance = sum((colour[i] - other[i]) ** 2 for i in range(3))
            if distance < best_distance:
                best_distance = distance
                best = part
        return best


def _neighbours(colour: tuple[int, int, int], keys: dict[str, str]) -> dict[str, str]:
    """The parts keyed around one tone - enough to tell a pupil sitting inside
    the face from a strand of hair at the edge of it."""
    found: dict[str, str] = {}
    for offset in range(1, 9):
        other = tuple((colour[i] + (12 if (offset >> (i % 3)) & 1 else -12)) for i in range(3))
        found[str(offset)] = keys.get("#%02x%02x%02x" % other[:3], "")
    return found


# Club Casual: the original 48x48 golfer. Its palette is the one the catalogue
# has always advertised, so the layer simply has to say which tone is which.
CASUAL_ART = LegacyArt(
    id="casual", name="Club Casual",
    description="The original pixel golfer: red polo, soft cap and brown trousers.",
    root="res://assets/sprites/golfer/casual",
    spawn_tiers=["casual", "beginner"],
    palette={"shirt": "b41929", "pants": "8c6b5f", "cap": "cccbe4", "hair": "56261c",
             "skin": "e6a38d", "shoes": "2f1813", "accent": "dddcee",
             "gear": "000000"},
    parts=["shirt", "pants", "cap", "hair", "skin", "shoes", "accent", "gear"],
    regions=[(0.00, "head"), (0.34, "body"), (0.56, "waist"), (0.70, "legs"), (0.94, "feet")],
    region_parts={
        # The dark tones the artist reused all over the figure are told apart by
        # the band of the body they are drawn in: the same dark brown is the
        # hair's outline above the neck, a crease in the top on the shirt, the
        # belt at the waist, the trouser seam below it and the sole at the feet.
        "head": {"pants": "hair", "shoes": "hair", "eye": "hair"},
        "body": {"hair": "shirt", "shoes": "shirt", "cap": "shirt", "eye": "shirt"},
        "waist": {"hair": "accent", "shoes": "accent", "cap": "accent", "eye": "accent"},
        "legs": {"hair": "pants", "shoes": "pants", "cap": "pants", "eye": "pants",
                 "shine": "pants"},
        "feet": {"hair": "shoes", "cap": "shoes", "pants": "shoes", "eye": "shoes",
                 "shine": "shoes"},
    },
    pupils=True,
    keys={
        # top
        "#b41929": "shirt", "#981f2c": "shirt", "#a41123": "shirt", "#81091a": "shirt",
        "#700d17": "shirt", "#bf323a": "shirt", "#5e0c0f": "shirt", "#6e282f": "shirt",
        "#822627": "shirt", "#8a2532": "shirt", "#8c3032": "shirt", "#7d272a": "shirt",
        # the shirt's shaded side, which the artist pushed towards magenta
        "#d72045": "shirt", "#d4274b": "shirt", "#d02041": "shirt", "#cd2646": "shirt",
        "#cd1c3d": "shirt", "#ca2a41": "shirt", "#802c3b": "shirt", "#bd2e46": "shirt",
        "#ab3046": "shirt", "#c80e3e": "shirt", "#d11c44": "shirt", "#cd1740": "shirt",
        "#d3092c": "shirt", "#df1a3f": "shirt", "#d51243": "shirt", "#e3222a": "shirt",
        "#f5597f": "shirt", "#eb7284": "shirt", "#cb455c": "shirt", "#ac3554": "shirt",
        "#a10043": "shirt", "#af0044": "shirt", "#95003f": "shirt", "#e01845": "shirt",
        "#c43e62": "shirt", "#65113a": "shirt", "#781837": "shirt", "#d0444f": "shirt",
        "#e95962": "shirt", "#fa8482": "shirt", "#e67372": "shirt", "#d7655e": "shirt",
        "#e06c6c": "shirt", "#c13f4c": "shirt", "#8e303a": "shirt", "#883a43": "shirt",
        "#791f33": "shirt", "#94283f": "shirt", "#823c2e": "shirt", "#8b513d": "shirt",
        "#b24c4b": "shirt", "#8e3936": "shirt", "#93465b": "shirt",
        # cap
        "#cccbe4": "cap", "#a89eb1": "cap", "#968e9d": "cap", "#bcb6c9": "cap",
        "#d3cad7": "cap", "#aea8b1": "cap", "#857985": "cap", "#f3f3ef": "cap",
        "#f4f2f3": "cap", "#fafafa": "cap", "#fbf9f8": "cap", "#dbbfbe": "cap",
        # hair / beard (a dark brown that doubles as the art's outline)
        "#56261c": "hair", "#73382c": "hair", "#421c0f": "hair", "#6f2a32": "hair",
        "#a0677a": "hair", "#8f3852": "hair", "#973f39": "hair", "#796b71": "hair",
        # skin
        "#e6a38d": "skin", "#efb9a5": "skin", "#ca8c7a": "skin", "#de9a81": "skin",
        "#d19484": "skin", "#d5b0a1": "skin", "#b9968d": "skin", "#ac8480": "skin",
        "#f1d0be": "skin", "#b37968": "skin", "#c37b67": "skin", "#af6d5c": "skin",
        "#b96752": "skin", "#e79561": "skin", "#f8dac0": "skin", "#fbceb9": "skin",
        "#dec8c5": "skin", "#e6cabe": "skin", "#f6d1cc": "skin", "#ffd3ad": "skin",
        "#caaea4": "skin", "#d2adb1": "skin", "#d29ead": "skin", "#a25e4b": "skin",
        "#e4795f": "skin", "#df6a61": "skin", "#ef8266": "skin", "#af5a86": "skin",
        # trousers
        "#8c6b5f": "pants", "#785d59": "pants", "#5b4948": "pants", "#5e443a": "pants",
        "#97736a": "pants", "#78524e": "pants", "#ddcfc9": "pants",
        # footwear
        "#2f1813": "shoes", "#1e0c0a": "shoes", "#202831": "shoes", "#18305e": "shoes",
        # the helmet-like dark grey the walk art's soles and outline share
        "#4d3937": "shoes", "#41261f": "shoes", "#d2c4ce": "accent",
        # the trimmed lavender the collar, belt and gloves are drawn in
        "#dddcee": "accent", "#efe0d4": "accent", "#dddcee": "accent",
        # the club the walk art carries
        "#000000": "gear",
    },
)

# Weekend Beginner: drawn a size larger, with a palette of its own (the catalogue
# used to advertise the casual one, which is why nothing on this skin could be
# re-coloured). The navy the artist used for the hair, the trousers and the
# shoes is split by the band the pixel sits in.
BEGINNER_ART = LegacyArt(
    id="beginner", name="Weekend Beginner",
    description="The beginner's look - no cap, plain kit, everything a bit loose.",
    root="res://assets/sprites/golfer/beginner",
    spawn_tiers=["beginner"],
    palette={"shirt": "ebe7e7", "pants": "2c2537", "hair": "383249", "skin": "f4ada0",
             "shoes": "241d26", "gear": "643a23"},
    parts=["shirt", "pants", "hair", "skin", "shoes", "gear"],
    regions=[(0.00, "head"), (0.40, "body"), (0.68, "legs"), (0.86, "feet")],
    region_parts={
        # The navy is the hair, the trousers and the shoes all at once - and the
        # one dark line the artist used to outline each of them - so the band of
        # the figure is what says which is which. The pale tones below the knee
        # are the soles of the boots, and the one between the trouser legs is a
        # highlight on them.
        "body": {"hair": "shirt", "shoes": "shirt", "eye": "shirt"},
        "legs": {"hair": "pants", "eye": "pants", "shine": "pants", "cap": "pants",
                 "shirt": "pants"},
        "feet": {"hair": "shoes", "eye": "shoes", "pants": "shoes", "cap": "shoes",
                 "shirt": "shoes", "shine": "shoes"},
    },
    keys={
        "#ebe7e7": "shirt", "#b9b6b6": "shirt", "#d7d4dc": "shirt", "#faf5f6": "shine",
        "#aa9a99": "shirt", "#918b8c": "shirt", "#928b8c": "shirt", "#908887": "shirt",
        "#d3c3c0": "shirt", "#8b98b2": "shirt", "#51516b": "shirt", "#514a4a": "shirt",
        "#f4ada0": "skin", "#f3beb4": "skin", "#e49a8c": "skin", "#cd877c": "skin",
        "#9d807c": "skin", "#d4aaa0": "skin", "#ad6a5b": "skin", "#f3d8cc": "skin",
        "#f6d0cc": "skin", "#f5dac3": "skin", "#d6aba3": "skin", "#f2d4cd": "skin",
        "#ca9a9c": "skin", "#d7abaa": "skin", "#ae847c": "skin", "#a27a74": "skin",
        "#705a52": "skin", "#99867f": "skin", "#867168": "skin", "#9e8176": "skin",
        "#84646b": "skin", "#745956": "skin", "#84695d": "skin", "#835e53": "skin",
        "#7f5448": "skin", "#9a3952": "skin", "#fad7d2": "skin", "#ffe3cc": "skin",
        "#ddb1c5": "skin", "#8f4c4d": "skin", "#8f533c": "skin", "#8b513d": "skin",
        # the hair, the trousers and the shoes are drawn in the same navy
        "#383249": "hair", "#2c2537": "hair", "#524c59": "hair", "#574f63": "hair",
        "#686c7b": "hair", "#262c69": "hair", "#323068": "hair", "#3a2c71": "hair",
        "#423166": "hair", "#765f80": "hair", "#18305e": "hair",
        # the eyes, and the darkest outline the boots are drawn with
        "#000000": "eye", "#090521": "eye", "#241d26": "shoes", "#471c1b": "eye",
        # the club
        "#643a23": "gear", "#72452c": "gear", "#8c6d5d": "gear", "#86576e": "gear",
        "#8a5442": "gear", "#8f533c": "gear", "#995938": "gear", "#9b5648": "gear",
        "#a27a74": "skin", "#d4aaa0": "skin",
    },
)


LEGACY_ART = [CASUAL_ART, BEGINNER_ART]


def legacy_shade(art: LegacyArt, part: str, colour: tuple[int, int, int]) -> int:
    """The ramp stop the pixel was drawn in: the one closest to its colour."""
    # The parts the art has no colour of its own for - the eyes and the
    # highlights - are drawn in the fixed colours every skin shares, so they
    # have no ramp to pick a stop from.
    reference = art.palette.get(part)
    if reference is None:
        return 0
    stops = ramp(reference)
    best = 0
    best_distance = float("inf")
    for index, stop in enumerate(stops):
        distance = sum((colour[i] - stop[i]) ** 2 for i in range(3))
        if distance < best_distance:
            best_distance = distance
            best = index
    return best


def legacy_layer(art: LegacyArt, pixels: list[list[tuple[int, int, int, int]]]) -> bytes:
    height = len(pixels)
    width = len(pixels[0])
    opaque = [(x, y) for y in range(height) for x in range(width) if pixels[y][x][3] > 0]
    if not opaque:
        return bytes(width * height)
    top = min(y for _, y in opaque)
    bottom = max(y for _, y in opaque)
    span = max(bottom - top, 1)
    # The tones actually on the frame, so a shared one can be told apart by what
    # it sits next to (the pupils are found this way).
    keys = dict(art.keys)
    for x, y in opaque:
        keys["#%02x%02x%02x" % pixels[y][x][:3]] = art.part_for(
            pixels[y][x], (y - top) / span, art.keys)
    layer = bytearray(width * height)
    for x, y in opaque:
        colour = pixels[y][x]
        part = art.part_for(colour, (y - top) / span, keys)
        if part is None:
            continue
        layer[y * width + x] = layer_index(part, legacy_shade(art, part, colour))
    return bytes(layer)


def render_legacy_layers(art: LegacyArt, repo: str, drawn: set[str]) -> int:
    """Re-read the hand-made art and write the part layer beside every frame."""
    folder = art.root.replace("res://", "")
    count = 0
    for direction in DIRECTIONS:
        for anim, frames in ANIM_FRAMES.items():
            for frame in range(frames):
                frame_root = os.path.join(repo, folder, "animations", anim, direction,
                                          "frame_%03d" % frame)
                png = frame_root + ".png"
                if not os.path.exists(png):
                    continue
                pixels = read_png(png)
                layer = legacy_layer(art, pixels)
                write_layer(frame_root + LAYER_SUFFIX, layer)
                for index in layer:
                    if index:
                        drawn.add(PART_ORDER[(index - 1) // SHADE_COUNT])
                count += 1
    return count


def legacy_record(art: LegacyArt, drawn: set[str]) -> dict:
    return {
        "id": art.id,
        "name": art.name,
        "description": art.description,
        "root": art.root,
        "legacy": True,
        "customizable": [part for part in CUSTOM_PARTS if part in drawn],
        "colors": dict(art.palette),
        "spawn_tiers": art.spawn_tiers,
        "frames": {anim: frames for anim, frames in ANIM_FRAMES.items()},
        "directions": DIRECTIONS,
    }


def main() -> int:
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    data_path = os.path.join(repo, "data", "golfer_skins.json")

    skins: list[dict] = []
    total = 0
    for art in LEGACY_ART:
        drawn: set[str] = set()
        count = render_legacy_layers(art, repo, drawn)
        if not count:
            # No art on disk for this one: keep the record so the tier it
            # stands for still has a skin to name.
            drawn.update(art.parts)
        skins.append(legacy_record(art, drawn))
        total += count
        print("  %-10s %3d layers for the hand-made art" % (art.id, count))
        if count == 0:
            print("      (no art on disk for %s - nothing to layer)" % art.id)

    payload = {
        "version": 1,
        "generated_by": "tools/generate_golfer_skins.py",
        "canvas": [48, 48],
        "directions": DIRECTIONS,
        "part_labels": PART_LABELS,
        "skins": skins,
    }
    os.makedirs(os.path.dirname(data_path), exist_ok=True)
    with open(data_path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")

    print("Wrote %d part layers across %d hand-made skins" % (total, len(LEGACY_ART)))
    print("Wrote %s" % data_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
