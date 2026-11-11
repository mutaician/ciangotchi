#!/usr/bin/env python3
"""Draw the Saiyan forms as text grids in tools/sprites/.

Body sprites are 32x32, bar icons (<form>_icon_*) are 16x16. Grid letters:
  X  body pixel   (tinted with the theme foreground)
  A  accent pixel (hair, aura, ki: tinted with the form's colour)
  .  empty
Every form is the same body with its own hair, eyes and aura, so a new form
is one entry in FORMS. Run gen-sprites.sh afterwards to make the PNGs.

  python3 tools/make-forms.py            write every grid
  python3 tools/make-forms.py --preview out.png   also render a colour sheet
"""
import os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "sprites")
N = 32


def mirror(half):
    out = []
    for r in half:
        assert len(r) == 16, (len(r), r)
        out.append(r + r[::-1])
    return out


def art(s):
    return s.strip("\n").split("\n")


def new(n=N):
    return [["."] * n for _ in range(n)]


def put(g, rows, y0=0, x0=0):
    """Paste rows; '_' erases, '.' leaves what is there."""
    for dy, row in enumerate(rows):
        for dx, ch in enumerate(row):
            y, x = y0 + dy, x0 + dx
            if ch == "." or not (0 <= y < len(g) and 0 <= x < len(g)):
                continue
            g[y][x] = "." if ch == "_" else ch


def dots(g, pts, ch="X"):
    for x, y in pts:
        if 0 <= y < len(g) and 0 <= x < len(g):
            g[y][x] = "." if ch == "_" else ch


# --- hair (rows 0-14, the last three are the widow's-peak hairline) -----------

HAIR = {
    # Upswept flame, soft outline: base and god.
    "flame": mirror(art("""
...............A
..............AA
..............AA
.............AAA
..........A..AAA
..........AA.AAA
.......A..AAAAAA
.......AA.AAAAAA
.......AAAAAAAAA
......AAAAAAAAAA
......AAAAAAAAAA
.......AAAAAAAAA
.......AAA...AAA
.......AA.....AA
.......A.......A
""")),
    # Rigid blades: super saiyan and blue.
    "blades": mirror(art("""
...............A
..............AA
...........A..AA
...........A.AAA
..........AA.AAA
.......A..AAAAAA
.......A.AAAAAAA
.......AAAAAAAAA
......AAAAAAAAAA
.....AAAAAAAAAAA
.....AAAAAAAAAAA
......AAAAAAAAAA
.......AAA...AAA
.......AA.....AA
.......A.......A
""")),
    # Deeper cuts, longer blades: super saiyan 2, majin, ultra ego.
    "spikes": mirror(art("""
..........A....A
..........A...AA
..........AA..AA
......A...AA.AAA
......A..AAA.AAA
......AA.AAAAAAA
.......A.AAAAAAA
....A..AAAAAAAAA
....AA.AAAAAAAAA
.....AAAAAAAAAAA
.....AAAAAAAAAAA
......AAAAAAAAAA
.......AAA...AAA
.......AA.....AA
.......A.......A
""")),
}

# --- face (rows 12-19) ---------------------------------------------------------

FACE = mirror(art("""
........XXXXXXXX
........XXXXXXXX
........XX__XXXX
.......XXX____XX
.......XXXXXXXXX
........XXXXXXXX
.........XXXXX__
..........XXXXXX
"""))


def face(kind, eyes):
    f = [list(r) for r in FACE]
    def e(x, y):          # erase, mirrored
        f[y][x] = "_"; f[y][31 - x] = "_"
    def s(x, y):
        f[y][x] = "X"; f[y][31 - x] = "X"
    if eyes == "ego":     # no brows, a heavy ridge: wider, taller eyes
        e(12, 2)
    if eyes == "majin":   # dark rims under the eyes
        e(10, 4); e(11, 4)
    if kind == "sleep":   # eyes shut
        s(10, 2); s(11, 2)
    if kind == "eat":     # mouth open
        e(14, 5); e(15, 5)
    if kind == "chew":
        s(14, 6); s(15, 6); e(14, 5); e(15, 5)
    if kind == "rage":    # shouting
        for x in (13, 14, 15):
            e(x, 5); e(x, 6)
    if kind == "idle":    # the smirk: one corner up
        f[5][18] = "_"
    return ["".join(r) for r in f]


MAJIN_M = art("""
_...._
__..__
_.__._
""")  # stamped on the forehead

# --- bodies (rows 20-31) --------------------------------------------------------

