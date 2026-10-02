#!/usr/bin/env python3
"""Check that a screenshot shows a colour, and that a change made it show.

A screenshot that was taken is not evidence that the theme did anything, and a
whole-screen pixel count is worse: the wallpaper drifts between two shots, so a
feature that repaints nothing still "changes" 9% of the screen. Matching an exact
RGB is too strict in the other direction, because a themed accent shows up mostly
as antialiased strokes blended into the glass it sits on.

So match by hue, with floors on saturation and brightness, and require the new
hue to actually grow compared with the shot from before. That is the question a
person asks: did the colour arrive?

Usage:
    visual-accent.py <after.png> <colour> [--before before.png] [--min PIXELS]
                     [--grow FACTOR] [--quiet]

    <after.png>   screenshot taken after the change
    <colour>      #rrggbb the change was supposed to make visible
    --before      screenshot from before the change; the hue must be rarer there. Without
                  it the check is weak on purpose: the wallpaper has warm tones of its
                  own, so only a colour it cannot contain is evidence on its own.
    --min PIXELS  how many pixels must carry the hue in the after shot (default 400)
    --grow FACTOR how much more often it must appear than before, default 2
    --quiet       rely on the exit code only

Exit codes: 0 the colour shows where it should, 1 it does not, 2 unreadable input.
"""

import colorsys
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
import png  # noqa: E402

HUE_SLACK = 22      # degrees
SATURATION_FLOOR = 0.15
VALUE_FLOOR = 0.12


def hue_distance(a, b):
    """Smallest angle between two hues in degrees."""
    return min(abs(a - b), 360 - abs(a - b))


def count_hue(px, colour, width, height, channels, rows):
    """Pixels whose hue is within HUE_SLACK degrees of `colour`, above the floors."""
    target = colorsys.rgb_to_hsv(*[c / 255 for c in colour])[0] * 360
    seen = 0
    for y in range(height):
        row = rows[y]
        for x in range(width):
            i = x * channels
            hue, sat, val = colorsys.rgb_to_hsv(row[i] / 255, row[i + 1] / 255, row[i + 2] / 255)
            if sat >= SATURATION_FLOOR and val >= VALUE_FLOOR and hue_distance(hue * 360, target) <= HUE_SLACK:
                seen += 1
    return seen


def main(argv):
    if len(argv) < 2 or argv[0] in ("-h", "--help"):
        print(__doc__.strip())
        return 0 if len(argv) > 1 else 1

    before, quiet, minimum, grow, positional = None, False, 400, 2.0, []
    i = 0
    while i < len(argv):
        if argv[i] == "--before" and i + 1 < len(argv):
            before = argv[i + 1]
            i += 2
        elif argv[i] == "--min" and i + 1 < len(argv):
            minimum = int(argv[i + 1])
            i += 2
        elif argv[i] == "--grow" and i + 1 < len(argv):
            grow = float(argv[i + 1])
            i += 2
        elif argv[i] == "--quiet":
            quiet = True
            i += 1
        else:
            positional.append(argv[i])
            i += 1

    if len(positional) != 2:
        print("visual-accent.py: expected <after.png> <colour>", file=sys.stderr)
        return 1
    after_path, colour_text = positional
    try:
        colour = png.parse_hex(colour_text)
    except ValueError as error:
        print(f"visual-accent.py: {error}", file=sys.stderr)
        return 1

    try:
        w, h, c, r = png.read(after_path)
    except ValueError as error:
        print(f"visual-accent.py: {error}", file=sys.stderr)
        return 2
    after = count_hue(None, colour, w, h, c, r)

    bcount = None
    if before:
        try:
            bw, bh, bc, br = png.read(before)
        except ValueError as error:
            print(f"visual-accent.py: {error}", file=sys.stderr)
            return 2
        bcount = count_hue(None, colour, bw, bh, bc, br)

    ok = after >= minimum
    if bcount is not None:
        ok = ok and after >= bcount * grow
    if not quiet:
        print(f"{colour_text} on {after_path} ({w}x{h}): {after} px "
              f"(minimum {minimum})", end="")
        if bcount is not None:
            print(f"; on {before}: {bcount} px (need {bcount * grow:.0f})", end="")
        print(" -> " + ("ok" if ok else "FAIL, the colour did not arrive"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
