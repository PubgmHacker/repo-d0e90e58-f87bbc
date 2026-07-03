#!/usr/bin/env python3
"""
Round 2: Download remaining Russian service logos from alternative sources.
Uses favicon APIs + brand page SVGs as fallback.
"""
import os
import urllib.request
import time
import cairosvg
from PIL import Image
import json
import shutil

DEST_BASE = "/home/z/my-project/raveclone-review-v2/Plink/Resources/Assets.xcassets"
TMP_DIR = "/tmp/service_logos"
os.makedirs(TMP_DIR, exist_ok=True)

# Try multiple sources for each missing logo
SOURCES = {
    "rutube": [
        # Try Wikimedia variants first
        ("svg", "https://upload.wikimedia.org/wikipedia/commons/3/34/Rutube_logo_2020.svg"),
        ("svg", "https://upload.wikimedia.org/wikipedia/ru/8/87/Rutube_logo.svg"),
        # Fallback: official site favicon
        ("favicon", "https://rutube.ru/favicon.ico"),
        ("google_favicon", "https://www.google.com/s2/favicons?domain=rutube.ru&sz=128"),
    ],
    "kinopoisk": [
        ("svg", "https://upload.wikimedia.org/wikipedia/ru/9/9a/Kinopoisk_2022.svg"),
        ("svg", "https://upload.wikimedia.org/wikipedia/ru/4/4f/%D0%9A%D0%B8%D0%BD%D0%BE%D0%BF%D0%BE%D0%B8%D1%81%D0%BA_2022.svg"),
        ("favicon", "https://kinopoisk.ru/favicon.ico"),
        ("google_favicon", "https://www.google.com/s2/favicons?domain=kinopoisk.ru&sz=128"),
    ],
    "ivi": [
        ("svg", "https://upload.wikimedia.org/wikipedia/ru/0/08/Ivi.ru_logo.svg"),
        ("svg", "https://upload.wikimedia.org/wikipedia/commons/8/8c/Ivi.ru_logo.svg"),
        ("google_favicon", "https://www.google.com/s2/favicons?domain=ivi.ru&sz=128"),
    ],
    "okko": [
        ("svg", "https://upload.wikimedia.org/wikipedia/ru/2/20/Okko_logo.svg"),
        ("svg", "https://upload.wikimedia.org/wikipedia/commons/4/4c/Okko_logo.svg"),
        ("google_favicon", "https://www.google.com/s2/favicons?domain=okko.tv&sz=128"),
    ],
    "wink": [
        ("svg", "https://upload.wikimedia.org/wikipedia/ru/5/5e/Wink_logo.svg"),
        ("google_favicon", "https://www.google.com/s2/favicons?domain=wink.ru&sz=128"),
    ],
    "start": [
        ("svg", "https://upload.wikimedia.org/wikipedia/ru/9/91/Start_logo.svg"),
        ("google_favicon", "https://www.google.com/s2/favicons?domain=start.ru&sz=128"),
    ],
    "premier": [
        ("svg", "https://upload.wikimedia.org/wikipedia/ru/c/cb/Premier_logo.svg"),
        ("google_favicon", "https://www.google.com/s2/favicons?domain=premier.one&sz=128"),
    ],
    "smotrim": [
        ("svg", "https://upload.wikimedia.org/wikipedia/ru/c/c1/%D0%A1%D0%BC%D0%BE%D1%82%D1%80%D0%B8%D0%BC_logo.svg"),
        ("google_favicon", "https://www.google.com/s2/favicons?domain=smotrim.ru&sz=128"),
    ],
    "kion": [
        ("svg", "https://upload.wikimedia.org/wikipedia/ru/3/32/Kion_logo.svg"),
        ("google_favicon", "https://www.google.com/s2/favicons?domain=kion.ru&sz=128"),
    ],
}

OUTPUT_SIZE = 240


def fetch(url, dest):
    req = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
        "Accept": "*/*",
    })
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            data = resp.read()
            with open(dest, "wb") as f:
                f.write(data)
        return len(data)
    except Exception as e:
        return 0


