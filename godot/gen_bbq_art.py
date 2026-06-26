#!/usr/bin/env python3
"""Procedural pixel-art generator for the 1-4 串烤肉 (BBQ) level.

Produces, in godot/assets/:
  bbq_ingredients.png   900x150  6 frames: 牛肉 辣椒 洋葱 蘑菇 馒头 大葱
  bbq_flip.png          300x150  2 frames: 翻面提示 / 翻面完成
  bbq_stick.png          36x260  vertical wooden skewer
  bbq_full_skewer.png   120x430  a finished skewer (order-panel decor)

Everything is drawn on a small logical grid then NEAREST-upscaled so the
edges stay chunky-pixel, matching the level's TEXTURE_FILTER_NEAREST tiles.
"""
import os
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "assets")
S = 30          # logical tile size
SCALE = 5       # -> 150px frames

# --- palette ---------------------------------------------------------------
INK   = (38, 22, 14, 255)      # dark outline
INK2  = (24, 14, 9, 255)
WHITE = (255, 255, 255, 255)

def new_tile():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))

def ink_ellipse(d, box, fill, outline=INK, ow=1):
    """Ellipse with a 1px dark outline drawn by expanding the box."""
    x0, y0, x1, y1 = box
    d.ellipse((x0 - ow, y0 - ow, x1 + ow, y1 + ow), fill=outline)
    d.ellipse(box, fill=fill)

def ink_poly(d, pts, fill, outline=INK):
    d.polygon(pts, fill=outline)          # cheap outline: dark first, fill smaller-ish
    d.polygon(pts, fill=fill, outline=outline)

def ink_rrect(d, box, r, fill, outline=INK, ow=1):
    x0, y0, x1, y1 = box
    d.rounded_rectangle((x0 - ow, y0 - ow, x1 + ow, y1 + ow), r + ow, fill=outline)
    d.rounded_rectangle(box, r, fill=fill)


# ---------------------------------------------------------------------------
# Ingredients (each returns a 30x30 RGBA tile)
# ---------------------------------------------------------------------------
def beef():
    img = new_tile(); d = ImageDraw.Draw(img)
    ink_rrect(d, (5, 8, 24, 24), 4, (198, 40, 40, 255))      # red cube
    d.rounded_rectangle((7, 10, 22, 15), 3, fill=(229, 75, 75, 255))  # top highlight
    # marbling fat streaks
    for (a, b) in [(9, 18), (13, 21), (17, 17)]:
        d.line((a, b, a + 4, b - 3), fill=(247, 200, 200, 255), width=1)
    d.point((20, 12), fill=WHITE)
    return img

def pepper():
    img = new_tile(); d = ImageDraw.Draw(img)
    body = [(15, 7), (21, 11), (22, 18), (17, 25), (13, 24), (11, 17), (12, 10)]
    ink_poly(d, body, (255, 122, 26, 255))
    d.line((15, 11, 14, 22), fill=(255, 178, 110, 255), width=1)   # highlight
    d.polygon([(20, 14), (22, 18), (18, 22)], fill=(214, 92, 12, 255))  # shade
    d.line((14, 8, 16, 4), fill=(56, 142, 60, 255), width=2)       # stem
    d.point((16, 4), fill=(76, 175, 80, 255))
    return img

def onion():
    img = new_tile(); d = ImageDraw.Draw(img)
    ink_ellipse(d, (7, 9, 23, 25), (123, 31, 162, 255))
    for off in (-4, 0, 4):                                         # layer arcs
        d.arc((11 + off, 11, 19 + off, 24), 250, 290, fill=(186, 104, 200, 255), width=1)
    d.line((15, 9, 13, 5), fill=(120, 180, 90, 255), width=1)      # sprout
    d.line((15, 9, 17, 5), fill=(120, 180, 90, 255), width=1)
    d.line((13, 25, 17, 25), fill=(225, 210, 180, 255), width=1)   # root
    d.point((12, 13), fill=(214, 160, 224, 255))
    return img

def mushroom():
    img = new_tile(); d = ImageDraw.Draw(img)
    ink_rrect(d, (12, 15, 18, 25), 2, (224, 206, 178, 255))        # stem
    d.pieslice((5, 7, 25, 23), 180, 360, fill=INK)                 # cap outline
    d.pieslice((6, 8, 24, 22), 180, 360, fill=(109, 76, 65, 255))  # cap
    d.pieslice((8, 10, 22, 18), 180, 360, fill=(140, 100, 80, 255))
    for (a, b) in [(11, 12), (16, 10), (20, 13)]:                  # spots
        d.ellipse((a, b, a + 2, b + 2), fill=(232, 220, 200, 255))
    return img

def mantou():
    img = new_tile(); d = ImageDraw.Draw(img)
    ink_rrect(d, (6, 9, 24, 25), 8, (253, 243, 192, 255))         # bun dome
    d.rounded_rectangle((8, 11, 21, 17), 6, fill=(255, 252, 224, 255))  # highlight
    d.line((9, 24, 21, 24), fill=(228, 196, 120, 255), width=1)   # golden base
    d.point((11, 13), fill=WHITE)
    return img