TORSO_CROSSED = mirror(art("""
.............XXX
.........XXXXXXX
.......XXXXXXXXX
.......XX.......
.......XXXXXXXXX
........XXXXXXXX
..........XXXXXX
"""))
TORSO_PLAIN = mirror(art("""
.............XXX
.........XXXXXXX
.........XXXXXXX
.........XXXXXXX
..........XXXXXX
..........XXXXXX
..........XXXXXX
"""))
TORSO_RAGE = mirror(art("""
.............XXX
........XXXXXXXX
......XXXXXXXXXX
.....XXX.XXXXXXX
....XXX..XXXXXXX
...XXXX..XXXXXXX
...XXX....XXXXXX
"""))
LEGS_STAND = mirror(art("""
.........XXXXX..
.........XXXXX..
.........XXXXX..
........XXXXXX..
.......XXXXXXX..
"""))
# The hover: one leg straight, the other tucked up.
LEGS_FLY = art("""
..........XXXXX..XXXXX..........
..........XXXX...XXXXX..........
..........XXXX....XXXX..........
..........XXXX.....XXX..........
.........XXXXX..................
""")
LEGS_WIDE = mirror(art("""
.........XXXXXX.
........XXXXX...
.......XXXXX....
......XXXXXX....
.....XXXXXXX....
"""))
# Saiyan-saga shoulder pads, worn by the base form only.
PADS = mirror(art("""
....X...........
....XXX.........
.....XXXXX......
"""))

ARM_DOWN = [(7, 21), (8, 21), (6, 22), (7, 22), (6, 23), (7, 23), (6, 24), (7, 24),
            (6, 25), (7, 25), (5, 26), (6, 26), (7, 26), (5, 27), (6, 27), (7, 27)]


MEAT = [(x, 12) for x in (27, 28, 29)] + [(x, y) for y in (13, 14, 15) for x in range(26, 31)] \
    + [(x, 16) for x in (27, 28, 29)] + [(28, 17), (28, 18)] \
    + [(x, y) for y in (19, 20) for x in (27, 28, 29)] + [(x, 21) for x in range(23, 29)]
BITE = [(26, 13), (26, 14), (27, 12), (27, 13), (26, 15)]

ZED_SMALL = [(27, 8), (28, 8), (28, 9), (27, 10), (28, 10)]
ZED_BIG = [(26, 3), (27, 3), (28, 3), (29, 3), (28, 4), (27, 5), (26, 6), (27, 6), (28, 6), (29, 6)]

BOLTS = (  # super saiyan 2 lightning, one set per frame
    [(3, 6), (4, 7), (3, 8), (4, 9), (28, 16), (29, 17), (28, 18), (27, 19)],
    [(28, 5), (27, 6), (28, 7), (27, 8), (3, 15), (2, 16), (3, 17), (4, 18)],
)

# --- aura -----------------------------------------------------------------------


def aura(g, level, frame, floor=True):
    """Flickering outline two pixels off the silhouette, in the accent colour."""
    if level <= 0:
        return
    n = len(g)
    filled = [(x, y) for y in range(n) for x in range(n) if g[y][x] != "."]

    def dist(x, y):
        return min(max(abs(x - fx), abs(y - fy)) for fx, fy in filled)

    for y in range(n - 1):
        for x in range(n):
            if g[y][x] != "." or (floor and 9 <= x <= 22 and y >= 20):
                continue
            d = dist(x, y)
            dash = (x + y + frame * 3) % 6     # diagonal dashes that crawl
            if d == 2 and (level >= 3 or dash < (3 if level == 1 else 4)):
                g[y][x] = "a"
            elif d == 4 and level >= 3 and dash < 2:
                g[y][x] = "a"
            elif d == 4 and level >= 4 and dash < 4:
                g[y][x] = "a"
    for row in g:
        for i, ch in enumerate(row):
            if ch == "a":
                row[i] = "A"


# --- forms ----------------------------------------------------------------------

FORMS = {
    #  name     hair      eyes     aura  extras           preview colour
    "base":  ("flame",  "normal", 0, ("pads",),          "#4b5366"),
    "ssj":   ("blades", "normal", 1, (),                 "#ffd23c"),
    "ssj2":  ("spikes", "normal", 2, ("bolts",),         "#ffd23c"),
    "god":   ("flame",  "normal", 1, (),                 "#ff4d5e"),
    "blue":  ("blades", "normal", 2, (),                 "#3fb8ff"),
    "ego":   ("spikes", "ego",    3, (),                 "#c04dff"),
    "majin": ("spikes", "majin",  2, ("bolts", "m"),     "#ffd23c"),
}
ANIMS = ("idle", "walk", "fly", "eat", "sleep", "rage")


