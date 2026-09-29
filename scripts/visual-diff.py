#!/usr/bin/env python3
"""Compare two PNG screenshots and report how much of the screen changed.

A screenshot that was taken is not evidence that the theme did anything: the
accent picker rewrote colors.toml and painted nothing, and a whole-screen pixel
count would have passed it on wallpaper noise alone. Use this to catch a change
that *should* move a lot of pixels (a theme switch, a wallpaper swap); use
visual-accent.py when you need to know a specific colour showed up.

Both images must have the same size.

Usage:
    visual-diff.py <before.png> <after.png> [--min-changed PCT] [--quiet]

    --min-changed PCT  fail unless at least PCT% of the pixels differ (default 0)
    --quiet            print nothing; rely on the exit code

Exit codes: 0 the change threshold is met, 1 it was not, 2 the images are
unreadable or differ in size.
"""

import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
import png  # noqa: E402


def main(argv):
    if len(argv) < 2 or argv[0] in ("-h", "--help"):
        print(__doc__.strip())
        return 0 if len(argv) > 1 else 1

    minimum, quiet, paths = 0.0, False, []
    i = 0
    while i < len(argv):
        if argv[i] == "--min-changed" and i + 1 < len(argv):
            minimum = float(argv[i + 1].rstrip("%"))
            i += 2
        elif argv[i] == "--quiet":
            quiet = True
            i += 1
        else:
            paths.append(argv[i])
            i += 1
    if len(paths) != 2:
        print("visual-diff.py: expected two PNG paths", file=sys.stderr)
        return 2

    try:
        w1, h1, c1, a = png.read(paths[0])
        w2, h2, c2, b = png.read(paths[1])
    except ValueError as error:
        print(f"visual-diff.py: {error}", file=sys.stderr)
        return 2
    if (w1, h1) != (w2, h2):
        print(f"visual-diff.py: size mismatch: {w1}x{h1} vs {w2}x{h2}", file=sys.stderr)
        return 2

    total = w1 * h1
    changed = 0
    for y in range(h1):
        row_a, row_b = a[y], b[y]
        if row_a == row_b:
            continue
        for x in range(w1):
            i = x * c1
            if row_a[i:i + 3] != row_b[i:i + 3]:
                changed += 1

    percent = 100.0 * changed / total
    if not quiet:
        print(f"{w1}x{h1}: {changed} pixels differ ({percent:.3f}%, minimum {minimum:.3f}%)")
    return 0 if percent >= minimum else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
