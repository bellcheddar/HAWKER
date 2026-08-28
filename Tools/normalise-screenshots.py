#!/usr/bin/env python3
"""
Force every capture to the exact pixel size its App Store display type accepts.

The simulators do not all hand back a size Apple will take. An iPhone 14 Plus
gives 1284x2778 where the 6.5-inch slot wants 1242x2688, and a 13-inch iPad Pro
(M5) gives 2064x2752 where APP_IPAD_PRO_3GEN_129 wants 2048x2732. Uploading a
wrong size fails late, after the asset has been reserved and sent.

Also flattens to RGB: the App Store rejects an alpha channel, and a window
capture taken without -o carries one from the drop shadow.

    python3 Tools/normalise-screenshots.py
"""
from pathlib import Path

from PIL import Image

# display type -> (directory, exact accepted size)
TARGETS = {
    "APP_IPHONE_67":          ("assets/screenshots/iphone69", (1320, 2868)),
    "APP_IPHONE_65":          ("assets/screenshots/iphone65", (1242, 2688)),
    "APP_IPAD_PRO_3GEN_129":  ("assets/screenshots/ipad13",   (2048, 2732)),
    "APP_WATCH_SERIES_10":    ("assets/screenshots/watch",    (416, 496)),
    "APP_APPLE_VISION_PRO":   ("assets/screenshots/visionos", (3840, 2160)),
    "APP_DESKTOP":            ("assets/screenshots/macos",    (2880, 1800)),
}


def normalise(path: Path, size: tuple[int, int]) -> str:
    with Image.open(path) as image:
        original = image.size
        mode = image.mode
        out = image.convert("RGB") if mode != "RGB" else image.copy()
        if out.size != size:
            # LANCZOS: these are text-heavy UI captures and a cheaper filter
            # visibly softens the monospaced numerals.
            out = out.resize(size, Image.LANCZOS)
        out.save(path, "PNG")
    changed = original != size or mode != "RGB"
    return f"{original[0]}x{original[1]} {mode} -> {size[0]}x{size[1]} RGB" if changed else "already correct"


def main() -> None:
    for display, (directory, size) in TARGETS.items():
        folder = Path(directory)
        shots = sorted(folder.glob("*.png")) if folder.is_dir() else []
        if not shots:
            print(f"{display:24s} {directory}: no captures")
            continue
        print(f"{display:24s} {directory}  ({len(shots)} shots)")
        for shot in shots:
            print(f"    {shot.name:18s} {normalise(shot, size)}")


if __name__ == "__main__":
    main()