def build(form, anim, frame):
    hair, eyes, level, extras, _ = FORMS[form]
    g = new()
    bob = 1 if frame == 1 and anim in ("idle", "walk", "rage") else 0
    if anim == "sleep":
        bob = 1

    if anim == "fly":
        return build_fly(form, frame)
    torso = {"idle": TORSO_CROSSED, "walk": TORSO_CROSSED, "sleep": TORSO_CROSSED,
             "eat": TORSO_PLAIN, "rage": TORSO_RAGE}[anim]
    legs = {"walk": LEGS_FLY, "rage": LEGS_WIDE}.get(anim, LEGS_STAND)
    put(g, torso, 20)
    put(g, legs, 27)
    if "pads" in extras:
        put(g, PADS, 18)
    if anim == "eat":
        dots(g, ARM_DOWN)
    if anim == "eat":
        dots(g, MEAT)
        if frame == 1:
            dots(g, BITE, "_")

    kind = {"eat": "eat" if frame == 0 else "chew"}.get(anim, anim)
    if anim == "walk":
        kind = "plain"
    put(g, face(kind, eyes), 12 + bob)
    put(g, HAIR[hair], bob)
    if "m" in extras:
        put(g, MAJIN_M, 11 + bob, 13)

    if anim == "sleep":
        dots(g, ZED_SMALL if frame == 0 else ZED_BIG, "A")
    else:
        if anim == "walk":   # ki under the feet
            ki = [(16, 31), (20, 31), (7, 31)] if frame == 0 else [(18, 31), (22, 31), (6, 30)]
            dots(g, ki, "A")
        aura(g, level + (1 if anim == "rage" else 0), frame)
        if "bolts" in extras:
            dots(g, BOLTS[frame], "A")
    return ["".join(r) for r in g]


# --- flying: Superman pose, facing right -----------------------------------------
# The head stays upright and looks at us; the body streams out behind it. The
# game tilts and mirrors the whole sprite to point where the pet is going.


def build_fly(form, frame):
    hair, eyes, level, extras, _ = FORMS[form]
    g = new()
    bob = frame            # a small up-and-down while it flies
    hx, hy = 6, 5 + bob    # the head's offset
    body = []
    by = 23 + bob
    body += [(x, y) for y in range(by, by + 7) for x in range(8, 23)]       # torso
    body += [(x, y) for y in range(by + 1, by + 6) for x in range(5, 8)]    # hips
    top, bot = (by + 1, by + 4) if frame == 0 else (by, by + 5)             # legs scissor
    body += [(x, y) for y in (top, top + 1) for x in range(0, 5)]
    body += [(x, y) for y in (bot, bot + 1) for x in range(0, 5)]
    body += [(x, y) for y in (by + 2, by + 3, by + 4) for x in range(23, 27)]  # forearm
    body += [(x, y) for y in range(by + 1, by + 6) for x in range(27, 31)]  # fist
    dots(g, body)
    dots(g, [(x, by + 4) for x in range(10, 18)], "_")                      # arm line across the chest
    dots(g, [(29, by + 3), (29, by + 4)], "_")                              # knuckles
    if "pads" in extras:
        put(g, PADS, by - 3, 4)
    put(g, face("plain", eyes), 12 + hy, hx)
    put(g, HAIR[hair], hy, hx)
    if "m" in extras:
        put(g, MAJIN_M, 11 + hy, 13 + hx)
    # ki trailing behind, in the accent colour
    trail = [(1, 18), (3, 20), (5, 17), (0, 30), (4, 31), (8, 29)] if frame == 0 \
        else [(0, 19), (2, 17), (4, 20), (1, 31), (6, 30), (3, 29)]
    dots(g, trail, "A")
    aura(g, level, frame, floor=False)
    if "bolts" in extras:
        dots(g, [(x + 4, y + 2) for x, y in BOLTS[frame]], "A")
    return ["".join(r) for r in g]


# --- bar icons (16x16 heads) ----------------------------------------------------

ICON_HAIR = {
    "flame": art("""
.......AA.......
.......AA.......
......AAAA......
....A.AAAA.A....
....AAAAAAAA....
...AAAAAAAAAA...
..AAAAAAAAAAAA..
..AAA..AA..AAA..
..AA........AA..
"""),
    "blades": art("""
.......AA.......
.....A.AA.A.....
.....A.AA.A.....
..A.AAAAAAAA.A..
..AAAAAAAAAAAA..
.AAAAAAAAAAAAAA.
..AAAAAAAAAAAA..
..AAA..AA..AAA..
..AA........AA..
"""),
    "spikes": art("""
....A..AA..A....
....A..AA..A....
.A..AA.AA.AA..A.
.AA.AA.AA.AA.AA.
.AAAAAAAAAAAAAA.
..AAAAAAAAAAAA..
..AAAAAAAAAAAA..
..AAA..AA..AAA..
..AA........AA..
"""),
}
ICON_FACE = art("""
...XXXXXXXXXX...
...XXXXXXXXXX...
...X_XXXXXX_X...
..XX___XX___XX..
..XXXXXXXXXXXX..
...XXXXXXXXXX...
....XXX__XXX....
.....XXXXXX.....
......XXXX......
""")


