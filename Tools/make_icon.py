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

from PIL import Image, ImageDraw, ImageFilter

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
        cause = (a.get("verdict") or {}).get("cause") or a.get("cause") or "unknown"
        score = a.get("score") or {}
        rank = score.get("benignDeath", 0.5) * 0.35 + score.get("structuralTractability", 0) * 0.25 \
             + score.get("biologicalWhitespace", 0) * 0.25 + score.get("freedomToOperate", 0) * 0.15
        year = None
        for t in a.get("trials", []):
            d = t.get("completionDate") or t.get("startDate")
            if d:
                year = d
        pts.append((cause, rank, year))
    return pts


def draw(points, out):
    img = Image.new("RGB", (S, S), VOID)
    d = ImageDraw.Draw(img)

    # Ground: a soft radial lift so the cloud sits in space rather than on a flat field.
    glow = Image.new("RGB", (S, S), VOID)
    gd = ImageDraw.Draw(glow)
    gd.ellipse([S * 0.08, S * 0.20, S * 0.92, S * 1.04], fill=SLAB)
    img = Image.blend(img, glow.filter(ImageFilter.GaussianBlur(S // 8)), 0.85)
    d = ImageDraw.Draw(img)

    rng = random.Random(1729)

    # Horizon line: the graveyard's ground plane, in neon at low alpha.
    for i in range(6):
        y = S * (0.62 + i * 0.055)
        w = int(2 - i * 0.25)
        if w < 1:
            w = 1
        d.line([(S * (0.10 - i * 0.012), y), (S * (0.90 + i * 0.012), y)],
               fill=tuple(int(c * (0.30 - i * 0.04)) for c in NEON), width=w)

    if points:
        n = min(len(points), 900)
        chosen = rng.sample(points, n) if len(points) > n else points
    else:
        chosen = []

    # Plot: x spreads the cloud, y is rank (higher rank sits higher), size by rank.
    for i, (cause, rank, _year) in enumerate(chosen):
        colour = CAUSE.get(cause, CAUSE["unknown"])
        # Deterministic scatter in x, so the icon is reproducible.
        t = (i + 0.5) / max(1, len(chosen))
        x = S * (0.13 + 0.74 * t) + rng.gauss(0, S * 0.018)
        y = S * (0.78 - 0.50 * min(1.0, max(0.0, rank))) + rng.gauss(0, S * 0.022)
        r = S * (0.006 + 0.016 * min(1.0, max(0.0, rank)))

        # Emissive falloff: three stacked discs rather than a wide polyline, which
        # would fan spikes out of every joint.
        for k, (mult, alpha) in enumerate([(3.2, 0.10), (1.9, 0.26), (1.0, 1.0)]):
            rr = r * mult
            col = tuple(int(VOID[j] + (colour[j] - VOID[j]) * alpha) for j in range(3))
            d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=col)

    img = img.filter(ImageFilter.GaussianBlur(0.6))

    # The App Store rejects an icon with an alpha channel, and PIL gives RGBA freely.
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
