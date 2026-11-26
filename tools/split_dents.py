#!/usr/bin/env python3
"""
Split a sheet of dents/scratches/wear marks (PNG, transparent background) into
individual PNGs and sort them into folders by WEAR TYPE (default) or by COLOR.

  decals/
    fine_scratches/ deep_scratches/ gouges/ dents/ scuffs/ grime/ corrosion/
    paint_transfer/{yellow,brown,silver,...}/
    adhesive_residue/
    _review/            <- specks / things the rules couldn't place
    manifest.csv        <- every piece, its category, and the measurements used

Each piece is saved as 01.png, 02.png ... Numbering continues from whatever is
already in a folder, so you can feed in many sheets with the same -o directory.

Usage:
    python split_dents.py dents1.png -o decals
    python split_dents.py sheets/ -o decals
    python split_dents.py dents1.png -o out_by_color --by color     # old behaviour

Requires: pip install pillow numpy scipy

The wear-type sorting is a set of shape/texture/color heuristics (see
classify_wear). They are meant to get you ~80% of the way; use manifest.csv
to see why something landed where it did, and tweak the thresholds at the top.
"""
import argparse
import csv
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

# ============================================================ TUNABLE THRESHOLDS
T = dict(
    speck_area=40,            # core pixels below this -> _review
    dent_max_elong=2.0,       # blob must be this round or rounder ...
    dent_min_width=15.0,      # ... and at least this wide (avg px) to be a dent
    dent_min_shading=25.0,    # dents/pits show light+dark shading (lum std-dev)
    soft_max_shading=22.0,    # below this a wide mark is flat/soft (grime/scuff)
    soft_min_width=9.0,       # "wide" mark for grime/scuff/paint transfer
    scuff_min_elong=2.3,      # soft + streaky/elongated -> scuff, else grime
    gouge_min_width=9.0,      # thick, elongated, few strokes, shaded -> gouge
    gouge_max_strokes=3,
    gouge_min_elong=2.0,
    fine_max_width=8.0,       # thinner than this (max px) -> fine scratch
    fine_min_strokes=3,       # or this many separate strokes -> fine scratches
    paint_min_sat=0.40,       # colored smear this saturated -> paint transfer
    silver_paint_min_lum=170, # bright flat metallic smear -> silver paint transfer
)


# ================================================================ color helpers
def classify_pixels(rgb, weights):
    rgb_f = rgb.astype(np.float32) / 255.0
    mx, mn = rgb_f.max(axis=1), rgb_f.min(axis=1)
    delta = mx - mn
    sat = np.where(mx > 0, delta / np.maximum(mx, 1e-6), 0)
    val = mx
    r, g, b = rgb_f[:, 0], rgb_f[:, 1], rgb_f[:, 2]
    d = np.maximum(delta, 1e-6)
    hue = np.zeros_like(mx)
    hue = np.where(mx == r, ((g - b) / d) % 6, hue)
    hue = np.where(mx == g, (b - r) / d + 2, hue)
    hue = np.where(mx == b, (r - g) / d + 4, hue)
    hue = hue * 60.0

    cats = np.full(len(rgb), "other", dtype=object)
    neutral = sat < 0.30
    cats[neutral & (val >= 0.85)] = "white"
    cats[neutral & (val < 0.85) & (val >= 0.22)] = "silver"
    cats[neutral & (val < 0.22)] = "black"
    chroma = ~neutral
    cats[chroma & (hue >= 40) & (hue < 70)] = "yellow"
    warm = chroma & ((hue < 40) | (hue >= 340))
    cats[warm & (sat >= 0.5)] = "rust"
    cats[warm & (sat < 0.5)] = "brown"
    cats[chroma & (hue >= 70) & (hue < 170)] = "green"
    cats[chroma & (hue >= 170) & (hue < 260)] = "blue"
    return {c: float(weights[cats == c].sum()) for c in np.unique(cats)}


def predominant_color(rgba_crop, mask, min_alpha=60):
    a = rgba_crop[..., 3]
    sel = mask & (a >= min_alpha)
    if sel.sum() < 5:
        sel = mask & (a > 0)
    if not sel.any():
        return "other"
    totals = classify_pixels(rgba_crop[..., :3][sel], a[sel].astype(np.float32))
    for c in ("yellow", "rust", "brown", "green", "blue"):   # colors beat gray fringe
        if c in totals:
            totals[c] *= 1.6
    return max(totals, key=totals.get)


