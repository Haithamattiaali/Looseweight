#!/usr/bin/env python3
"""Download a sample of Nutrition5k plates for the accuracy check.

Nutrition5k (Google Research, Thames et al., CVPR 2021) has overhead RGB-D photos of cafeteria plates with
every ingredient weighed. Only the files needed for the check are downloaded, into eval-data/ (git-ignored).

For each dish this writes:
  eval-data/<dish>/rgb.jpg     overhead photo (640×480)
  eval-data/<dish>/depth.bin   depth, little-endian uint16, 640×480, units of 0.1 mm (0 = no reading)
  eval-data/<dish>/meta.json   weighed mass, calories, macros and ingredients
  eval-data/<dish>/food_mask.bin  uint8 640×480, 1 where the pixel is not white plate (a crude colour mask
                                  used only by the depth-only check; the AI check lets the model outline food)

Usage: python3 scripts/eval/prepare_nutrition5k.py [--dishes 30] [--out eval-data]
Needs: pip install pillow
"""
from __future__ import annotations

import argparse
import io
import json
import random
import urllib.request
from pathlib import Path

from PIL import Image

BASE = "https://storage.googleapis.com/nutrition5k_dataset/nutrition5k_dataset"


def fetch(path: str) -> bytes:
    with urllib.request.urlopen(f"{BASE}/{path}", timeout=60) as response:
        return response.read()


def parse_metadata(text: str) -> dict[str, dict]:
    dishes = {}
    for line in text.splitlines():
        parts = line.strip().split(",")
        if len(parts) < 6:
            continue
        dish = {
            "id": parts[0],
            "kcal": float(parts[1]),
            "mass_g": float(parts[2]),
            "fat_g": float(parts[3]),
            "carbs_g": float(parts[4]),
            "protein_g": float(parts[5]),
            "ingredients": [],
        }
        for i in range(6, len(parts) - 6, 7):
            dish["ingredients"].append({
                "name": parts[i + 1],
                "grams": float(parts[i + 2]),
                "kcal": float(parts[i + 3]),
                "fat_g": float(parts[i + 4]),
                "carbs_g": float(parts[i + 5]),
                "protein_g": float(parts[i + 6]),
            })
        dishes[dish["id"]] = dish
    return dishes


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dishes", type=int, default=30)
    parser.add_argument("--out", default="eval-data")
    parser.add_argument("--seed", type=int, default=5)
    args = parser.parse_args()

    metadata = parse_metadata(fetch("metadata/dish_metadata_cafe1.csv").decode())
    test_ids = fetch("dish_ids/splits/depth_test_ids.txt").decode().split()
    candidates = [d for d in test_ids if d in metadata and 40 <= metadata[d]["mass_g"] <= 900 and metadata[d]["kcal"] > 20]
    random.Random(args.seed).shuffle(candidates)

    out = Path(args.out)
    written = 0
    for dish_id in candidates:
        if written >= args.dishes:
            break
        folder = out / dish_id
        try:
            rgb = Image.open(io.BytesIO(fetch(f"imagery/realsense_overhead/{dish_id}/rgb.png"))).convert("RGB")
            depth = Image.open(io.BytesIO(fetch(f"imagery/realsense_overhead/{dish_id}/depth_raw.png")))
        except Exception as error:  # some dishes lack files
            print(f"skip {dish_id}: {error}")
            continue
        if depth.size != (640, 480) or rgb.size != (640, 480):
            print(f"skip {dish_id}: unexpected size")
            continue
        folder.mkdir(parents=True, exist_ok=True)
        rgb.save(folder / "rgb.jpg", quality=92)
        hsv = rgb.convert("HSV")
        mask = bytes(1 if (sat > 50 or val < 140) else 0 for _, sat, val in hsv.getdata())
        (folder / "food_mask.bin").write_bytes(mask)
        raw = depth.convert("I;16") if depth.mode != "I;16" else depth
        (folder / "depth.bin").write_bytes(raw.tobytes("raw", "I;16"))
        (folder / "meta.json").write_text(json.dumps(metadata[dish_id], indent=1))
        written += 1
        print(f"{written:3d} {dish_id} {metadata[dish_id]['mass_g']:.0f} g {metadata[dish_id]['kcal']:.0f} kcal")
    print(f"wrote {written} dishes to {out}")


if __name__ == "__main__":
    main()
