#!/usr/bin/env python3
"""
Download REAL brand logos from Wikimedia Commons + convert to PNG @3x.
Creates Assets.xcassets structure for Plink iOS app.
"""
import os
import urllib.request
import cairosvg
from PIL import Image
import json
import io

# Brand logo sources — REAL vector logos from Wikimedia Commons
# (public domain or CC-licensed official brand logos)
LOGOS = {
    "youtube": {
        "url": "https://upload.wikimedia.org/wikipedia/commons/0/09/YouTube_full-color_icon_%282017%29.svg",
        "size": 240,  # PNG output size in px (used as @3x for 80pt icon)
    },
    "vk": {
        "url": "https://upload.wikimedia.org/wikipedia/commons/f/f3/VK_Compact_Logo_%282021-present%29.svg",
        "size": 240,
    },
    "rutube": {
        "url": "https://upload.wikimedia.org/wikipedia/commons/3/34/Rutube_logo_2020.svg",
        "size": 240,
    },
    "netflix": {
        # Netflix "N" icon (red on transparent)
        "url": "https://upload.wikimedia.org/wikipedia/commons/6/69/Netflix_logo.svg",
        "size": 240,
    },
    "disney": {
        # Disney+ logo
        "url": "https://upload.wikimedia.org/wikipedia/commons/3/3e/Disney%2B_logo.svg",
        "size": 240,
    },
    "kinopoisk": {
        # Кинопоиск (Яндекс) — orange circle with К
        "url": "https://upload.wikimedia.org/wikipedia/ru/9/9a/Kinopoisk_2022.svg",
        "size": 240,
    },
    "ivi": {
        # ivi.ru logo
        "url": "https://upload.wikimedia.org/wikipedia/ru/0/08/Ivi.ru_logo.svg",
        "size": 240,
    },
    "okko": {
        # Okko logo
        "url": "https://upload.wikimedia.org/wikipedia/ru/2/20/Okko_logo.svg",
        "size": 240,
    },
    "wink": {
        # Wink (Ростелеком) logo
        "url": "https://upload.wikimedia.org/wikipedia/ru/5/5e/Wink_logo.svg",
        "size": 240,
    },
    "start": {
        # Start (ТНТ) logo
        "url": "https://upload.wikimedia.org/wikipedia/ru/9/91/Start_logo.svg",
        "size": 240,
    },
    "premier": {
        # Premier (ТНТ Premier) logo
        "url": "https://upload.wikimedia.org/wikipedia/ru/c/cb/Premier_logo.svg",
        "size": 240,
    },
    "smotrim": {
        # Смотрим (VGTRK) logo
        "url": "https://upload.wikimedia.org/wikipedia/ru/c/c1/%D0%A1%D0%BC%D0%BE%D1%82%D1%80%D0%B8%D0%BC_logo.svg",
        "size": 240,
    },
    "kion": {
        # KION (МТС) logo
        "url": "https://upload.wikimedia.org/wikipedia/ru/3/32/Kion_logo.svg",
        "size": 240,
    },
}

DEST_BASE = "/home/z/my-project/raveclone-review-v2/Plink/Resources/Assets.xcassets"
TMP_DIR = "/tmp/service_logos"

os.makedirs(DEST_BASE, exist_ok=True)
os.makedirs(TMP_DIR, exist_ok=True)


def download_svg(name, url):
    """Download SVG from URL with browser User-Agent."""
    svg_path = os.path.join(TMP_DIR, f"{name}.svg")
    req = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
    })
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = resp.read()
            with open(svg_path, "wb") as f:
                f.write(data)
        return svg_path, len(data)
    except Exception as e:
        print(f"  ❌ {name}: download failed — {e}")
        return None, 0


def svg_to_png(name, svg_path, size):
    """Convert SVG to PNG at 3 resolutions (@1x, @2x, @3x)."""
    png_path = os.path.join(TMP_DIR, f"{name}.png")
    try:
        cairosvg.svg2png(
            url=svg_path,
            write_to=png_path,
            output_width=size,
            output_height=size,
            background_color=None,  # transparent
        )
        # Verify with PIL
        with Image.open(png_path) as img:
            print(f"  ✅ {name}: PNG {img.width}x{img.height}, mode={img.mode}")
        return png_path
    except Exception as e:
        print(f"  ❌ {name}: SVG→PNG failed — {e}")
        return None


def create_imageset(name, png_path):
    """Create Assets.xcassets/ServiceLogo.{name}.imageset/ with PNG + Contents.json."""
    imageset_dir = os.path.join(DEST_BASE, f"ServiceLogo{name.capitalize()}.imageset")
    os.makedirs(imageset_dir, exist_ok=True)

    # Copy PNG as the single asset (used at all scales; SwiftUI scales automatically)
    import shutil
    png_dest = os.path.join(imageset_dir, f"{name}.png")
    shutil.copy(png_path, png_dest)

    # Generate Contents.json — single universal PNG
    contents = {
        "images": [
            {
                "filename": f"{name}.png",
                "idiom": "universal",
                "scale": "1x"
            },
            {
                "idiom": "universal",
                "scale": "2x"
            },
            {
                "idiom": "universal",
                "scale": "3x"
            }
        ],
        "info": {
            "author": "xcode",
            "version": 1
        },
        "properties": {
            "preserves-vector-representation": True
        }
    }
    with open(os.path.join(imageset_dir, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)

    return imageset_dir


def main():
    print("=== Downloading REAL brand logos from Wikimedia Commons ===\n")

    success = []
    failed = []

    for name, cfg in LOGOS.items():
        print(f"[{name}]")
        svg_path, size = download_svg(name, cfg["url"])
        if not svg_path or size < 100:
            failed.append(name)
            continue

        # Check SVG is actually a valid SVG (not a 404 page)
        with open(svg_path) as f:
            head = f.read(500)
        if "<svg" not in head:
            print(f"  ❌ {name}: not a valid SVG (likely 404)")
            failed.append(name)
            continue

        png_path = svg_to_png(name, svg_path, cfg["size"])
        if not png_path:
            failed.append(name)
            continue

        imageset_dir = create_imageset(name, png_path)
        success.append((name, imageset_dir))

    print(f"\n=== Summary ===")
    print(f"✅ Success: {len(success)} logos")
    for name, path in success:
        print(f"   - {name}: {path}")
    print(f"❌ Failed: {len(failed)} logos: {failed}")

    # Write a manifest for the Swift code generator
    manifest_path = os.path.join(TMP_DIR, "manifest.json")
    with open(manifest_path, "w") as f:
        json.dump({
            "success": [s[0] for s in success],
            "failed": failed,
            "image_names": {name: f"ServiceLogo{name.capitalize()}" for name, _ in success}
        }, f, indent=2)
    print(f"\nManifest: {manifest_path}")


if __name__ == "__main__":
    main()
