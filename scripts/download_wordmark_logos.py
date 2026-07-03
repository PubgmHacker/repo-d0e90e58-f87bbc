#!/usr/bin/env python3
"""
Download FULL wordmark logos (with brand name text) for all services.
These are horizontal logos with the full brand name, not just icons.
"""
import os
import urllib.request
import time
import cairosvg
from PIL import Image
import json
import shutil

DEST_BASE = "/home/z/my-project/raveclone-review-v2/Plink/Resources/Assets.xcassets"
TMP_DIR = "/tmp/service_logos_wordmark"
os.makedirs(TMP_DIR, exist_ok=True)

# Full wordmark logos (horizontal, with brand name text)
# Sources: Wikimedia Commons (SVG) + official brand pages
LOGOS = {
    "youtube": [
        # YouTube full logo (red + black text)
        ("svg", "https://upload.wikimedia.org/wikipedia/commons/b/b8/YouTube_Logo.svg"),
    ],
    "vkvideo": [
        # VK Видео — try Wikimedia first, then VK's official
        ("svg", "https://upload.wikimedia.org/wikipedia/commons/f/f3/VK_Compact_Logo_%282021-present%29.svg"),
    ],
    "rutube": [
        ("svg", "https://upload.wikimedia.org/wikipedia/commons/3/34/Rutube_logo_2020.svg"),
    ],
    "netflix": [
        # Netflix full wordmark
        ("svg", "https://upload.wikimedia.org/wikipedia/commons/7/7a/Netflix_2014_logo.svg"),
    ],
    "disney": [
        # Disney+ full logo
        ("svg", "https://upload.wikimedia.org/wikipedia/commons/3/3e/Disney%2B_logo.svg"),
    ],
    "kinopoisk": [
        # Кинопоиск full wordmark
        ("svg", "https://upload.wikimedia.org/wikipedia/ru/9/9a/Kinopoisk_2022.svg"),
    ],
    "ivi": [
        ("svg", "https://upload.wikimedia.org/wikipedia/ru/0/08/Ivi.ru_logo.svg"),
    ],
    "okko": [
        ("svg", "https://upload.wikimedia.org/wikipedia/ru/2/20/Okko_logo.svg"),
    ],
    "wink": [
        ("svg", "https://upload.wikimedia.org/wikipedia/ru/5/5e/Wink_logo.svg"),
    ],
    "start": [
        ("svg", "https://upload.wikimedia.org/wikipedia/ru/9/91/Start_logo.svg"),
    ],
    "premier": [
        ("svg", "https://upload.wikimedia.org/wikipedia/ru/c/cb/Premier_logo.svg"),
    ],
    "smotrim": [
        ("svg", "https://upload.wikimedia.org/wikipedia/ru/c/c1/%D0%A1%D0%BC%D0%BE%D1%82%D1%80%D0%B8%D0%BC_logo.svg"),
    ],
    "kion": [
        ("svg", "https://upload.wikimedia.org/wikipedia/ru/3/32/Kion_logo.svg"),
    ],
}

OUTPUT_WIDTH = 480  # wider for wordmarks (horizontal aspect ratio)


def fetch(url, dest):
    req = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
        "Accept": "*/*",
    })
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = resp.read()
            with open(dest, "wb") as f:
                f.write(data)
        return len(data)
    except Exception:
        return 0


def is_valid_svg(path):
    try:
        with open(path, "r", errors="ignore") as f:
            content = f.read(2000)
        return "<svg" in content.lower() and len(content) > 100
    except Exception:
        return False


def svg_to_png(name, svg_path, width):
    """Convert SVG to PNG preserving aspect ratio (height auto-scaled)."""
    png_path = os.path.join(TMP_DIR, f"{name}.png")
    try:
        cairosvg.svg2png(
            url=svg_path,
            write_to=png_path,
            output_width=width,
        )
        # Verify
        with Image.open(png_path) as img:
            print(f"  ✅ {name}: {img.width}x{img.height}")
        return png_path
    except Exception as e:
        print(f"  ❌ {name}: SVG→PNG failed — {e}")
        return None


def trim_transparent(png_path):
    """Trim transparent borders so the logo fits tightly."""
    with Image.open(png_path) as img:
        img = img.convert("RGBA")
        bbox = img.getbbox()
        if bbox:
            img = img.crop(bbox)
        # Add small padding (5%)
        pad_x = max(8, img.width // 20)
        pad_y = max(8, img.height // 20)
        canvas = Image.new("RGBA", (img.width + 2*pad_x, img.height + 2*pad_y), (0,0,0,0))
        canvas.paste(img, (pad_x, pad_y))
        out = png_path.replace(".png", "_trimmed.png")
        canvas.save(out)
        return out


def create_imageset(name, png_path):
    """Create Assets.xcassets/ServiceLogo{name}Wordmark.imageset/"""
    imageset_dir = os.path.join(DEST_BASE, f"ServiceLogo{name.capitalize()}Wordmark.imageset")
    os.makedirs(imageset_dir, exist_ok=True)
    png_dest = os.path.join(imageset_dir, f"{name}.png")
    shutil.copy(png_path, png_dest)

    contents = {
        "images": [
            {"filename": f"{name}.png", "idiom": "universal", "scale": "1x"},
            {"idiom": "universal", "scale": "2x"},
            {"idiom": "universal", "scale": "3x"},
        ],
        "info": {"author": "xcode", "version": 1},
        "properties": {"preserves-vector-representation": True},
    }
    with open(os.path.join(imageset_dir, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)
    return imageset_dir


def main():
    print("=== Downloading FULL wordmark logos ===\n")
    success = []
    failed = []

    for name, sources in LOGOS.items():
        print(f"[{name}]")
        got = False
        for kind, url in sources:
            time.sleep(1.5)
            tmp = os.path.join(TMP_DIR, f"{name}.svg")
            size = fetch(url, tmp)
            if size < 200:
                print(f"  try {kind}: download failed ({size}b)")
                continue
            if kind == "svg" and not is_valid_svg(tmp):
                print(f"  try svg: invalid SVG")
                continue
            png_path = svg_to_png(name, tmp, OUTPUT_WIDTH)
            if not png_path:
                continue
            # Trim transparent borders
            png_path = trim_transparent(png_path)
            imageset_dir = create_imageset(name, png_path)
            success.append((name, imageset_dir))
            got = True
            break
        if not got:
            print(f"  ❌ ALL SOURCES FAILED for {name}")
            failed.append(name)

    print(f"\n=== Summary ===")
    print(f"✅ Success: {len(success)}")
    for n, p in success:
        print(f"   - {n}")
    print(f"❌ Failed: {len(failed)}: {failed}")

    # Manifest
    manifest = {
        "success": [s[0] for s in success],
        "failed": failed,
        "image_names": {n: f"ServiceLogo{n.capitalize()}Wordmark" for n, _ in success}
    }
    with open(os.path.join(TMP_DIR, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2)
    print(f"\nManifest: {TMP_DIR}/manifest.json")


if __name__ == "__main__":
    main()