def icon(form, frame):
    hair, eyes, level, extras, _ = FORMS[form]
    g = new(16)
    put(g, ICON_FACE, 7)
    put(g, ICON_HAIR[hair], 0)
    if "m" in extras:
        dots(g, [(7, 8), (8, 8)], "_")
    if level >= 1:
        pts = [(0, 9), (15, 11), (0, 13), (15, 7)] if frame == 0 else [(0, 11), (15, 9), (15, 13), (0, 7)]
        dots(g, pts, "A")
    return ["".join(r) for r in g]


# --- the pod --------------------------------------------------------------------


def pod(frame, n=32):
    g = new(n)
    c = (n - 1) / 2
    big = n == 32
    cy = c + (1 if big else 0)
    R, win, ring = (12.6, 3.2, 4.6) if big else (6.6, 1.6, 2.6)
    wy = cy - (3 if big else 1)
    for y in range(n):
        for x in range(n):
            d = ((x - c) ** 2 + (y - cy) ** 2) ** 0.5
            dw = ((x - c) ** 2 + (y - wy) ** 2) ** 0.5
            if dw <= win:
                g[y][x] = "A"
            elif dw <= ring:
                g[y][x] = "."
            elif d <= R:
                g[y][x] = "X"
    if big:
        for x in range(n):                      # hatch seam and its hinges
            if g[21][x] == "X":
                g[21][x] = "."
        dots(g, [(6, 17), (25, 17), (9, 25), (22, 25)], "_")
        dots(g, [(15, 2), (16, 2)] if frame == 0 else [], "A")   # beacon blinks
        if frame == 1:                          # it rocks a little
            dots(g, [(3, 30), (2, 31), (28, 30), (29, 31)], "A")
    return ["".join(r) for r in g]


# --- output ---------------------------------------------------------------------


def everything():
    out = {}
    for f in "ab":
        i = "ab".index(f)
        out[f"pod_idle_{f}"] = pod(i)
        out[f"pod_icon_{f}"] = pod(i, 16)
        for form in FORMS:
            out[f"{form}_icon_{f}"] = icon(form, i)
            for anim in ANIMS:
                out[f"{form}_{anim}_{f}"] = build(form, anim, i)
    return out


def write(grids):
    for name, rows in grids.items():
        with open(os.path.join(OUT, name + ".txt"), "w") as fh:
            fh.write("\n".join(rows) + "\n")


def hexrgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def preview(grids, path, scale=5, only=None):
    bg, fg = hexrgb("#10151a"), hexrgb("#9af0a8")
    dim = tuple((f * 55 + b * 45) // 100 for f, b in zip(fg, bg))
    rows = [("pod", "#ff5d7a")] + [(k, v[4]) for k, v in FORMS.items()]
    if only:
        rows = [r for r in rows if r[0] in only]
    cols = ("icon", "idle") + ANIMS[1:]
    cell, pad = 32, 4
    wpx, hpx = len(cols) * (cell + pad) + pad, len(rows) * (cell + pad) + pad
    frames = []
    for f in "ab":
        img = [[bg] * wpx for _ in range(hpx)]
        for ry, (form, colour) in enumerate(rows):
            acc = dim if colour == "dim" else hexrgb(colour)
            for cx, anim in enumerate(cols):
                g = grids.get(f"{form}_{anim}_{f}")
                if not g:
                    continue
                off = (cell - len(g)) // 2
                for y, row in enumerate(g):
                    for x, ch in enumerate(row):
                        if ch != ".":
                            img[pad + ry * (cell + pad) + off + y][pad + cx * (cell + pad) + off + x] = fg if ch == "X" else acc
        ppm = f"{path}.{f}.ppm"
        with open(ppm, "wb") as fh:
            fh.write(b"P6 %d %d 255\n" % (wpx, hpx))
            fh.write(bytes(v for line in img for px in line for v in px))
        frames.append(ppm)
    s = f"{scale * 100}%"
    subprocess.run(["magick", frames[0], "-filter", "point", "-resize", s, path], check=True)
    subprocess.run(["magick", "-delay", "45", "-loop", "0", frames[0], frames[1],
                    "-filter", "point", "-resize", s, os.path.splitext(path)[0] + ".gif"], check=True)
    for p in frames:
        os.remove(p)


if __name__ == "__main__":
    grids = everything()
    write(grids)
    print("wrote", len(grids), "grids")
    if "--preview" in sys.argv:
        i = sys.argv.index("--preview")
        preview(grids, sys.argv[i + 1], only=sys.argv[i + 2:] or None)
