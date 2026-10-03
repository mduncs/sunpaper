#!/usr/bin/env python3
"""Write a copy of an aerial catalog (entries.json) with one custom asset added.

Never edits the input in place. Usage:
  add-catalog-entry.py IN.json OUT.json --id UUID --name "My Video" \
      --video "/abs/path/videos/UUID.mov" --thumb "/abs/path/thumbnails/UUID.png"

The asset goes into a "Custom" category (created on first use) with its own
subcategory. Field set mirrors Apple's entries on macOS 27.2 plus what LivePaper
writes; previewImage and url-4K-SDR-240FPS are file:// URLs.
See scripts/video/README.md.
"""
import argparse
import json
import pathlib
import uuid

CATEGORY_ID = "5E1C0A7A-0000-4000-8000-53554E504150"  # fixed so re-runs reuse it


def main():
    p = argparse.ArgumentParser()
    p.add_argument("src")
    p.add_argument("dst")
    p.add_argument("--id", required=True)
    p.add_argument("--name", required=True)
    p.add_argument("--video", required=True)
    p.add_argument("--thumb", required=True)
    a = p.parse_args()

    src, dst = pathlib.Path(a.src), pathlib.Path(a.dst)
    if src.resolve() == dst.resolve():
        raise SystemExit("refusing to overwrite the input catalog")
    catalog = json.loads(src.read_text())

    asset_id = a.id.upper()
    if any(x["id"] == asset_id for x in catalog["assets"]):
        raise SystemExit(f"asset {asset_id} already present")
    video_url = pathlib.Path(a.video).as_uri()
    thumb_url = pathlib.Path(a.thumb).as_uri()
    sub_id = str(uuid.uuid4()).upper()

    category = next((c for c in catalog["categories"] if c["id"] == CATEGORY_ID), None)
    if category is None:
        category = {
            "id": CATEGORY_ID,
            "localizedNameKey": "Custom",
            "localizedDescriptionKey": "Custom videos",
            "preferredOrder": 99,
            "previewImage": thumb_url,
            "representativeAssetID": asset_id,
            "subcategories": [],
        }
        catalog["categories"].append(category)
    category["subcategories"].append({
        "id": sub_id,
        "localizedNameKey": a.name,
        "localizedDescriptionKey": a.name,
        "preferredOrder": len(category["subcategories"]),
        "previewImage": thumb_url,
        "representativeAssetID": asset_id,
    })
    catalog["assets"].append({
        "accessibilityLabel": a.name,
        "categories": [CATEGORY_ID],
        "id": asset_id,
        "includeInShuffle": False,
        "localizedNameKey": a.name,
        "pointsOfInterest": {},
        "preferredOrder": 1000 + len(category["subcategories"]),
        "previewImage": thumb_url,
        "shotID": "CUSTOM_" + asset_id[:8],
        "showInTopLevel": True,
        "subcategories": [sub_id],
        "url-4K-SDR-240FPS": video_url,
    })

    dst.write_text(json.dumps(catalog, indent=2, ensure_ascii=False))
    print(f"wrote {dst}: {len(catalog['assets'])} assets, subcategory {sub_id}")
    print(f"also install: {a.video} and thumbnails/{asset_id}.png + thumbnails/{sub_id}.png (214x130 PNG)")


if __name__ == "__main__":
    main()