def is_valid_svg(path):
    try:
        with open(path, "r", errors="ignore") as f:
            content = f.read(2000)
        return "<svg" in content.lower() and len(content) > 100
    except Exception:
        return False


def is_valid_png(path):
    try:
        with Image.open(path) as img:
            img.verify()
        return True
    except Exception:
        return False


def svg_to_png(name, svg_path):
    png_path = os.path.join(TMP_DIR, f"{name}.png")
    try:
        cairosvg.svg2png(
            url=svg_path,
            write_to=png_path,
            output_width=OUTPUT_SIZE,
            output_height=OUTPUT_SIZE,
        )
        return png_path if is_valid_png(png_path) else None
    except Exception:
        return None


def png_to_imageset(name, png_path):
    """Copy PNG into Assets.xcassets structure."""
    imageset_dir = os.path.join(DEST_BASE, f"ServiceLogo{name.capitalize()}.imageset")
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


def resize_png(name, png_path):
    """Resize PNG to OUTPUT_SIZE x OUTPUT_SIZE with transparent padding."""
    out_path = os.path.join(TMP_DIR, f"{name}_resized.png")
    with Image.open(png_path) as img:
        img = img.convert("RGBA")
        # Make square with transparent padding
        max_dim = max(img.width, img.height)
        canvas = Image.new("RGBA", (max_dim, max_dim), (0, 0, 0, 0))
        offset = ((max_dim - img.width) // 2, (max_dim - img.height) // 2)
        canvas.paste(img, offset, img)
        canvas = canvas.resize((OUTPUT_SIZE, OUTPUT_SIZE), Image.LANCZOS)
        canvas.save(out_path)
    return out_path


def main():
    print("=== Round 2: Downloading remaining logos ===\n")
    success = []
    failed = []

    for name, sources in SOURCES.items():
        print(f"[{name}]")
        got = False
        for kind, url in sources:
            time.sleep(1.5)  # avoid rate limit
            ext = "svg" if kind == "svg" else "png"
            tmp = os.path.join(TMP_DIR, f"{name}_try.{ext}")
            size = fetch(url, tmp)
            if size < 200:
                print(f"  try {kind}: too small ({size}b)")
                continue

            if kind == "svg":
                if not is_valid_svg(tmp):
                    print(f"  try svg: invalid SVG")
                    continue
                png_path = svg_to_png(name, tmp)
                if not png_path:
                    print(f"  try svg: conversion failed")
                    continue
            else:
                # favicon or google_favicon — already PNG
                if not is_valid_png(tmp):
                    print(f"  try {kind}: invalid PNG")
                    continue
                png_path = tmp

            # Resize to uniform 240x240
            png_path = resize_png(name, png_path)
            print(f"  ✅ {kind}: OK ({size}b → {png_path})")
            imageset_dir = png_to_imageset(name, png_path)
            success.append((name, imageset_dir))
            got = True
            break

        if not got:
            print(f"  ❌ ALL SOURCES FAILED")
            failed.append(name)

    print(f"\n=== Round 2 Summary ===")
    print(f"✅ Success: {len(success)}")
    for n, p in success:
        print(f"   - {n}")
    print(f"❌ Failed: {len(failed)}: {failed}")

    # Update manifest
    manifest_path = os.path.join(TMP_DIR, "manifest.json")
    existing = {}
    if os.path.exists(manifest_path):
        with open(manifest_path) as f:
            existing = json.load(f)
    existing_success = set(existing.get("success", []))
    existing_success.update(s[0] for s in success)
    existing["success"] = sorted(existing_success)
    existing["failed"] = failed
    existing["image_names"] = {n: f"ServiceLogo{n.capitalize()}" for n in existing_success}
    with open(manifest_path, "w") as f:
        json.dump(existing, f, indent=2)
    print(f"\nFinal manifest: {manifest_path}")


if __name__ == "__main__":
    main()
