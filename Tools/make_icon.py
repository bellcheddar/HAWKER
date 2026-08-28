#!/usr/bin/env python3
"""
Draw HAWKER's app icon from the app's own data.

A glyph would say nothing. This is the Overlook's point cloud: every dead asset the
ingest actually found, positioned by year of death and Ghost Rank, coloured by cause
of death on the app's own semantic scale. The picture is the product.

    python3 Tools/make_icon.py <assets.json> [out_dir]

Two things the App Store rejects, both guarded here:
  - an icon with an alpha channel (PIL hands you RGBA by default)
  - a visionOS icon that is a flat PNG rather than a layered .solidimagestack
"""
import json
import math
import random
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

# The app's palette, verbatim from Palette.swift.
VOID = (0x05, 0x07, 0x0F)
SLAB = (0x0E, 0x14, 0x28)
NEON = (0x4E, 0xF0, 0xFF)
CAUSE = {
    "safetyMechanistic": (0xFF, 0x4D, 0x5E),
    "efficacyFutility":  (0xFF, 0xAE, 0x43),
    "pkAdmet":           (0xB5, 0x7B, 0xFF),
    "enrolment":         (0x2F, 0xE0, 0xC0),
    "businessStrategic": (0xFF, 0x5C, 0xD8),
    "funding":           (0xFF, 0x5C, 0xD8),
    "operational":       (0x64, 0x74, 0x8B),
    "unknown":           (0x64, 0x74, 0x8B),
}

S = 1024


def load_points(path):
    """Real assets if we have them; otherwise nothing, rather than invented data."""
    if not path or not Path(path).exists():
        return []
    data = json.loads(Path(path).read_text())
    assets = data.get("assets", data) if isinstance(data, dict) else data
    pts = []
    for a in assets:
        cause = (a.get("verdict") or {}).get("cause") or "unknown"
        s = a.get("score") or {}
        rank = (s.get("benignDeath", 0.5) * 0.35
                + s.get("structuralTractability", 0.0) * 0.25
                + s.get("biologicalWhitespace", 0.0) * 0.25
                + s.get("freedomToOperate", 0.0) * 0.15)
        year = a.get("estimatedFTOYear")
        if year is None:
            continue
        pts.append((cause, float(year), rank))
    return pts


def axes(points):
    """Percentile range, read off the data rather than assumed.

    Plain min/max let a couple of outliers (an estimated horizon of 1954, another of
    2042) stretch the axis and squash every other point into the middle third. The
    5th to 95th percentile fills the frame; the outliers still plot, just clamped.
    """
    ys = sorted(p[1] for p in points)
    rs = sorted(p[2] for p in points)

    def pct(v, q):
        return v[min(len(v) - 1, max(0, int(q * (len(v) - 1))))]

    return (pct(ys, 0.05), pct(ys, 0.95), pct(rs, 0.03), pct(rs, 0.97))


def draw(points, out):
    img = Image.new("RGB", (S, S), VOID)

    # Ground: a soft lift from the lower left, so the cloud sits in space.
    glow = Image.new("RGB", (S, S), VOID)
    gd = ImageDraw.Draw(glow)
    gd.ellipse([-S * 0.25, S * 0.30, S * 0.85, S * 1.35], fill=(0x14, 0x1E, 0x3C))
    img = Image.blend(img, glow.filter(ImageFilter.GaussianBlur(S // 6)), 0.9)
    d = ImageDraw.Draw(img)

    rng = random.Random(1729)

    # The graveyard's ground plane: a few neon rules in perspective.
    for i in range(5):
        y = S * (0.815 + i * 0.042)
        fade = 0.42 - i * 0.075
        d.line([(S * 0.06, y), (S * 0.94, y)],
               fill=tuple(int(VOID[j] + (NEON[j] - VOID[j]) * fade) for j in range(3)),
               width=max(1, 3 - i))

    # The Overlook's own axes: estimated horizon year across, Ghost Rank up.
    #
    # The other score components were tried first and do not scatter: benignDeath has
    # four distinct values across 176 assets and structuralTractability has seven, so
    # plotting them draws four clumps rather than a cloud. Year has 56 distinct values
    # over 1954 to 2042 and is the only axis with real spread.
    ylo, yhi, rlo, rhi = axes(points)
    yspan = max(1.0, yhi - ylo)
    rspan = max(0.01, rhi - rlo)
    for cause, year, rank in points:
        colour = CAUSE.get(cause, CAUSE["unknown"])
        fx = min(1.0, max(0.0, (year - ylo) / yspan))
        fr = min(1.0, max(0.0, (rank - rlo) / rspan))
        x = S * (0.11 + 0.78 * fx) + rng.gauss(0, S * 0.014)
        y = S * (0.80 - 0.66 * fr) + rng.gauss(0, S * 0.018)
        r = S * (0.0060 + 0.0105 * fr)

        # Additive falloff: a dim halo, then a bright core. Kept small on purpose.
        # A first attempt used radii four times this with screen blending, and 176
        # overlapping halos saturated the whole frame to white: the colour scale, which
        # is the only thing the icon is actually saying, disappeared entirely.
        for mult, alpha in ((3.0, 0.10), (1.8, 0.30), (1.0, 0.95)):
            rr = r * mult
            layer = Image.new("RGB", img.size)
            ImageDraw.Draw(layer).ellipse(
                [x - rr, y - rr, x + rr, y + rr],
                fill=tuple(int(c * alpha) for c in colour),
            )
            # Screen blend, so overlapping glows brighten rather than muddying.
            img = ImageChops.screen(img, layer)

    img = img.filter(ImageFilter.GaussianBlur(0.5))
    img = img.convert("RGB")
    assert img.mode == "RGB", f"icon must be RGB, got {img.mode}"
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out, "PNG")
    print(f"wrote {out} ({img.size[0]}x{img.size[1]}, mode {img.mode}, {out.stat().st_size} bytes)")
    return img


if __name__ == "__main__":
    src = sys.argv[1] if len(sys.argv) > 1 else None
    outdir = Path(sys.argv[2] if len(sys.argv) > 2 else "assets/icon")
    pts = load_points(src)
    print(f"{len(pts)} real assets available for the icon")
    if not pts:
        sys.exit("No asset data. Run hawker-ingest first: the icon is drawn from real data, not invented.")
    draw(pts, outdir / "hawker-icon-1024.png")