def leek():
    img = new_tile(); d = ImageDraw.Draw(img)
    ink_rrect(d, (12, 12, 18, 26), 2, (245, 245, 235, 255))       # white stalk
    ink_rrect(d, (12, 4, 18, 14), 2, (56, 142, 60, 255))          # green top
    d.line((15, 4, 15, 1), fill=(56, 142, 60, 255), width=2)      # split tines
    d.line((13, 5, 12, 2), fill=(76, 175, 80, 255), width=1)
    d.line((17, 5, 18, 2), fill=(76, 175, 80, 255), width=1)
    d.line((15, 14, 15, 25), fill=(225, 230, 215, 255), width=1)  # highlight
    return img

INGREDIENTS = [beef, pepper, onion, mushroom, mantou, leek]


# ---------------------------------------------------------------------------
# Sprite-sheet assembly
# ---------------------------------------------------------------------------
def build_ingredient_sheet():
    sheet = Image.new("RGBA", (S * 6, S), (0, 0, 0, 0))
    for i, fn in enumerate(INGREDIENTS):
        sheet.paste(fn(), (i * S, 0))
    sheet = sheet.resize((S * 6 * SCALE, S * SCALE), Image.NEAREST)
    sheet.save(os.path.join(OUT, "bbq_ingredients.png"))


def build_flip_sheet():
    sheet = Image.new("RGBA", (S * 2, S), (0, 0, 0, 0))

    # frame 0: rotation arrows (flip prompt)
    f0 = new_tile(); d = ImageDraw.Draw(f0)
    d.arc((7, 7, 23, 23), 40, 300, fill=(255, 107, 43, 255), width=3)
    d.polygon([(22, 6), (26, 11), (19, 12)], fill=(255, 193, 7, 255))   # arrowhead
    d.polygon([(8, 24), (4, 19), (11, 18)], fill=(255, 193, 7, 255))
    d.ellipse((13, 13, 17, 17), fill=(255, 193, 7, 255))               # center spark
    sheet.paste(f0, (0, 0))

    # frame 1: success check (flip done)
    f1 = new_tile(); d = ImageDraw.Draw(f1)
    ink_ellipse(d, (6, 6, 24, 24), (255, 193, 7, 255))
    d.ellipse((9, 9, 21, 21), fill=(255, 224, 130, 255))
    d.line((11, 16, 14, 19), fill=INK2, width=2)                       # check
    d.line((14, 19, 20, 11), fill=INK2, width=2)
    sheet.paste(f1, (S, 0))

    sheet = sheet.resize((S * 2 * SCALE, S * SCALE), Image.NEAREST)
    sheet.save(os.path.join(OUT, "bbq_flip.png"))


def build_stick():
    w, h = 9, 65
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    # shaft
    d.rectangle((2, 0, 6, h - 8), fill=INK)
    d.rectangle((3, 0, 6, h - 9), fill=(169, 116, 63, 255))
    d.line((4, 1, 4, h - 10), fill=(206, 160, 110, 255))              # grain highlight
    d.line((6, 1, 6, h - 10), fill=(120, 78, 40, 255))               # grain shade
    # pointed tip
    d.polygon([(2, h - 9), (7, h - 9), (4, h - 1)], fill=INK)
    d.polygon([(3, h - 9), (6, h - 9), (4, h - 3)], fill=(169, 116, 63, 255))
    img = img.resize((w * 4, h * 4), Image.NEAREST)
    img.save(os.path.join(OUT, "bbq_stick.png"))


def build_full_skewer():
    """A finished skewer with 5 threaded ingredients for the order panel."""
    cell = 30
    cols, rows = 4, 14
    img = Image.new("RGBA", (cols * cell, rows * cell), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx = cols * cell // 2
    # stick
    d.rectangle((cx - 3, 6, cx + 3, rows * cell - 6), fill=INK)
    d.rectangle((cx - 2, 6, cx + 2, rows * cell - 7), fill=(169, 116, 63, 255))
    d.polygon([(cx - 4, rows * cell - 8), (cx + 4, rows * cell - 8),
               (cx, rows * cell - 1)], fill=(169, 116, 63, 255))
    # thread 5 ingredients up the stick
    order = [beef, pepper, onion, mushroom, mantou]
    big = cell * 2
    for i, fn in enumerate(order):
        tile = fn().resize((big, big), Image.NEAREST)
        y = 20 + i * (big - 14)
        img.alpha_composite(tile, (cx - big // 2, y))
    img = img.resize((img.width * 2, img.height * 2), Image.NEAREST)
    img.save(os.path.join(OUT, "bbq_full_skewer.png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    build_ingredient_sheet()
    build_flip_sheet()
    build_stick()
    build_full_skewer()
    print("done ->", OUT)
