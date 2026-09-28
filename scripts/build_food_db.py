#!/usr/bin/env python3
"""Build the bundled food table for LooseweightKit.

Source: the `tempo-food-db` npm package (v1.0.0, CC-BY-4.0, TempoLife / Probyte OU).
7,233 of its rows are USDA FoodData Central SR Legacy (public domain); the rest
are curated rows from packaging labels and public tables.

The source truncates some long USDA names, so several rows share one name
(for example 32 rows of "Lamb, Australian, imported, fresh, leg"). Rows with the
same name are merged into one entry holding the median values plus the
[min, max] energy range of the merged rows. The app treats an entry with a range
as "ambiguous": the model may pick a value inside the range, never outside it.

Output: Packages/LooseweightKit/Sources/LooseweightKit/Resources/foods.json
  {"version": ..., "attribution": ..., "categories": [...], "fields": [...], "foods": [[...], ...]}

Usage: python3 scripts/build_food_db.py
"""
from __future__ import annotations

import base64
import collections
import hashlib
import io
import json
import statistics
import tarfile
import urllib.request
from pathlib import Path

PACKAGE_URL = "https://registry.npmjs.org/tempo-food-db/-/tempo-food-db-1.0.0.tgz"
PACKAGE_SHA512 = "wALzOQ7yFjiuvXvKLase8nf1rXj39Ws1QfcL2kemdpZOBlWI0yqfYRHp/h/odaCH1VEB7E1eSdPXfZ9+mg92/w=="
OUT = Path(__file__).resolve().parent.parent / "Packages/LooseweightKit/Sources/LooseweightKit/Resources/foods.json"

CATEGORIES = {
    "Liha ja linnuliha": "Meat & poultry",
    "Köögivili": "Vegetables",
    "Leivad ja pagarittooted": "Breads & bakery",
    "Valmistoidud": "Prepared meals",
    "Puuviljad ja marjad": "Fruits & berries",
    "Magustoidud ja küpsetised": "Desserts & baked goods",
    "Joogid": "Drinks",
    "Piimatooted": "Dairy",
    "Kaunviljad": "Legumes",
    "Kala ja mereannid": "Fish & seafood",
    "Rasvad ja õlid": "Fats & oils",
    "Hommikusöögid": "Breakfast",
    "Teravili ja pasta": "Grains & pasta",
    "Pähklid ja seemned": "Nuts & seeds",
    "Supid": "Soups",
    "Snäkid ja suupisted": "Snacks",
    "Kartulid ja mugulad": "Potatoes & tubers",
    "Kastmed ja maitsed": "Sauces & condiments",
    "Eesti toidud": "Regional dishes",
    "Vürtsid ja maitseained": "Spices & seasonings",
    "Munad": "Eggs",
    "Salatid": "Salads",
}
CATEGORY_LIST = sorted(set(CATEGORIES.values()))

FIELDS = [
    "id", "name", "category", "kcal", "protein", "carbs", "fat", "fiber",
    "sugar", "saturatedFat", "sodiumMg", "source", "kcalRange",
]


def download() -> list[dict]:
    with urllib.request.urlopen(PACKAGE_URL, timeout=60) as response:
        blob = response.read()
    digest = base64.b64encode(hashlib.sha512(blob).digest()).decode()
    if digest != PACKAGE_SHA512:
        raise SystemExit(f"integrity mismatch: {digest}")
    with tarfile.open(fileobj=io.BytesIO(blob), mode="r:gz") as tar:
        member = tar.extractfile("package/data/tempolife-foods.json")
        assert member is not None
        return json.load(member)


def rounded(value: float | None, digits: int = 2) -> float | None:
    if value is None:
        return None
    return round(float(value), digits)


def median_of(rows: list[dict], key: str) -> float | None:
    values = [row[key] for row in rows if row.get(key) is not None]
    return statistics.median(values) if values else None


def build(rows: list[dict]) -> dict:
    groups: dict[tuple[str, str], list[dict]] = collections.defaultdict(list)
    for row in rows:
        name = " ".join(row["name"].split())
        category = CATEGORIES[row["category"]]
        groups[(name, category)].append(row)

    foods = []
    for (name, category), members in sorted(groups.items()):
        kcal = median_of(members, "kcal_per_100g")
        salt = median_of(members, "salt_g")
        energies = [m["kcal_per_100g"] for m in members]
        kcal_range = None
        if len(members) > 1 and max(energies) > min(energies):
            kcal_range = [rounded(min(energies), 0), rounded(max(energies), 0)]
        source = 0 if all(m.get("source") == "usda_sr_legacy" for m in members) else 1
        food_id = hashlib.sha1(f"{name}|{category}".encode()).hexdigest()[:10]
        foods.append([
            food_id,
            name,
            CATEGORY_LIST.index(category),
            rounded(kcal, 1),
            rounded(median_of(members, "protein_g")),
            rounded(median_of(members, "carbs_g")),
            rounded(median_of(members, "fat_g")),
            rounded(median_of(members, "fiber_g")),
            rounded(median_of(members, "sugar_g")),
            rounded(median_of(members, "saturated_fat_g")),
            None if salt is None else round(salt * 1000 / 2.5),
            source,
            kcal_range,
        ])

    ids = [food[0] for food in foods]
    if len(ids) != len(set(ids)):
        raise SystemExit("id collision")
    return {
        "version": "tempo-food-db@1.0.0+lw1",
        "attribution": "Food nutrition data from TempoLife (tempolife.app), CC-BY-4.0. Underlying USDA FoodData Central SR Legacy data is public domain.",
        "units": "per 100 g; sodium in mg",
        "categories": CATEGORY_LIST,
        "fields": FIELDS,
        "foods": foods,
    }


def main() -> None:
    table = build(download())
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(table, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    ambiguous = sum(1 for food in table["foods"] if food[-1])
    print(f"wrote {OUT} — {len(table['foods'])} foods ({ambiguous} with an energy range)")


if __name__ == "__main__":
    main()
