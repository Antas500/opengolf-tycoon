#!/usr/bin/env python3
"""Generate the themed Golfer Skin sprite sets for OpenGolf Tycoon.

Every skin is drawn here, pixel by pixel, as a 48x48 figure laid out the same
way as the original hand-made Casual golfer art (feet on row 40, head starting
near row 9, centred on column 24) so any golfer can change skins without the
shadow, the club, the name label or the collision shape moving.

The tool writes:

  assets/sprites/golfer/skins/<id>/animations/<anim>/<dir>/frame_NNN.png

and one metadata file, ``data/golfer_skins.json``, describing each skin: the
palette ramps used by the art (so the game can re-colour individual parts -
shirt, cap, hair, ... - while keeping the pixel shading), which parts the
player may re-colour, and which visitor tiers may spawn wearing the skin.

Run from the repository root:

    python3 tools/generate_golfer_skins.py

The output is deterministic, so re-running the tool after an art tweak shows
up as a plain diff of PNG files.
"""

from __future__ import annotations

import json
import math
import os
import struct
import sys
import zlib
from dataclasses import dataclass, field

# ---------------------------------------------------------------------------
# Canvas and figure metrics
# ---------------------------------------------------------------------------

W = 48
H = 48
CX = 24          # the figure is centred between columns 23 and 24

DIRECTIONS = [
    "south", "south-east", "east", "north-east",
    "north", "north-west", "west", "south-west",
]

ANIM_FRAMES = {"idle": 4, "walk": 4, "swing": 6}

# Vertical anchors, in sprite pixels. They match the original Casual art so
# the feet land on row 40 whatever the golfer ended up wearing.
HEAD_CY = 14.0
HEAD_RX = 5.3
HEAD_RY = 5.6
EYE_Y = 13
NECK_Y = 18
TORSO_TOP = 19
TORSO_BOTTOM = 29
SHOULDER_HALF = 5
WAIST_HALF = 4
LEG_TOP = 30
FOOT_Y = 38
SHOE_Y = 40
LEG_W = 4
LEG_GAP = 1


# ---------------------------------------------------------------------------
# PNG writer (RGBA8, no interlace - all Godot needs)
# ---------------------------------------------------------------------------


def _chunk(kind: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + kind
        + payload
        + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
    )


def write_png(path: str, pixels: list[list[tuple[int, int, int, int]]]) -> None:
    height = len(pixels)
    width = len(pixels[0])
    raw = bytearray()
    for row in pixels:
        raw.append(0)  # filter type: none
        for rgba in row:
            raw += bytes(rgba)
    data = b"\x89PNG\r\n\x1a\n"
    data += _chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    data += _chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    data += _chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(data)


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
# ``frame_000.layer.bin`` - deflated so the whole 1,456-frame catalogue costs
# a few hundred kilobytes rather than three and a half.

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
# Geometry
# ---------------------------------------------------------------------------

Cell = tuple[int, int]
Cells = set[Cell]


def rect(x0: int, y0: int, x1: int, y1: int) -> Cells:
    if x1 < x0:
        x0, x1 = x1, x0
    if y1 < y0:
        y0, y1 = y1, y0
    return {(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)}


def ellipse(cx: float, cy: float, rx: float, ry: float) -> Cells:
    cells: Cells = set()
    for y in range(int(math.floor(cy - ry - 1)), int(math.ceil(cy + ry + 1)) + 1):
        for x in range(int(math.floor(cx - rx - 1)), int(math.ceil(cx + rx + 1)) + 1):
            dx = (x + 0.5 - cx) / max(rx, 0.5)
            dy = (y + 0.5 - cy) / max(ry, 0.5)
            if dx * dx + dy * dy <= 1.02:
                cells.add((x, y))
    return cells


