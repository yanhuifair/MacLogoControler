#!/usr/bin/env python3
"""Make the panel's lid pictures from Apple's own lid shots.

    make-lid-images.py <source-dir> <out-dir>

Reads the finish-select shots Apple publishes — top-down views of each closed lid,
`mac-macbook-pro-proled-finish-select-202610-{14,16}inch-{silver,spaceblack}.png`,
already knocked out to transparency — and writes per size and finish:

  lid-16inch-spaceblack.png        the lid, cropped to its own bounds, 1600 px wide
  lid-16inch-spaceblack-mark.png   the printed logo's shape, white on clear, on the
                                   lid's own canvas: two layers over the same box, so
                                   the light sits on the mark exactly, at any scale.

Both are quantised to keep them light. The script prints the geometry the live view
needs: each lid's aspect, and the mark's centre and size as shares of the lid.
"""
import os
import sys
from collections import deque

import numpy as np
from PIL import Image, ImageFilter

LIDS = [("16inch", "spaceblack"), ("16inch", "silver"), ("14inch", "spaceblack"), ("14inch", "silver")]
# The lid's width in the app: the 16-inch fills the card's inside (392 pt) and the
# renderer draws up to 2x, so 1600 px leaves the shots sharp with room over.
WIDTH = 1600


def process(src, out):
    im = Image.open(src)
    a = np.asarray(im.split()[3])
    ys, xs = np.where(a > 8)  # the lid and its antialiased edge
    box = (max(xs.min() - 1, 0), max(ys.min() - 1, 0), min(xs.max() + 2, a.shape[1]), min(ys.max() + 2, a.shape[0]))
    lid = im.crop(box)

    # Resize premultiplied: knocked-out pixels hold their RGB under clear alpha, and
    # blending those straight fringes the lid's edge with whatever sat outside it.
    alpha = np.asarray(lid.split()[3], dtype=np.float32)
    rgb = np.asarray(lid.convert("RGB"), dtype=np.float32) * (alpha / 255.0)[..., None]
    size = (WIDTH, round(lid.height * WIDTH / lid.width))
    rgb = np.stack([Image.fromarray(c.astype(np.uint8)).resize(size, Image.LANCZOS)
                    for c in np.moveaxis(rgb, -1, 0)], axis=-1).astype(np.float32)
    alpha = np.asarray(Image.fromarray(alpha.astype(np.uint8)).resize(size, Image.LANCZOS), dtype=np.float32)
    with np.errstate(invalid="ignore", divide="ignore"):
        straight = np.clip(rgb / (alpha / 255.0)[..., None], 0, 255)
    straight[alpha < 1] = 0
    shot = Image.fromarray(np.dstack([straight.astype(np.uint8), alpha.astype(np.uint8)]), "RGBA")
    shot = shot.quantize(colors=255, method=Image.FASTOCTREE, dither=Image.FLOYDSTEINBERG).convert("RGBA")
    shot.save(out, optimize=True)
    print(f"{os.path.basename(out)}: {shot.width}x{shot.height} aspect {shot.width / shot.height:.4f} "
          f"({os.path.getsize(out) // 1024} KiB)")
    return shot


def mark(shot, out):
    """The printed logo's shape, cut from the lid picture, on the picture's own canvas.

    The lid darkens slowly and the logo is just pixels darker than its surroundings —
    black body and sheened crown alike. Across the middle band the lid is far wider
    than the logo, so each row's own median is what the lid looks like on that row and
    well under it is the mark: the gradient cancels row by row, and the grain sits a
    few greys off the median, far above the threshold. Grain specks are opened out;
    the mark's own holes and the sheen's seams are filled back in.
    """
    w, h = shot.size
    l = np.asarray(shot.convert("L"), dtype=np.float32)
    y0b, y1b, x0b, x1b = int(0.35 * h), int(0.70 * h), int(0.35 * w), int(0.65 * w)
    band = l[y0b:y1b, x0b:x1b]
    per_row = np.median(band, axis=1, keepdims=True)
    mask = band < per_row * 0.85
    mask = np.asarray(Image.fromarray((mask * 255).astype(np.uint8))
                      .filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(5))) > 128
    mask = fill_holes(mask)
    shape = np.zeros((h, w), dtype=np.uint8)
    shape[y0b:y1b, x0b:x1b] = mask * 255
    alpha = Image.fromarray(shape).filter(ImageFilter.GaussianBlur(1.2))
    full = Image.new("RGBA", (w, h))
    full.paste(Image.new("RGBA", (w, h), (255, 255, 255, 255)), (0, 0), alpha)
    full.quantize(colors=2, method=Image.FASTOCTREE).convert("RGBA").save(out, optimize=True)

    ys, xs = np.where(mask)
    x0, x1, y0, y1 = xs.min() + x0b, xs.max() + x0b, ys.min() + y0b, ys.max() + y0b
    print(f"    mark {x1 - x0 + 1}x{y1 - y0 + 1} px at centre "
          f"({(x0 + x1 + 1) / 2 / w:.4f}·W, {(y0 + y1 + 1) / 2 / h:.4f}·H), "
          f"{(x1 - x0 + 1) / h:.4f}×{(y1 - y0 + 1) / h:.4f}·H "
          f"(aspect {(xs.max() - xs.min() + 1) / (ys.max() - ys.min() + 1):.4f}, "
          f"{os.path.getsize(out) // 1024} KiB)")


def fill_holes(mask):
    """What the outside can't reach through clear pixels is inside the mark: fill it."""
    h, w = mask.shape
    free = ~mask
    reached = np.zeros_like(mask)
    q = deque((y, x) for x in range(w) for y in (0, h - 1) if free[y, x])
    q += deque((y, x) for y in range(h) for x in (0, w - 1) if free[y, x] and not reached[y, x])
    for yx in list(q):
        reached[yx] = True
    while q:
        y, x = q.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < h and 0 <= nx < w and free[ny, nx] and not reached[ny, nx]:
                reached[ny, nx] = True
                q.append((ny, nx))
    return mask | (free & ~reached)


def main():
    downloads, out_dir = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)
    for size, finish in LIDS:
        src = os.path.join(downloads, f"mac-macbook-pro-proled-finish-select-202610-{size}-{finish}.png")
        shot = process(src, os.path.join(out_dir, f"lid-{size}-{finish}.png"))
        mark(shot, os.path.join(out_dir, f"lid-{size}-{finish}-mark.png"))


if __name__ == "__main__":
    main()
