#!/usr/bin/env python3
"""Recolor the Orbital theme (accent AND glass tint) and re-apply it.

Usage: orbital-accent.py <preset|#rrggbb|list|current>

Every blue-ish color of the pristine theme (hue 190-240, i.e. the accent
family, the navy glass backgrounds and the blue-grey text tones) is rotated
to the chosen hue, keeping saturation/lightness. The pristine blue theme is
kept in ~/.local/state/omarchy/orbital-accent-base/ and each run regenerates
~/.config/omarchy/themes/orbital from it, so choices never compound.
The wallpaper is untouched (OMARCHY_THEME_SKIP_BACKGROUND=1).
"""
import colorsys, json, os, re, shutil, subprocess, sys

HOME = os.path.expanduser("~")
THEME = HOME + "/.config/omarchy/themes/orbital"
BASE = HOME + "/.local/state/omarchy/orbital-accent-base"
STATE = HOME + "/.local/state/omarchy/orbital-accent.json"
BASE_ACCENT = "#39A9FF"
BASE_HUE = colorsys.rgb_to_hsv(0x39/255, 0xA9/255, 0xFF/255)[0] * 360
# name: (hue, saturation multiplier, accent value multiplier, glass value multiplier)
# Neutrals (white/gray/black) drop saturation to 0: the accent family becomes
# white/gray and the glass becomes neutral dark grey / pure black.
PRESETS = {
    "blue": None, "indigo": (240, 1, 1, 1), "purple": (268, 1, 1, 1),
    "lilac": (285, 1, 1, 1), "magenta": (305, 1, 1, 1), "pink": (325, 1, 1, 1),
    "rose": (350, 1, 1, 1), "red": (0, 1, 1, 1), "orange": (25, 1, 1, 1),
    "amber": (42, 1, 1, 1), "lime": (85, 1, 1, 1), "green": (145, 1, 1, 1),
    "mint": (160, 1, 1, 1), "teal": (175, 1, 1, 1), "cyan": (190, 1, 1, 1),
    "white": (0, 0, 1, 1), "gray": (0, 0, 0.62, 1), "black": (0, 0, 1, 0.3),
}
SKIP = ("preview-web",)  # brand colors live there

def rot(r, g, b, p):
    hue, sm, va, vg = p
    h, s, v = colorsys.rgb_to_hsv(r/255, g/255, b/255)
    if not (190 <= h*360 <= 240 and s > 0.08):
        return r, g, b
    h = ((h*360 - BASE_HUE + hue) % 360) / 360
    s *= sm
    v *= va if v >= 0.5 else vg
    return tuple(round(x*255) for x in colorsys.hsv_to_rgb(h, s, v))

def transform(text, p, bare=False):
    def hexsub(m):
        c = m.group(1)
        return "#%02X%02X%02X" % rot(int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16), p)
    def trip(m):
        r, g, b = int(m.group(1)), int(m.group(3)), int(m.group(5))
        if max(r, g, b) > 255: return m.group(0)
        n = rot(r, g, b, p)
        return "%d%s%d%s%d" % (n[0], m.group(2), n[1], m.group(4), n[2])
    text = re.sub(r"#([0-9A-Fa-f]{6})\b", hexsub, text)
    if bare:  # ghostty.conf / foot.ini keep colors without the '#'
        text = re.sub(r"(?<![0-9A-Za-z#])([0-9A-Fa-f]{6})(?![0-9A-Za-z])",
                      lambda m: hexsub(m)[1:], text)
    return re.sub(r"(?<![\d.])(\d{1,3})(\s*,\s*)(\d{1,3})(\s*,\s*)(\d{1,3})(?![\d.])", trip, text)

def apply(name, p):
    if not os.path.isdir(BASE) or not os.listdir(BASE):
        sys.exit("orbital-accent: pristine theme copy missing (%s). Run install.sh from the "
                 "Orbital repository once to create it." % BASE)
    if not os.path.isdir(THEME):
        sys.exit("orbital-accent: theme not installed at %s (install it as 'orbital')." % THEME)
    for root, _, files in os.walk(BASE):
        rel = os.path.relpath(root, BASE)
        for f in files:
            src = os.path.join(root, f)
            dst = os.path.join(THEME, rel, f)
            t = open(src).read()
            if not any(s in rel + "/" + f for s in SKIP):
                t = transform(t, p, bare=f in ('ghostty.conf', 'foot.ini'))
            open(dst, "w").write(t)
    # Window border: Hyprland's active border lives in looknfeel.lua (outside
    # the theme), which reads this value; also applied live below.
    border = "rgba(%02x%02x%02x44)" % rot(0x7C, 0xC8, 0xFF, p)
    json.dump({"name": name, "border": border}, open(STATE, "w"))
    env = dict(os.environ, OMARCHY_THEME_SKIP_BACKGROUND="1")
    subprocess.run(["omarchy", "theme", "refresh"], env=env)
    subprocess.run(["hyprctl", "eval", 'hl.config({ general = { col = { active_border = "%s" } } })' % border],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def main():
    a = (sys.argv[1] if len(sys.argv) > 1 else "current").lower()
    if a == "list": print("\n".join(PRESETS)); return
    if a == "current":
        try: print(json.load(open(STATE))["name"])
        except Exception: print("blue")
        return
    if a in PRESETS:
        p = (BASE_HUE, 1, 1, 1) if PRESETS[a] is None else PRESETS[a]
    elif re.fullmatch(r"#[0-9a-f]{6}", a):
        p = (colorsys.rgb_to_hsv(*(int(a[i:i+2], 16)/255 for i in (1, 3, 5)))[0] * 360, 1, 1, 1)
    else: sys.exit("unknown accent: " + a)
    apply(a, p)
main()