def line(x0: int, y0: int, x1: int, y1: int) -> Cells:
    cells: Cells = set()
    dx = abs(x1 - x0)
    dy = -abs(y1 - y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx + dy
    x, y = x0, y0
    while True:
        cells.add((x, y))
        if x == x1 and y == y1:
            break
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x += sx
        if e2 <= dx:
            err += dx
            y += sy
    return cells


def thick(cells: Cells, radius: int = 1) -> Cells:
    out: Cells = set(cells)
    for x, y in cells:
        for dx in range(-radius, radius + 1):
            for dy in range(-radius, radius + 1):
                out.add((x + dx, y + dy))
    return out


def mir(cells: Cells) -> Cells:
    """Mirror about the figure's centre line (between columns 23 and 24)."""
    return {(2 * int(CX) - 1 - x, y) for x, y in cells}


def shift(cells: Cells, dx: int, dy: int = 0) -> Cells:
    return {(x + dx, y + dy) for x, y in cells}


def clip(cells: Cells) -> Cells:
    return {(x, y) for x, y in cells if 0 <= x < W and 0 <= y < H}


# ---------------------------------------------------------------------------
# Painter
# ---------------------------------------------------------------------------

FIXED = {
    "eye": (36, 26, 28),
    "shine": (250, 250, 245),
    "shadow": (20, 24, 20),
}

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


class Painter:
    """Collects the drawing as (part, ramp index) per pixel."""

    def __init__(self, width: int = W, height: int = H) -> None:
        self.width = width
        self.height = height
        self.part: list[list[str | None]] = [[None] * width for _ in range(height)]
        self.shade: list[list[int]] = [[0] * width for _ in range(height)]

    # -- low level ---------------------------------------------------------
    def put(self, x: int, y: int, part: str, shade: int = 0) -> None:
        if 0 <= x < self.width and 0 <= y < self.height:
            self.part[y][x] = part
            self.shade[y][x] = shade

    def at(self, x: int, y: int) -> str | None:
        if 0 <= x < self.width and 0 <= y < self.height:
            return self.part[y][x]
        return None

    # -- shapes ------------------------------------------------------------
    def fill(self, cells: Cells, part: str, *, shade: bool = True, light: bool = True,
             light_rows: int = 1, dark_at: float = 0.70) -> None:
        """Fill a shape and shade it top-to-bottom for volume."""
        cells = clip(cells)
        if not cells:
            return
        rows = [y for _, y in cells]
        top, bottom = min(rows), max(rows)
        span = max(bottom - top, 1)
        for x, y in cells:
            level = 0
            if shade:
                frac = (y - top) / span
                if frac >= dark_at:
                    level = 2
                elif light and y - top < light_rows:
                    level = 1
            self.put(x, y, part, level)

    def rows(self, cells: Cells, part: str, y0: int, y1: int) -> None:
        self.fill({(x, y) for x, y in cells if y0 <= y <= y1}, part, shade=False)

    def stripe(self, cells: Cells, part: str, every: int = 3, offset: int = 1) -> None:
        for x, y in cells:
            if (x + y + offset) % every == 0:
                self.put(x, y, part, 0)

    def sil(self, cells: Cells, part: str, *, shade: bool = True, light: bool = True,
            light_rows: int = 1) -> None:
        self.fill(cells, part, shade=shade, light=light, light_rows=light_rows)

    # -- outline -----------------------------------------------------------
    def outline_silhouette(self, thickness: int = 1) -> None:
        """Darken the rim of the whole figure, so every skin shares the one
        dark outline the original art uses."""
        for _ in range(thickness):
            rim: Cells = set()
            for y in range(self.height):
                for x in range(self.width):
                    if self.part[y][x] is None:
                        continue
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        if self.at(x + dx, y + dy) is None:
                            rim.add((x, y))
                            break
            for x, y in rim:
                self.shade[y][x] = 3

    def outline_parts(self) -> None:
        """Dark line along the seam between two different parts, the way the
        stock art separates a sleeve from a shirt or a shirt from trousers."""
        darken: Cells = set()
        for y in range(self.height):
            for x in range(self.width):
                part = self.part[y][x]
                if part is None or part in ("eye", "shine"):
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    neighbour = self.at(x + dx, y + dy)
                    if neighbour is not None and neighbour != part:
                        darken.add((x, y))
                        break
        for x, y in darken:
            if self.shade[y][x] < 3:
                self.shade[y][x] = 3

    def edge(self, cells: Cells, part: str) -> None:
        """Explicit dark line along the rim of one part (mask edges, hems)."""
        for x, y in cells:
            if self.part[y][x] == part:
                self.shade[y][x] = 3

    # -- output ------------------------------------------------------------
    def to_pixels(self, palette: dict[str, list[tuple[int, int, int]]],
                  fixed: dict[str, tuple[int, int, int]]) -> list[list[tuple[int, int, int, int]]]:
        pixels = [[(0, 0, 0, 0)] * self.width for _ in range(self.height)]
        for y in range(self.height):
            for x in range(self.width):
                part = self.part[y][x]
                if part is None:
                    continue
                if part in fixed:
                    colour = fixed[part]
                else:
                    shades = palette[part]
                    colour = shades[min(self.shade[y][x], len(shades) - 1)]
                pixels[y][x] = (colour[0], colour[1], colour[2], 255)
        return pixels

    def scaled(self, factor: int) -> "Painter":
        out = Painter(self.width * factor, self.height * factor)
        for y in range(self.height):
            for x in range(self.width):
                part = self.part[y][x]
                if part is None:
                    continue
                for oy in range(factor):
                    for ox in range(factor):
                        out.put(x * factor + ox, y * factor + oy, part, self.shade[y][x])
        return out

    def to_layer(self) -> bytes:
        """The part layer for this frame: one byte per pixel, as the game reads
        it. Every pixel the artist drew gets its part; the shadow (which is not
        a body part) and empty canvas stay 0, which the game never re-colours."""
        layer = bytearray(self.width * self.height)
        for y in range(self.height):
            for x in range(self.width):
                part = self.part[y][x]
                if part is None:
                    continue
                layer[y * self.width + x] = layer_index(part, self.shade[y][x])
        return bytes(layer)


# ---------------------------------------------------------------------------
# Skin definitions
# ---------------------------------------------------------------------------


@dataclass
class Skin:
    id: str
    name: str
    description: str
    palette: dict[str, str]
    custom: list[str] = field(default_factory=lambda: list(CUSTOM_PARTS))
    spawn_tiers: list[str] = field(default_factory=list)
    hat: str = "cap"
    hair: str = "short"
    top: str = "polo"
    legs: str = "trousers"
    shoes: str = "cleats"
    gear: str = "club"
    face: list[str] = field(default_factory=list)
    accent_style: str = ""


SKINS: list[Skin] = [
    Skin(
        id="plain", name="Club Standard",
        description="The plain club golfer: flat colours, no fancy kit, one clean "
                    "silhouette. The best starting point for a skin of your own.",
        palette={"skin": "eab68f", "hair": "4a3324", "shirt": "4a86c8",
                 "pants": "3b4a63", "cap": "dcdcd9", "shoes": "2e2a28",
                 "accent": "ececec", "gear": "9a9a9a"},
        spawn_tiers=["beginner", "casual"],
        hat="cap", hair="short", top="polo", legs="trousers", shoes="cleats",
        gear="club", accent_style="collar",
    ),
    Skin(
        id="caddie", name="Caddie",
        description="Flat cap, bib overalls over a polo, a towel over one shoulder "
                    "and a bag strap across the chest.",
        palette={"skin": "dda87e", "hair": "3a2617", "shirt": "3f7fb5",
                 "pants": "2f4b78", "cap": "6b6f74", "shoes": "3a2f26",
                 "accent": "efe9dc", "gear": "6d4b2f"},
        spawn_tiers=["casual", "beginner"],
        hat="flat", hair="short", top="overalls", legs="trousers", shoes="sneakers",
        gear="towel", accent_style="strap",
    ),
    Skin(
        id="wizard", name="Wizard",
        description="A tall crooked hat, a long robe that sweeps past the knees, a "
                    "pointed grey beard and a staff with a glowing stone.",
        palette={"skin": "e7bd97", "hair": "d8dbe2", "shirt": "4a3d8f",
                 "pants": "362c6b", "cap": "4a3d8f", "shoes": "4a3524",
                 "accent": "e5c76b", "gear": "7a5a34"},
        spawn_tiers=["casual", "serious"],
        hat="wizard", hair="longbeard", top="robe", legs="robe", shoes="sandals",
        gear="staff", accent_style="star",
    ),
    Skin(
        id="robot", name="Robot",
        description="A boxy chrome caddie with a glowing eyeslit, a shoulder aerial "
                    "and claw hands. Every panel hums with light.",
        palette={"skin": "9aa6b2", "hair": "6a7480", "shirt": "a3b0bf",
                 "pants": "6e7a88", "cap": "c9d4e0", "shoes": "444c56",
                 "accent": "3fd6c0", "gear": "8a949f"},
        spawn_tiers=["serious", "pro"],
        hat="antenna", hair="bald", top="chassis", legs="piston", shoes="magboots",
        gear="spanner", face=["visor"], accent_style="led",
    ),
    Skin(
        id="ninja", name="Ninja",
        description="A hood and mask with only the eyes showing, a knotted headband "
                    "trailing behind, and wrapped tabi boots. Silent off the tee.",
        palette={"skin": "e0ac84", "hair": "1d1d24", "shirt": "2b2f3a",
                 "pants": "23262f", "cap": "2b2f3a", "shoes": "15151a",
                 "accent": "c03a3a", "gear": "3a3f4b"},
        spawn_tiers=["casual", "serious", "pro"],
        hat="headband", hair="hood", top="gi", legs="tabi", shoes="tabi",
        gear="club", face=["mask"], accent_style="sash",
    ),
    Skin(
        id="pirate", name="Pirate",
        description="A tricorn hat, a striped shirt, an eyepatch, a cutlass and a "
                    "wooden peg where one leg should be.",
        palette={"skin": "d9a173", "hair": "241a14", "shirt": "ece6da",
                 "pants": "33405c", "cap": "23252e", "shoes": "2b2118",
                 "accent": "b8453c", "gear": "c9c9cf"},
        spawn_tiers=["beginner", "casual", "serious"],
        hat="tricorn", hair="long", top="striped", legs="peg", shoes="boots",
        gear="cutlass", face=["eyepatch"], accent_style="sash",
    ),
    Skin(
        id="cowboy", name="Cowboy",
        description="A wide-brimmed hat, a poncho over the shoulders, a knotted "
                    "bandana and spurred boots that click down the fairway.",
        palette={"skin": "d6a071", "hair": "3d2a18", "shirt": "8a5a34",
                 "pants": "3f4a5c", "cap": "6f4d2c", "shoes": "4a3320",
                 "accent": "b8443c", "gear": "c8a05a"},
        spawn_tiers=["beginner", "casual"],
        hat="cowboy", hair="short", top="poncho", legs="trousers", shoes="boots",
        gear="lasso", face=["moustache"],
    ),
    Skin(
        id="astronaut", name="Astronaut",
        description="A bubble helmet over a life-support pack, with thick gloves and "
                    "magnetised boots. Brings a spare ball for every planet.",
        palette={"skin": "e2b18c", "hair": "3a2b22", "shirt": "d3dce6",
                 "pants": "a9b6c6", "cap": "e8f4ff", "shoes": "7f8b99",
                 "accent": "e0662f", "gear": "95a3b3"},
        spawn_tiers=["pro"],
        hat="bubble", hair="short", top="hazmat", legs="trousers", shoes="magboots",
        gear="pack", face=["goggles"], accent_style="led",
    ),
    Skin(
        id="suit", name="Business Golfer",
        description="A pressed blazer, a silk tie, dark glasses and a briefcase the "
                    "caddie never gets to carry.",
        palette={"skin": "e3b389", "hair": "2c2320", "shirt": "f4f4f2",
                 "pants": "33384a", "cap": "f4f4f2", "shoes": "1e1e22",
                 "accent": "8f2b3c", "gear": "4a3625"},
        spawn_tiers=["serious", "pro"],
        hat="none", hair="swept", top="blazer", legs="trousers", shoes="dress",
        gear="briefcase", face=["shades"], accent_style="tie",
    ),
    Skin(
        id="lumberjack", name="Lumberjack",
        description="A plaid flannel, a knitted beanie, a thick beard and an axe "
                    "that doubles as a driver.",
        palette={"skin": "dfa77c", "hair": "6b3a1c", "shirt": "b03a2e",
                 "pants": "3d5670", "cap": "3f7f6a", "shoes": "3a2a1c",
                 "accent": "d8c07a", "gear": "9aa0a6"},
        spawn_tiers=["beginner", "casual"],
        hat="beanie", hair="beard", top="flannel", legs="trousers", shoes="boots",
        gear="axe", face=["beard"],
    ),
    Skin(
        id="chef", name="Chef",
        description="A tall toque, a double-breasted jacket over an apron and a red "
                    "neckerchief. Food is the other kind of club.",
        palette={"skin": "e6b78f", "hair": "4a3222", "shirt": "f6f6f4",
                 "pants": "3a3f45", "cap": "fbfbfb", "shoes": "2a2624",
                 "accent": "c23b32", "gear": "b9c0c6"},
        spawn_tiers=["beginner", "casual", "serious"],
        hat="toque", hair="short", top="apron", legs="trousers", shoes="cleats",
        gear="whisk", accent_style="neckerchief", face=["moustache"],
    ),
    Skin(
        id="knight", name="Knight",
        description="Plate armour with pauldrons, a plumed helm with the visor up, "
                    "and a tabard over the breastplate.",
        palette={"skin": "e0b08c", "hair": "2e2b2f", "shirt": "97a5b5",
                 "pants": "7d8896", "cap": "c3cfdc", "shoes": "6b7684",
                 "accent": "3f63b0", "gear": "b4bdc7"},
        spawn_tiers=["serious", "pro"],
        hat="helmet", hair="short", top="armour", legs="greaves", shoes="sabatons",
        gear="sword", face=["visor"], accent_style="plume",
    ),
    Skin(
        id="retro", name="Retro Sprite",
        description="A 24x24 sprite blown up to 48x48, straight off a 1990s "
                    "cartridge. Chunky pixels, tiny palette, huge nostalgia.",
        palette={"skin": "f0c090", "hair": "503020", "shirt": "d84848",
                 "pants": "3050a0", "cap": "f0f0f0", "shoes": "282828",
                 "accent": "f0d040", "gear": "808080"},
        spawn_tiers=["beginner", "casual", "serious", "pro"],
        hat="retrocap", hair="short", top="retro", legs="trousers", shoes="cleats",
        gear="club",
    ),
]


# ---------------------------------------------------------------------------
# Poses
# ---------------------------------------------------------------------------


@dataclass
class Pose:
    body_dy: int = 0
    lean: int = 0                       # upper body shifted towards the facing side
    head_dy: int = 0
    head_dx: int = 0
    leg_dx: tuple[int, int] = (0, 0)    # left/right leg horizontal offset
    leg_dy: tuple[int, int] = (0, 0)    # left/right foot lift (negative = up)
    hand_dx: tuple[int, int] = (0, 0)   # left/right hand horizontal offset
    hand_dy: tuple[int, int] = (0, 0)   # left/right hand vertical offset
    hand_grip: bool = False             # both hands together on the club
    grip_dy: int = 0                    # grip height, relative to the waist
    club: tuple[int, int] = (2, 7)      # club head, relative to the hands


def idle_pose(frame: int) -> Pose:
    breathe = [(0, 0), (-1, 1), (0, 0), (1, -1)]
    bob, sway = breathe[frame % 4]
    return Pose(body_dy=bob, hand_dy=(sway, sway))


def walk_pose(frame: int) -> Pose:
    return [
        Pose(leg_dx=(-1, 1), hand_dx=(1, -1)),
        Pose(leg_dy=(0, -1), body_dy=-1),
        Pose(leg_dx=(1, -1), hand_dx=(-1, 1)),
        Pose(leg_dy=(-1, 0), body_dy=-1),
    ][frame % 4]


def swing_pose(frame: int) -> Pose:
    """Address, takeaway, half way up, top, impact, follow through."""
    return [
        # address: hands low, club resting on the ground out in front
        Pose(hand_grip=True, grip_dy=0, club=(3, 7)),
        # takeaway: hands lift, club trailing behind
        Pose(hand_grip=True, grip_dy=-2, hand_dx=(-1, -1), club=(5, 2)),
        # half way up: hands at chest height, club behind the shoulder
        Pose(hand_grip=True, grip_dy=-5, hand_dx=(-2, -2), lean=-1, club=(6, -3)),
        # top of the backswing: club over the shoulder
        Pose(hand_grip=True, grip_dy=-7, hand_dx=(-2, -2), lean=-1, head_dx=-1,
             club=(4, -7)),
        # impact: hands back down and through
        Pose(hand_grip=True, grip_dy=0, hand_dx=(1, 1), lean=1, head_dx=1, club=(3, 7)),
        # follow through: club swung up over the other shoulder
        Pose(hand_grip=True, grip_dy=-6, hand_dx=(2, 2), lean=1, head_dx=1, club=(-6, -6)),
    ][frame % 6]


def pose_for(anim: str, frame: int) -> Pose:
    if anim == "idle":
        return idle_pose(frame)
    if anim == "walk":
        return walk_pose(frame)
    return swing_pose(frame)


# ---------------------------------------------------------------------------
# Views
# ---------------------------------------------------------------------------

FRONT, BACK, SIDE = "front", "back", "side"

## Hats that sit over the crown of the head: no hair shows above them.
HAT_STYLES_COVERING_CROWN = {
    "cap", "retrocap", "flat", "beanie", "tricorn", "cowboy", "wizard", "fedora",
    "helmet", "toque", "antenna", "bubble", "plume",
}


def view_for(direction: str) -> tuple[str, int]:
    """(base view, facing): facing +1 faces the right of the screen, -1 left,
    0 straight on."""
    return {
        "south": (FRONT, 0),
        "north": (BACK, 0),
        "east": (SIDE, 1),
        "west": (SIDE, -1),
        "south-east": (FRONT, 1),
        "south-west": (FRONT, -1),
        "north-east": (BACK, 1),
        "north-west": (BACK, -1),
    }[direction]


# ---------------------------------------------------------------------------
# The golfer
# ---------------------------------------------------------------------------


def draw_golfer(skin: Skin, direction: str, anim: str, frame: int) -> Painter:
    if skin.id == "retro":
        return draw_retro(skin, direction, anim, frame)
    view, facing = view_for(direction)
    pose = pose_for(anim, frame)
    turn = 0 if view != SIDE else 0
    angle = facing  # -1 / 0 / +1: how far the figure is turned from the camera
    global HAT_COVERS_CROWN
    HAT_COVERS_CROWN = skin.hat in HAT_STYLES_COVERING_CROWN
    p = Painter()
    _draw_pack(p, skin, view, angle, pose)
    _draw_legs(p, skin, view, angle, pose)
    _draw_torso(p, skin, view, angle, pose)
    _draw_hair_back(p, skin, view, angle, pose)
    _draw_head(p, skin, view, angle, pose)
    _draw_hat(p, skin, view, angle, pose)
    _draw_gear(p, skin, view, angle, pose)
    p.outline_silhouette()
    return p


# -- silhouette helpers ------------------------------------------------------


def _draw_pack(p: Painter, skin: Skin, view: str, angle: int, pose: Pose) -> None:
    """Life-support packs and backpacks, drawn behind everything else."""
    if skin.gear != "pack" or view == FRONT:
        return
    cx = CX + pose.lean + (angle if view != SIDE else 0)
    pack = rect(cx - 5, TORSO_TOP - 2 + pose.body_dy, cx + 4, TORSO_BOTTOM - 2 + pose.body_dy)
    p.fill(pack, "gear", shade=True, light=False, dark_at=1.2)
    p.fill(rect(cx - 2, TORSO_TOP - 3 + pose.body_dy, cx + 1, TORSO_TOP - 2 + pose.body_dy),
           "gear", shade=False)
    p.fill(rect(cx - 3, TORSO_TOP + 3 + pose.body_dy, cx + 2, TORSO_TOP + 4 + pose.body_dy),
           "accent", shade=False)


def head_cells(view: str, angle: int, pose: Pose) -> Cells:
    cx = int(CX + pose.lean + pose.head_dx + (angle if view != SIDE else 0))
    cy = int(HEAD_CY + pose.body_dy + pose.head_dy)
    if view == SIDE:
        facing = 1 if angle >= 0 else -1
        return clip(ellipse(cx, cy, HEAD_RX - 0.4, HEAD_RY) | ellipse(cx + 2.4 * facing, cy + 0.6, 2.0, 2.0))
    return clip(ellipse(cx, cy, HEAD_RX, HEAD_RY))


def torso_cells(view: str, angle: int, pose: Pose, *, extra_bottom: int = 0,
                widen: int = 0) -> Cells:
    top = TORSO_TOP + pose.body_dy
    bottom = TORSO_BOTTOM + pose.body_dy + extra_bottom
    lean = pose.lean
    if view == SIDE:
        x0, x1 = CX - 4 + lean, CX + 3 + lean
    else:
        x0 = CX - SHOULDER_HALF + angle - widen
        x1 = CX + SHOULDER_HALF - 1 + angle + widen
    cells: Cells = set()
    for y in range(top, bottom + 1):
        frac = (y - top) / max(bottom - top, 1)
        half = (WAIST_HALF - 0.6) + (SHOULDER_HALF - WAIST_HALF + 0.6) * max(0.0, 1.0 - frac * 1.6)
        mid = (x0 + x1 + 1) / 2.0
        lo = int(round(mid - half - 0.5))
        hi = int(round(mid + half - 0.5))
        cells |= rect(lo, y, hi, y)
    return clip(cells)


def hand_cells(view: str, angle: int, pose: Pose, side: int) -> Cells:
    """The hand at the end of one arm (side -1 = the golfer's left)."""
    index = 0 if side < 0 else 1
    dy = pose.body_dy + pose.hand_dy[index]
    if pose.hand_grip:
        # Both hands meet on the club grip, out in front of the body.
        cx = CX + pose.lean + pose.hand_dx[1] + (angle if view != SIDE else 0)
        y = TORSO_BOTTOM - 2 + pose.body_dy + pose.grip_dy + (2 if view == SIDE else 0)
        hands = rect(cx - 2, y, cx + 2, y + 1)
        gap = rect(cx - 1, y, cx, y)
        return clip(hands - gap)
    if view == SIDE:
        cx = CX + pose.lean + 1 + pose.hand_dx[index]
        return clip(rect(cx - 1, TORSO_BOTTOM - 4 + dy, cx + 1, TORSO_BOTTOM - 2 + dy))
    if side < 0:
        cx = CX - SHOULDER_HALF + pose.hand_dx[index] + (angle if view == BACK else 0)
        return clip(rect(cx - 1, TORSO_BOTTOM - 4 + dy, cx, TORSO_BOTTOM - 2 + dy))
    cx = CX + SHOULDER_HALF - 1 + pose.hand_dx[index] + (angle if view == BACK else 0)
    return clip(rect(cx - 1, TORSO_BOTTOM - 4 + dy, cx, TORSO_BOTTOM - 2 + dy))


def shoulder_cells(view: str, angle: int, pose: Pose, side: int) -> Cells:
    index = 0 if side < 0 else 1
    dy = pose.body_dy
    y = TORSO_TOP + 1 + dy
    hx, hy = _hand_anchor(view, angle, pose, index)
    sx = CX + side * (SHOULDER_HALF - 1) + (angle if view != SIDE else pose.lean)
    if side < 0:
        sx = CX - SHOULDER_HALF + 1 + (angle if view == BACK else angle if view == FRONT else pose.lean)
    else:
        sx = CX + SHOULDER_HALF - 2 + (angle if view == BACK else angle if view == FRONT else pose.lean)
    if view == SIDE:
        sx = CX + pose.lean + 1
    return clip(line(sx, y, hx, hy))


def _hand_anchor(view: str, angle: int, pose: Pose, index: int) -> tuple[int, int]:
    dy = pose.body_dy + pose.hand_dy[index]
    if pose.hand_grip:
        cx = CX + pose.lean + pose.hand_dx[1] + (angle if view != SIDE else 0)
        return (cx, TORSO_BOTTOM - 1 + pose.body_dy + pose.grip_dy)
    if view == SIDE:
        return (CX + pose.lean + 1 + pose.hand_dx[index], TORSO_BOTTOM - 3 + dy)
    if index == 0:
        return (CX - SHOULDER_HALF + pose.hand_dx[index] + (angle if view == BACK else 0),
                TORSO_BOTTOM - 3 + dy)
    return (CX + SHOULDER_HALF - 1 + pose.hand_dx[index] + (angle if view == BACK else 0),
            TORSO_BOTTOM - 3 + dy)


# -- legs --------------------------------------------------------------------


def _draw_legs(p: Painter, skin: Skin, view: str, angle: int, pose: Pose) -> None:
    if skin.legs == "robe":
        return
    if view == SIDE:
        back = rect(CX - 3 + pose.leg_dx[0], LEG_TOP, CX + 1 + pose.leg_dx[0], FOOT_Y + pose.leg_dy[0])
        front = rect(CX - 1 + pose.leg_dx[1], LEG_TOP, CX + 3 + pose.leg_dx[1], FOOT_Y + pose.leg_dy[1])
    else:
        back = rect(CX - LEG_GAP - LEG_W + pose.leg_dx[0], LEG_TOP,
                    CX - LEG_GAP - 1 + pose.leg_dx[0], FOOT_Y + pose.leg_dy[0])
        front = rect(CX + LEG_GAP + 1 + pose.leg_dx[1], LEG_TOP,
                     CX + LEG_GAP + LEG_W + pose.leg_dx[1], FOOT_Y + pose.leg_dy[1])
    legs = [(back, 0), (front, 1)]
    for cells, index in legs:
        if skin.legs == "piston":
            cells = rect(min(x for x, _ in cells) + 1, LEG_TOP, max(x for x, _ in cells) - 1,
                         FOOT_Y + pose.leg_dy[index])
            p.fill(cells, "gear", shade=True, light=(index == 1))
            p.rows(cells, "accent", LEG_TOP + 3, LEG_TOP + 4)
            p.rows(cells, "accent", LEG_TOP + 7, LEG_TOP + 7)
            continue
        p.fill(cells, "pants", shade=True, light=(index == 1))
        if skin.legs == "tabi":
            p.rows(cells, "accent", FOOT_Y - 4 + pose.leg_dy[index], FOOT_Y - 3 + pose.leg_dy[index])
        if skin.legs == "greaves":
            p.rows(cells, "cap", LEG_TOP, FOOT_Y - 4 + pose.leg_dy[index])
        if skin.legs == "peg":
            p.rows(cells, "pants", LEG_TOP, FOOT_Y - 1)
    if skin.legs == "peg":
        peg = rect(CX + LEG_GAP + 1, FOOT_Y - 6, CX + LEG_GAP + 2, FOOT_Y - 2)
        p.fill(peg, "gear", shade=True, light=False)
        p.fill(rect(CX + LEG_GAP, FOOT_Y + 1, CX + LEG_GAP + 3, FOOT_Y + 2), "shoes", shade=True,
               light=False)
        p.fill(rect(CX - LEG_GAP - LEG_W, FOOT_Y - 1, CX - LEG_GAP - 1, FOOT_Y), "shoes",
               shade=True, light=False)
        return

    for cells, index in legs:
        _draw_shoe(p, skin, cells, view, pose, index)


def _draw_shoe(p: Painter, skin: Skin, leg: Cells, view: str, pose: Pose, index: int) -> None:
    if not leg:
        return
    x0 = min(x for x, _ in leg)
    x1 = max(x for x, _ in leg)
    lift = pose.leg_dy[index]
    top = FOOT_Y + 1 + lift
    bottom = SHOE_Y + lift
    if skin.shoes == "boots":
        top = FOOT_Y - 3 + lift
    elif skin.shoes == "bare":
        p.fill(rect(x0, FOOT_Y + 1 + lift, x1, SHOE_Y + lift), "skin", shade=False)
        return
    shoe = rect(x0 - 1, top, x1 + 1, bottom)
    if view == SIDE:
        shoe = rect(x0 - 2, top, x1 + 1, bottom)
    p.fill(shoe, "shoes", shade=True, light=False, dark_at=0.9)
    if skin.shoes == "sabatons":
        p.rows(shoe, "cap", top, top)
    if skin.shoes == "sneakers":
        p.rows(shoe, "accent", top, top)
    if skin.shoes == "magboots":
        p.rows(shoe, "accent", bottom, bottom)
    if skin.shoes == "dress":
        p.rows(shoe, "shoes", top, bottom)


# -- torso -------------------------------------------------------------------


def _draw_torso(p: Painter, skin: Skin, view: str, angle: int, pose: Pose) -> None:
    robe = skin.top == "robe"
    torso = torso_cells(view, angle, pose, extra_bottom=7 if robe else 0)
    p.fill(torso, "shirt", light=False)

    # Sleeves: a line of shirt colour from each shoulder to its hand.
    top_y = TORSO_TOP + pose.body_dy
    hands = [hand_cells(view, angle, pose, side) for side in (-1, 1)]
    for index, hand in enumerate(hands):
        if not hand:
            continue
        sx = CX + (-1 if index == 0 else 1) * (SHOULDER_HALF - 2) + (angle if view != SIDE else pose.lean)
        sy = top_y + 1
        hx = sum(x for x, _ in hand) // len(hand)
        hy = min(y for _, y in hand)
        path = line(sx, sy, hx, hy)
        sleeve = set(path)
        sleeve |= {(x + (-1 if index == 0 else 1), y) for x, y in path}
        sleeve |= {(x, y - 1) for x, y in path if y > sy}
        p.fill(sleeve, "shirt", shade=True, light=(index == 0), light_rows=1)
    for index, hand in enumerate(hands):
        if not hand:
            continue
        if skin.top == "chassis":
            p.fill(thick(hand, 0), "gear", shade=True, light=False)
        elif skin.top == "hazmat":
            p.fill(hand, "accent", shade=True, light=False)
        elif skin.top == "armour":
            p.fill(hand, "gear", shade=True, light=False)
        else:
            p.fill(hand, "skin", shade=True, light=False)

    # Neck between the collar and the chin.
    neck = rect(CX - 1 + pose.lean + (angle if view != SIDE else 0), NECK_Y + pose.body_dy,
                CX + 1 + pose.lean + (angle if view != SIDE else 0), TORSO_TOP + pose.body_dy + 1)
    p.fill(neck, "skin", shade=False)

    # Neckline / collar.
    col_y = TORSO_TOP + pose.body_dy
    col_x0 = CX - 3 + (angle if view != SIDE else pose.lean)
    col_x1 = CX + 2 + (angle if view != SIDE else pose.lean)
    if skin.top in ("polo", "striped", "flannel", "overalls", "chassis", "apron", "retro"):
        p.fill(rect(col_x0, col_y, col_x1, col_y), "accent", shade=False)
    elif skin.top == "gi":
        p.fill(rect(col_x0 - 1, col_y, col_x1 + 1, col_y), "accent", shade=False)
    elif skin.top in ("blazer", "hazmat"):
        p.fill(rect(col_x0, col_y, col_x1, col_y), "shirt", shade=False)

    # Surface details.
    if skin.top == "striped":
        area = rect(CX - 6, TORSO_TOP + 1 + pose.body_dy, CX + 5, TORSO_BOTTOM + pose.body_dy)
        for x, y in area:
            if y % 3 == 0:
                p.put(x, y, "accent", 0)
    if skin.top == "flannel":
        area = rect(CX - 6, TORSO_TOP + 1 + pose.body_dy, CX + 5, TORSO_BOTTOM + pose.body_dy)
        for x, y in area:
            if (x + y) % 4 == 0:
                p.put(x, y, "accent", 0)
            elif (x - y) % 4 == 0:
                p.put(x, y, "accent", 2)
    if skin.top == "blazer":
        p.fill(rect(CX - 2 + pose.lean, TORSO_TOP + 1 + pose.body_dy,
                    CX - 2 + pose.lean, TORSO_BOTTOM - 1 + pose.body_dy), "shirt", shade=False)
        p.fill(rect(CX + 1 + pose.lean, TORSO_TOP + 1 + pose.body_dy,
                    CX + 1 + pose.lean, TORSO_BOTTOM - 1 + pose.body_dy), "shirt", shade=False)
        p.fill(rect(CX - 1 + pose.lean, TORSO_TOP + 1 + pose.body_dy,
                    CX + pose.lean, TORSO_BOTTOM - 2 + pose.body_dy), "accent", shade=False)
        p.fill(rect(CX - 3 + pose.lean, TORSO_TOP + 1 + pose.body_dy,
                    CX + 2 + pose.lean, TORSO_TOP + 2 + pose.body_dy), "shirt", shade=True,
               light=False)
    if skin.top == "apron":
        p.fill(rect(CX - 5, TORSO_TOP + 3 + pose.body_dy, CX + 4, TORSO_BOTTOM + pose.body_dy),
               "accent", shade=True, light=False)
        p.fill(rect(CX - 1, TORSO_TOP + 2 + pose.body_dy, CX, TORSO_BOTTOM + pose.body_dy),
               "shirt", shade=False)
    if skin.top == "poncho":
        p.fill(rect(CX - 7, TORSO_TOP + pose.body_dy, CX + 6, TORSO_TOP + 3 + pose.body_dy),
               "accent", shade=True, light=False)
        p.fill(rect(CX - 1, TORSO_TOP + 4 + pose.body_dy, CX, TORSO_TOP + 6 + pose.body_dy),
               "accent", shade=False)
    if skin.top == "armour":
        p.fill(rect(CX - 7, TORSO_TOP + pose.body_dy, CX + 6, TORSO_TOP + 2 + pose.body_dy),
               "cap", shade=True, light=True)
        p.fill(rect(CX - 1, TORSO_BOTTOM - 6 + pose.body_dy, CX + 0, TORSO_BOTTOM + pose.body_dy),
               "accent", shade=False)
        for side in (-1, 1):
            sx = CX + side * (SHOULDER_HALF) + (angle if view != SIDE else pose.lean)
            p.fill(rect(sx - 1, TORSO_TOP + pose.body_dy, sx + 1, TORSO_TOP + 2 + pose.body_dy),
                   "cap", shade=True, light=True)
    if skin.top == "hazmat":
        p.fill(rect(CX - 3, TORSO_BOTTOM - 2 + pose.body_dy, CX + 2, TORSO_BOTTOM + pose.body_dy),
               "accent", shade=False)
        p.fill(rect(CX - 2, TORSO_TOP + 3 + pose.body_dy, CX + 1, TORSO_TOP + 4 + pose.body_dy),
               "accent", shade=False)
        p.fill(rect(CX - 3, TORSO_TOP + 5 + pose.body_dy, CX + 2, TORSO_TOP + 5 + pose.body_dy),
               "gear", shade=False)
    if skin.top == "chassis":
        p.fill(rect(CX - 3, TORSO_TOP + 3 + pose.body_dy, CX + 2, TORSO_TOP + 4 + pose.body_dy),
               "accent", shade=False)
        p.fill(rect(CX - 2, TORSO_TOP + 7 + pose.body_dy, CX + 1, TORSO_TOP + 7 + pose.body_dy),
               "accent", shade=False)
        p.fill(rect(CX - 5, TORSO_BOTTOM + pose.body_dy, CX + 4, TORSO_BOTTOM + pose.body_dy),
               "gear", shade=False)
    if skin.top == "overalls":
        p.fill(rect(CX - 3, TORSO_TOP + 2 + pose.body_dy, CX + 2, TORSO_BOTTOM + pose.body_dy),
               "pants", shade=True, light=False)
        for side in (-2, 2):
            p.fill(rect(CX + side, TORSO_TOP + 1 + pose.body_dy, CX + side - 1 + (side > 0),
                        TORSO_TOP + 1 + pose.body_dy), "pants", shade=False)
    if skin.top == "gi":
        p.fill(line(CX - 5, TORSO_TOP + 1 + pose.body_dy, CX + 4, TORSO_TOP + 1 + pose.body_dy),
               "accent", shade=False)
    if skin.top == "retro":
        p.fill(rect(CX - 4, TORSO_TOP + pose.body_dy, CX + 3, TORSO_TOP + 1 + pose.body_dy),
               "accent", shade=False)

    # Accent styles that ride on the torso.
    top = TORSO_TOP + pose.body_dy
    bottom = TORSO_BOTTOM + pose.body_dy
    if skin.accent_style == "strap":
        p.fill(line(CX - 5, top + 1, CX + 4, bottom - 4), "accent", shade=False)
    if skin.accent_style == "bandana":
        p.fill(rect(CX - 3, top, CX + 2, top + 1), "accent", shade=False)
        p.fill(rect(CX - 1, top + 2, CX, top + 3), "accent", shade=False)
    if skin.accent_style == "neckerchief":
        p.fill(rect(CX - 3, top, CX + 2, top + 1), "accent", shade=False)
        p.fill(rect(CX - 1, top + 2, CX, top + 2), "accent", shade=False)
    if skin.accent_style == "sash":
        p.fill(line(CX - 6, top + 2, CX + 5, bottom - 1), "accent", shade=False)
    if skin.accent_style == "led":
        p.fill(rect(CX - 2, top + 1, CX - 1, top + 1), "accent", shade=False)
        p.fill(rect(CX + 1, top + 1, CX + 2, top + 1), "accent", shade=False)
    if skin.accent_style == "star":
        p.fill(rect(CX - 1, TORSO_BOTTOM - 4 + pose.body_dy, CX, TORSO_BOTTOM - 3 + pose.body_dy),
               "accent", shade=False)
    if skin.gear == "towel":
        side = CX + (SHOULDER_HALF - 3 if angle >= 0 else -SHOULDER_HALF + 2)
        p.fill(rect(side, top + 1, side + 1, top + 5), "accent", shade=True, light=True)

    # Belt above the trousers on everything that shows a waist.
    if not robe and skin.top not in ("chassis", "hazmat", "armour"):
        p.fill(rect(CX - 5, TORSO_BOTTOM + pose.body_dy, CX + 4, TORSO_BOTTOM + pose.body_dy),
               "pants", shade=True, light=False)


# -- head --------------------------------------------------------------------


def _draw_hair_back(p: Painter, skin: Skin, view: str, angle: int, pose: Pose) -> None:
    """Hair that hangs behind the head - drawn before the torso so it tucks in."""
    if skin.hair in ("long", "ponytail", "longbeard"):
        cx = int(CX + pose.lean + (angle if view != SIDE else 0))
        cy = int(HEAD_CY + pose.body_dy)
        back = rect(cx - 5, cy - 2, cx + 4, cy + 5)
        p.fill(back, "hair", shade=True, light=False)
        if skin.hair == "ponytail":
            tail = rect(cx - 1, cy + 4, cx + 1, cy + 8)
            p.fill(tail, "hair", shade=True, light=False)


def _draw_head(p: Painter, skin: Skin, view: str, angle: int, pose: Pose) -> None:
    head = head_cells(view, angle, pose)
    p.fill(head, "skin", light_rows=2)
    cx = int(CX + pose.lean + pose.head_dx + (angle if view != SIDE else 0))
    cy = int(HEAD_CY + pose.body_dy + pose.head_dy)

    _draw_hair(p, skin, view, cx, cy)
    if view != BACK:
        _draw_face(p, skin, view, cx, cy)
    else:
        # A hint of the hairline from behind.
        if skin.hair not in ("bald", "hood"):
            p.fill(rect(cx - 4, cy - 5, cx + 3, cy - 2), "hair", shade=True, light=True)


## Hats that already cover the crown, so no hair is drawn on top of them.
HAT_COVERS_CROWN = False


def _draw_hair(p: Painter, skin: Skin, view: str, cx: int, cy: int) -> None:
    style = skin.hair
    if style == "hood":
        hood = ellipse(cx, cy - 0.5, HEAD_RX + 0.6, HEAD_RY + 0.6)
        p.fill(hood, "shirt", shade=True, light=True)
        face_win = ellipse(cx, cy + 0.8, 3.6, 3.4)
        p.fill(face_win, "skin", shade=False)
        return
    if style == "bald":
        return
    if style == "beard":
        # The beard is the whole look; the crown is bare under the beanie.
        p.fill(rect(cx - 5, cy - 3, cx - 5, cy), "hair", shade=False)
        p.fill(rect(cx + 4, cy - 3, cx + 4, cy), "hair", shade=False)
    elif HAT_COVERS_CROWN:
        pass
    else:
        top = ellipse(cx, cy - 2.4, HEAD_RX - 0.4, 2.6)
        fringe = rect(cx - 4, cy - 5, cx + 3, cy - 3)
        p.fill(top | fringe, "hair", shade=False, light=False)
    # Sideburns, in front of the ears.
    p.fill(rect(cx - 5, cy - 3, cx - 5, cy - 1), "hair", shade=False)
    p.fill(rect(cx + 4, cy - 3, cx + 4, cy - 1), "hair", shade=False)
    if style in ("long", "ponytail"):
        p.fill(rect(cx - 5, cy, cx - 5, cy + 3), "hair", shade=False)
        p.fill(rect(cx + 4, cy, cx + 4, cy + 3), "hair", shade=False)
    if style == "swept":
        p.fill(rect(cx - 3, cy - 4, cx + 2, cy - 4), "hair", shade=True, light=True)
        p.fill(rect(cx + 2, cy - 3, cx + 3, cy - 3), "hair", shade=False)
    if style in ("beard", "longbeard"):
        beard = ellipse(cx, cy + 4.2, 3.4, 2.4)
        p.fill(beard, "hair", shade=True, light=False)
        p.fill(rect(cx - 1, cy + 3, cx, cy + 4), "skin", shade=False)   # mouth stays visible
        if style == "longbeard":
            p.fill(rect(cx - 2, cy + 5, cx + 1, cy + 8), "hair", shade=True, light=False)


def _draw_face(p: Painter, skin: Skin, view: str, cx: int, cy: int) -> None:
    eye_y = int(EYE_Y + (cy - HEAD_CY))
    facing = 1
    if view == SIDE:
        if "eyepatch" in skin.face:
            p.fill(rect(cx + 1, eye_y - 1, cx + 4, eye_y + 1), "shirt", shade=False)
            p.fill(line(cx, eye_y - 3, cx + 4, eye_y + 2), "eye", shade=False)
            return
        if "mask" in skin.face:
            p.fill(rect(cx - 4, eye_y - 2, cx + 5, eye_y + 4), "hair", shade=False)
            p.fill(rect(cx + 1, eye_y, cx + 3, eye_y + 1), "skin", shade=False)
        elif "visor" in skin.face or "goggles" in skin.face:
            p.fill(rect(cx - 3, eye_y - 2, cx + 5, eye_y + 1), "eye", shade=False)
            p.fill(rect(cx - 3, eye_y - 2, cx + 5, eye_y - 2), "accent", shade=False)
        else:
            p.fill(rect(cx + 1, eye_y, cx + 2, eye_y + 1), "eye", shade=False)
        if "moustache" in skin.face:
            p.fill(rect(cx + 1, eye_y + 3, cx + 4, eye_y + 3), "hair", shade=False)
        return

    if "eyepatch" in skin.face:
        p.fill(rect(cx - 4, eye_y - 1, cx - 2, eye_y + 1), "hair", shade=False)
        p.fill(line(cx - 6, eye_y - 3, cx - 2, eye_y + 2), "eye", shade=False)
        p.fill(rect(cx + 2, eye_y, cx + 3, eye_y + 1), "eye", shade=False)
    elif "shades" in skin.face:
        p.fill(rect(cx - 5, eye_y - 1, cx + 4, eye_y + 1), "eye", shade=False)
        p.fill(rect(cx - 5, eye_y - 1, cx - 4, eye_y), "shine", shade=False)
    elif "visor" in skin.face and skin.hat == "helmet":
        p.fill(rect(cx - 4, eye_y - 1, cx + 3, eye_y + 1), "eye", shade=False)
        p.fill(rect(cx - 4, eye_y - 1, cx + 3, eye_y - 1), "cap", shade=False)
    elif "visor" in skin.face:
        p.fill(rect(cx - 4, eye_y - 1, cx + 3, eye_y + 1), "eye", shade=False)
        p.fill(rect(cx - 4, eye_y - 1, cx + 3, eye_y - 1), "accent", shade=False)
    elif "mask" in skin.face:
        p.fill(rect(cx - 5, eye_y - 3, cx + 4, eye_y + 4), "hair", shade=False)
        p.fill(rect(cx - 5, eye_y - 1, cx + 4, eye_y + 1), "skin", shade=False)
        p.fill(rect(cx - 4, eye_y, cx - 3, eye_y), "eye", shade=False)
        p.fill(rect(cx + 3, eye_y, cx + 4, eye_y), "eye", shade=False)
    elif "goggles" in skin.face:
        p.fill(rect(cx - 4, eye_y - 1, cx + 3, eye_y + 1), "eye", shade=False)
        p.fill(rect(cx - 4, eye_y - 1, cx + 3, eye_y - 1), "accent", shade=False)
        p.fill(rect(cx - 1, eye_y, cx, eye_y), "gear", shade=False)
    else:
        p.fill(rect(cx - 4, eye_y, cx - 3, eye_y + 1), "eye", shade=False)
        p.fill(rect(cx + 2, eye_y, cx + 3, eye_y + 1), "eye", shade=False)
    if "beard" in skin.face:
        p.fill(rect(cx - 3, eye_y + 3, cx + 2, eye_y + 5), "hair", shade=False)
    elif "moustache" in skin.face:
        p.fill(rect(cx - 2, eye_y + 3, cx + 1, eye_y + 3), "hair", shade=False)
    else:
        p.fill(rect(cx - 1, eye_y + 4, cx, eye_y + 4), "eye", shade=False)


# -- hats --------------------------------------------------------------------


def _draw_hat(p: Painter, skin: Skin, view: str, angle: int, pose: Pose) -> None:
    style = skin.hat
    if style == "none":
        return
    cx = int(CX + pose.lean + pose.head_dx + (angle if view != SIDE else 0))
    cy = int(HEAD_CY + pose.body_dy + pose.head_dy)
    crown = cy - 5

    if style in ("cap", "retrocap"):
        p.fill(rect(cx - 5, crown, cx + 4, crown + 2), "cap", shade=True, light=True)
        p.fill(rect(cx - 6, crown + 2, cx + 5, crown + 2), "cap", shade=True, light=False)
        p.fill(rect(cx - 6, crown + 2, cx + 5, crown + 2), "accent" if style == "retrocap" else "cap",
               shade=False)
    elif style == "flat":
        p.fill(rect(cx - 5, crown + 1, cx + 4, crown + 2), "cap", shade=True, light=True)
        p.fill(rect(cx - 7, crown + 3, cx + 6, crown + 3), "cap", shade=True, light=False)
        p.fill(rect(cx - 5, crown + 1, cx + 4, crown + 1), "accent", shade=False)
    elif style == "beanie":
        p.fill(ellipse(cx, cy - 4.0, 6.0, 3.6), "cap", shade=True, light=True)
        p.fill(rect(cx - 6, cy - 4, cx + 5, cy - 3), "accent", shade=False)
        p.fill(ellipse(cx, cy - 8.0, 1.5, 1.5), "accent", shade=False)
    elif style == "tricorn":
        p.fill(rect(cx - 8, cy - 5, cx + 7, cy - 4), "cap", shade=False)      # brim
        p.fill(rect(cx - 8, cy - 7, cx - 7, cy - 4), "cap", shade=False)      # turned-up points
        p.fill(rect(cx + 6, cy - 7, cx + 7, cy - 4), "cap", shade=False)
        p.fill(rect(cx - 5, cy - 9, cx + 4, cy - 5), "cap", shade=True, light=True)  # crown
        p.fill(rect(cx - 5, cy - 6, cx + 4, cy - 5), "accent", shade=False)   # hat band
        p.fill(rect(cx - 1, cy - 8, cx, cy - 7), "accent", shade=False)       # cockade
    elif style == "cowboy":
        p.fill(rect(cx - 8, cy - 3, cx + 7, cy - 2), "cap", shade=True, light=True)
        p.fill(rect(cx - 4, cy - 7, cx + 3, cy - 2), "cap", shade=True, light=True)
        p.fill(rect(cx - 4, cy - 3, cx + 3, cy - 3), "accent", shade=False)
    elif style == "wizard":
        cone: Cells = set()
        for row in range(0, 10):
            y = cy - 4 - row
            width = max(0, 5 - row // 2)
            bend = 0
            if row >= 5:
                bend = -1
            if row >= 8:
                bend = -2
            for x in range(cx - width + bend, cx + width + 1 + bend):
                cone.add((x, y))
        p.fill(cone, "cap", shade=True, light=True, light_rows=2)
        p.fill(rect(cx - 6, cy - 4, cx + 5, cy - 3), "cap", shade=True, light=True)
        p.fill(rect(cx - 6, cy - 3, cx + 5, cy - 3), "accent", shade=False)
        p.fill(rect(cx - 2, cy - 13, cx - 1, cy - 13), "shine", shade=False)
    elif style == "headband":
        p.fill(rect(cx - 6, cy - 4, cx + 5, cy - 3), "accent", shade=True, light=False)
        p.fill(rect(cx - 8, cy - 3, cx - 7, cy), "accent", shade=True, light=False)
    elif style == "helmet":
        p.fill(ellipse(cx, cy - 1.2, HEAD_RX - 0.2, HEAD_RY - 0.5), "cap", shade=True,
               light=True, light_rows=2)
        p.fill(rect(cx - 4, cy - 3, cx + 3, cy + 2), "cap", shade=False)
        p.fill(rect(cx - 4, cy - 1, cx + 3, cy), "eye", shade=False)          # eye slit
        p.fill(rect(cx - 3, cy - 1, cx + 1, cy - 1), "shine", shade=False)    # glint
        p.fill(rect(cx - 5, cy - 2, cx + 4, cy + 1), "cap", shade=False)      # cheek guards
        p.fill(rect(cx - 1, cy + 2, cx, cy + 3), "cap", shade=False)          # nasal bar
        p.fill(rect(cx - 4, cy - 3, cx + 3, cy - 3), "accent", shade=False)   # brow band
        p.fill(rect(cx - 1, cy - 8, cx, cy - 6), "accent", shade=True, light=True)   # plume
        p.fill(line(cx, cy - 9, cx + 3, cy - 11), "accent", shade=True, light=False)
        p.fill(rect(cx - 2, cy + 4, cx + 1, cy + 4), "cap", shade=True, light=True)
    elif style == "toque":
        p.fill(rect(cx - 5, cy - 7, cx + 4, cy - 2), "cap", shade=True, light=True, light_rows=1)
        p.fill(ellipse(cx, cy - 9.5, 6.6, 4.0), "cap", shade=True, light=True, light_rows=1)
        p.fill(ellipse(cx - 3, cy - 11.0, 2.4, 2.0), "cap", shade=False)
        p.fill(ellipse(cx + 3, cy - 11.0, 2.4, 2.0), "cap", shade=False)
        p.fill(rect(cx - 6, cy - 2, cx + 5, cy - 1), "cap", shade=False)
    elif style == "antenna":
        p.fill(rect(cx - 5, crown - 1, cx + 4, crown + 2), "cap", shade=True, light=True)
        p.fill(rect(cx - 6, crown, cx - 6, crown + 2), "cap", shade=False)
        p.fill(line(cx + 3, crown - 1, cx + 5, crown - 5), "gear", shade=False)
        p.fill(ellipse(cx + 5.5, crown - 5.5, 1.1, 1.1), "accent", shade=False)
    elif style == "bubble":
        dome = ellipse(cx, cy, HEAD_RX + 1.4, HEAD_RY + 1.6)
        inner = ellipse(cx, cy, HEAD_RX + 0.2, HEAD_RY + 0.4)
        ring = dome - inner
        p.fill(ring, "cap", shade=True, light=True, dark_at=1.2)
        p.fill(rect(cx - 8, cy + 4, cx + 7, cy + 5), "cap", shade=True, light=False)
        p.fill(rect(cx - 5, cy + 6, cx + 4, cy + 6), "accent", shade=False)
        p.fill(ellipse(cx - 3.5, cy - 3.5, 1.3, 1.3), "shine", shade=False)
        p.fill(rect(cx + 3, cy - 1, cx + 4, cy + 1), "shine", shade=False)
    elif style == "plume":
        p.fill(rect(cx - 6, cy - 8, cx + 5, cy - 6), "accent", shade=True, light=True)


# -- held gear ---------------------------------------------------------------


def _draw_gear(p: Painter, skin: Skin, view: str, angle: int, pose: Pose) -> None:
    if skin.gear in ("none", "towel", "pack"):
        return
    if skin.gear == "club" and not pose.hand_grip:
        return  # the golfer only holds the club while swinging, as in the stock art
    hands = [hand_cells(view, angle, pose, side) for side in (-1, 1)]
    hand = hands[1] if hands[1] else (hands[0] if hands[0] else set())
    if not hand:
        return
    hx = sum(x for x, _ in hand) // max(len(hand), 1)
    hy = max(y for _, y in hand)

    if pose.hand_grip and skin.gear not in ("briefcase",):
        # Both hands are on the grip: the shaft leaves the hands and the head
        # swings through the arc the pose asks for.
        cdx, cdy = pose.club
        tip_x, tip_y = hx + cdx, hy + cdy
        shaft = thick(line(hx, hy, tip_x, tip_y), 0)
        p.fill(shaft, "gear", shade=False)
        if cdx >= 0:
            head = rect(tip_x - 1, tip_y - 1, tip_x + 3, tip_y + 2)
        else:
            head = rect(tip_x - 4, tip_y - 1, tip_x, tip_y + 2)
        p.fill(head, "gear", shade=True, light=False)
        return

    if skin.gear == "staff":
        sx = hx + (2 if view != SIDE or angle >= 0 else -3)
        p.fill(rect(sx - 1, hy - 13, sx, hy + 6), "gear", shade=False)
        p.fill(ellipse(sx - 0.5, hy - 14.5, 1.8, 1.8), "accent", shade=True, light=True)
        return
    if skin.gear == "axe":
        ax = hx + 2
        p.fill(rect(ax - 1, hy - 10, ax, hy + 5), "gear", shade=False)
        p.fill(rect(ax - 4, hy - 11, ax + 1, hy - 8), "gear", shade=True, light=True)
        return
    if skin.gear == "cutlass":
        p.fill(line(hx - 1, hy + 4, hx + 6, hy - 4), "gear", shade=False)
        p.fill(rect(hx - 2, hy + 3, hx + 1, hy + 4), "gear", shade=True, light=False)
        p.fill(rect(hx - 4, hy + 2, hx + 1, hy + 3), "accent", shade=False)
        return
    if skin.gear == "sword":
        sx = hx + 2
        p.fill(rect(sx - 1, hy - 11, sx, hy + 2), "gear", shade=False)
        p.fill(rect(sx - 1, hy - 12, sx, hy - 11), "shine", shade=False)
        p.fill(rect(sx - 3, hy + 2, sx + 2, hy + 3), "accent", shade=False)
        return
    if skin.gear == "spanner":
        p.fill(rect(hx - 1, hy - 6, hx, hy + 5), "gear", shade=False)
        p.fill(rect(hx - 4, hy - 8, hx + 3, hy - 6), "gear", shade=True, light=True)
        return
    if skin.gear == "whisk":
        p.fill(rect(hx - 1, hy - 8, hx, hy + 2), "gear", shade=False)
        p.fill(ellipse(hx - 0.5, hy - 10.0, 2.4, 2.4), "gear", shade=False)
        return
    if skin.gear == "briefcase":
        p.fill(rect(hx + 1, hy - 2, hx + 8, hy + 4), "gear", shade=True, light=False)
        p.fill(rect(hx + 3, hy - 4, hx + 6, hy - 2), "gear", shade=False)
        return
    if skin.gear == "lasso":
        p.fill(ellipse(hx + 6.0, hy - 2.0, 2.6, 3.2), "gear", shade=False)
        return

    # Default: a club resting beside the golfer.
    p.fill(line(hx, hy, hx + 1, hy + 7), "gear", shade=False)
    p.fill(rect(hx - 3, hy + 7, hx + 2, hy + 8), "gear", shade=True, light=False)


# ---------------------------------------------------------------------------
# The retro skin: drawn at 24x24 and doubled up
# ---------------------------------------------------------------------------


def draw_retro(skin: Skin, direction: str, anim: str, frame: int) -> Painter:
    global W, H, CX, HEAD_CY, HEAD_RX, HEAD_RY, EYE_Y  # noqa: PLW0603
    global TORSO_TOP, TORSO_BOTTOM, SHOULDER_HALF  # noqa: PLW0603
    global WAIST_HALF, LEG_TOP, FOOT_Y, SHOE_Y, LEG_W, LEG_GAP  # noqa: PLW0603
    view, facing = view_for(direction)
    pose = pose_for(anim, frame)
    original = (W, H, CX, HEAD_CY, HEAD_RX, HEAD_RY, EYE_Y, TORSO_TOP, TORSO_BOTTOM,
                SHOULDER_HALF, WAIST_HALF, LEG_TOP, FOOT_Y, SHOE_Y, LEG_W, LEG_GAP)
    W = H = 24
    CX = 12
    try:
        _set_retro_metrics()
        p = Painter(24, 24)
        _draw_retro_small(p, skin, view, facing, pose)
        p.outline_silhouette()
    finally:
        (W, H, CX, HEAD_CY, HEAD_RX, HEAD_RY, EYE_Y, TORSO_TOP, TORSO_BOTTOM,
         SHOULDER_HALF, WAIST_HALF, LEG_TOP, FOOT_Y, SHOE_Y, LEG_W, LEG_GAP) = original
    return p.scaled(2)


def _set_retro_metrics() -> None:
    global HEAD_CY, HEAD_RX, HEAD_RY, EYE_Y, TORSO_TOP, TORSO_BOTTOM, SHOULDER_HALF
    global WAIST_HALF, LEG_TOP, FOOT_Y, SHOE_Y, LEG_W, LEG_GAP

    HEAD_CY = 7.0
    HEAD_RX = 3.2
    HEAD_RY = 3.0
    EYE_Y = 6
    TORSO_TOP = 10
    TORSO_BOTTOM = 15
    SHOULDER_HALF = 3
    WAIST_HALF = 3
    LEG_TOP = 16
    FOOT_Y = 20
    SHOE_Y = 20
    LEG_W = 2
    LEG_GAP = 0


def _draw_retro_small(p: Painter, skin: Skin, view: str, angle: int, pose: Pose) -> None:
    _draw_legs(p, skin, view, angle, pose)
    _draw_torso(p, skin, view, angle, pose)
    _draw_head(p, skin, view, angle, pose)
    _draw_hat(p, skin, view, angle, pose)
    if skin.gear == "club":
        hx = CX + 3 + angle
        p.fill(rect(hx, TORSO_BOTTOM - 1, hx, TORSO_BOTTOM + 3), "gear", shade=False)


# ---------------------------------------------------------------------------
# Writing the skins
# ---------------------------------------------------------------------------


def render_skin(skin: Skin, root: str, drawn: set[str]) -> int:
    palette = {part: ramp(hexvalue) for part, hexvalue in skin.palette.items()}
    count = 0
    for direction in DIRECTIONS:
        for anim, frames in ANIM_FRAMES.items():
            for frame in range(frames):
                painter = draw_golfer(skin, direction, anim, frame)
                pixels = painter.to_pixels(palette, FIXED)
                frame_root = os.path.join(root, "animations", anim, direction,
                                          "frame_%03d" % frame)
                write_png(frame_root + ".png", pixels)
                write_layer(frame_root + LAYER_SUFFIX, painter.to_layer())
                # What the skin actually draws: the parts its layer holds, and
                # so the parts the colour pickers are offered. A palette entry
                # an outfit never uses (a towel drawn as trim, boots under a
                # robe) is not one of them.
                for row in painter.part:
                    for part in row:
                        if part is not None:
                            drawn.add(part)
                count += 1
    return count


def skin_record(skin: Skin, root: str, drawn: set[str]) -> dict:
    return {
        "id": skin.id,
        "name": skin.name,
        "description": skin.description,
        "root": root,
        "legacy": False,
        "customizable": [part for part in CUSTOM_PARTS if part in drawn],
        "colors": {part: skin.palette[part] for part in CUSTOM_PARTS if part in skin.palette},
        "spawn_tiers": skin.spawn_tiers,
        "frames": {anim: frames for anim, frames in ANIM_FRAMES.items()},
        "directions": DIRECTIONS,
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
    # highlights - are drawn in the fixed colours every skin shares.
    reference = art.palette.get(part)
    if reference is None:
        fixed = FIXED.get(part)
        if fixed is None:
            return 0
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
    sprite_root = os.path.join(repo, "assets", "sprites", "golfer", "skins")
    data_path = os.path.join(repo, "data", "golfer_skins.json")

    skins: list[dict] = []
    total = 0
    for skin in SKINS:
        root = "res://assets/sprites/golfer/skins/%s" % skin.id
        drawn: set[str] = set()
        count = render_skin(skin, os.path.join(sprite_root, skin.id), drawn)
        skins.append(skin_record(skin, root, drawn))
        total += count
        undrawn = [part for part in skin.palette if part not in drawn]
        note = "  (drawn without %s)" % ", ".join(undrawn) if undrawn else ""
        print("  %-12s %3d frames + layers, %d parts%s" % (skin.id, count, len(drawn), note))
    for art in LEGACY_ART:
        art_drawn: set[str] = set()
        count = render_legacy_layers(art, repo, art_drawn)
        if not count:
            # No hand-made art on disk for this one: keep the record so the
            # tier it stands for still has a skin to name.
            art_drawn.update(art.parts)
        skins.append(legacy_record(art, art_drawn))
        print("  %-12s %3d layers for the hand-made art" % (art.id, count))
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

    print("Wrote %d frames + layers across %d themed skins (+%d hand-made sets)"
          % (total, len(SKINS), len(LEGACY_ART)))
    print("Wrote %s" % data_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