# ============================================================ shape / texture
def measure(crop, mask):
    """Numbers describing one piece. `crop` is RGBA uint8, `mask` its object mask."""
    a = crop[..., 3].astype(np.float32)
    ink = mask & (a > 10)
    core = mask & (a > 128)
    if core.sum() < 5:
        core = mask & (a > 40)
    f = dict(core_area=int(core.sum()))
    if core.sum() < 5:
        f.update(elong=1, length=0, avg_w=0, max_w=0, strokes=0, shading=0, lum=255, sat=0, hue=0)
        return f

    ys, xs = np.nonzero(ink)
    ev = np.sort(np.linalg.eigvalsh(np.cov(np.vstack([xs, ys]))))[::-1]
    f["elong"] = float(np.sqrt(ev[0] / max(ev[1], 1e-6)))
    f["length"] = float(4 * np.sqrt(ev[0]))

    dt = ndi.distance_transform_edt(core)
    f["max_w"] = float(2 * dt.max())
    f["avg_w"] = float(core.sum() / max(f["length"], 1))

    lab, n = ndi.label(ndi.binary_dilation(core, iterations=1))
    sizes = ndi.sum(core, lab, range(1, n + 1))
    f["strokes"] = int((np.asarray(sizes) > 15).sum())

    rgb = crop[..., :3][core].astype(np.float32)
    lum = rgb.mean(axis=1)
    f["shading"] = float(lum.std())
    f["lum"] = float(lum.mean())
    mx, mn = rgb.max(axis=1), rgb.min(axis=1)
    f["sat"] = float(((mx - mn) / np.maximum(mx, 1)).mean())
    m = rgb.mean(axis=0) / 255.0
    r, g, b = m
    mxv, mnv = m.max(), m.min()
    d = max(mxv - mnv, 1e-6)
    h = (((g - b) / d) % 6 if mxv == r else (b - r) / d + 2 if mxv == g else (r - g) / d + 4) * 60
    f["hue"] = float(h)
    return f


def classify_wear(f, color):
    """Return (category_path, reason). category_path may contain a subfolder."""
    if f["core_area"] < T["speck_area"]:
        return "_review", "speck"

    wide = f["avg_w"] >= T["soft_min_width"]

    # --- colored material first -------------------------------------------
    if color == "yellow":
        return "paint_transfer/yellow", "yellow"
    if color == "rust":
        return "corrosion", "rust-colored"
    if color == "brown" and f["sat"] >= T["paint_min_sat"] and wide:
        return "paint_transfer/brown", "brown smear"
    if color in ("green", "blue") and wide:
        return f"paint_transfer/{color}", f"{color} smear"

    # pale, sticky-looking tan/yellow patch (untested on sample sheet)
    if 35 <= f["hue"] <= 65 and 0.25 <= f["sat"] < T["paint_min_sat"] and wide \
            and f["lum"] > 150 and f["shading"] < T["soft_max_shading"]:
        return "adhesive_residue", "pale tan patch"

    # --- dents: compact, wide, shaded ---------------------------------------
    if f["elong"] < T["dent_max_elong"] and f["avg_w"] >= T["dent_min_width"] \
            and f["shading"] >= T["dent_min_shading"]:
        return "dents", "compact+shaded"
    if f["elong"] < 1.5 and f["max_w"] >= 18 and f["strokes"] <= 1:   # small pits
        return "dents", "small compact pit"

    # --- flat/soft wide marks -----------------------------------------------
    if wide and f["shading"] < T["soft_max_shading"]:
        if color == "silver" and f["lum"] >= T["silver_paint_min_lum"]:
            return "paint_transfer/silver", "bright flat smear"
        if f["elong"] >= T["scuff_min_elong"]:
            return "scuffs", "soft+elongated"
        return "grime", "soft+blobby"

    # --- scratch family -----------------------------------------------------
    if f["avg_w"] >= T["gouge_min_width"] and f["strokes"] <= T["gouge_max_strokes"] \
            and f["elong"] >= T["gouge_min_elong"] and f["shading"] >= 25:
        return "gouges", "thick+shaded"
    if f["max_w"] < T["fine_max_width"] or f["strokes"] >= T["fine_min_strokes"]:
        return "fine_scratches", "thin or many strokes"
    if f["elong"] >= 3.0:
        return "deep_scratches", "long single/double stroke"
    if wide and f["max_w"] >= 15:
        return "scuffs", "wide streaky"
    return "fine_scratches", "default"


# ================================================================ image logic
def load_with_alpha(path, bg_threshold):
    arr = np.array(Image.open(path).convert("RGBA"))
    if arr[..., 3].min() < 250:             # real transparency
        return arr
    rgb = arr[..., :3].astype(np.int16)     # opaque -> treat near-white as background
    dist = (255 - rgb).max(axis=2)
    alpha = np.clip((dist - bg_threshold) * 255 / max(1, 255 - bg_threshold) * 4, 0, 255)
    arr[..., 3] = alpha.astype(np.uint8)
    return arr


def split_sheet(path, out_dir, a, counters, manifest):
    arr = load_with_alpha(path, a.bg_threshold)
    alpha = arr[..., 3]
    solid = alpha > a.alpha
    grown = ndi.binary_dilation(solid, structure=np.ones((3, 3)), iterations=a.merge)
    labels, _ = ndi.label(grown)
    objs = [(i, sl) for i, sl in enumerate(ndi.find_objects(labels), start=1) if sl is not None]
    if not objs:
        print(f"  {path.name}: nothing found")
        return

    row_h = np.median([sl[0].stop - sl[0].start for _, sl in objs])
    objs.sort(key=lambda o: (round(((o[1][0].start + o[1][0].stop) / 2) / max(row_h * 1.5, 1)),
                             o[1][1].start))
    h, w = alpha.shape
    saved = 0
    for lab, (ys, xs) in objs:
        comp = labels == lab
        if (comp & solid).sum() < a.min_area:
            continue
        y0, y1 = max(ys.start - a.pad, 0), min(ys.stop + a.pad, h)
        x0, x1 = max(xs.start - a.pad, 0), min(xs.stop + a.pad, w)
        crop = arr[y0:y1, x0:x1].copy()
        keep = ndi.binary_dilation(comp, iterations=a.pad)[y0:y1, x0:x1]
        crop[~keep, 3] = 0
        cmask = comp[y0:y1, x0:x1]

        color = predominant_color(crop, cmask)
        feats = measure(crop, cmask)
        if a.by == "color":
            rel, reason = color, "color"
        else:
            rel, reason = classify_wear(feats, color)

        folder = out_dir / rel
        folder.mkdir(parents=True, exist_ok=True)
        if rel not in counters:
            existing = [int(p.stem) for p in folder.glob("*.png") if p.stem.isdigit()]
            counters[rel] = max(existing, default=0)
        counters[rel] += 1
        name = f"{counters[rel]:02d}.png"
        Image.fromarray(crop, "RGBA").save(folder / name)
        manifest.append(dict(
            file=f"{rel}/{name}", source=path.name, category=rel, reason=reason, color=color,
            **{k: round(v, 2) if isinstance(v, float) else v for k, v in feats.items()}))
        saved += 1
    print(f"  {path.name}: {saved} pieces")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("inputs", nargs="+", help="PNG files and/or folders of PNGs")
    ap.add_argument("-o", "--out", default="decals", help="output directory (default: decals)")
    ap.add_argument("--by", choices=["wear", "color"], default="wear", help="sort by wear type (default) or color")
    ap.add_argument("--alpha", type=int, default=30, help="alpha above this counts as 'ink' (default 30)")
    ap.add_argument("--merge", type=int, default=12,
                    help="px gap bridged when grouping strokes into one object (default 12)")
    ap.add_argument("--min-area", type=int, default=20, help="ignore specks smaller than this many px (default 20)")
    ap.add_argument("--pad", type=int, default=4, help="padding around each crop (default 4)")
    ap.add_argument("--bg-threshold", type=int, default=12,
                    help="for PNGs with NO transparency: distance from white that counts as ink (default 12)")
    a = ap.parse_args()

    files = []
    for item in a.inputs:
        p = Path(item)
        if p.is_dir():
            files += sorted(p.glob("*.png"))
        elif p.is_file():
            files.append(p)
        else:
            print(f"skipping {item}: not found", file=sys.stderr)

    out_dir = Path(a.out)
    counters, manifest = {}, []
    for f in files:
        split_sheet(f, out_dir, a, counters, manifest)

    if manifest:
        mpath = out_dir / "manifest.csv"
        new = not mpath.exists()
        with open(mpath, "a", newline="") as fh:
            wr = csv.DictWriter(fh, fieldnames=list(manifest[0].keys()))
            if new:
                wr.writeheader()
            wr.writerows(manifest)

    print("\nTotals this run:")
    for c, n in sorted(counters.items()):
        print(f"  {c}/  -> {n:02d}.png is the latest")


if __name__ == "__main__":
    main()


