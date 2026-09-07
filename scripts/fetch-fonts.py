#!/usr/bin/env python3
"""Convert Excalidraw's own fonts to ttf so previews use the real typefaces.

Excalidraw ships them as woff2, which CoreText cannot register, so this pulls
each one from the excalidraw repo, pins any variable axis to regular weight,
and rewrites it as ttf under Resources/Fonts with the family name the renderer
looks for. Optional: without it the renderer falls back to installed lookalikes.
"""

import io
import json
import pathlib
import sys
import urllib.request

from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

REPO = "https://api.github.com/repos/excalidraw/excalidraw/contents"
FONTS = "packages/excalidraw/fonts"
OUT = pathlib.Path(__file__).resolve().parent.parent / "Resources" / "Fonts"

# Directory in the excalidraw repo -> the family name Style.swift asks for.
FAMILIES = {
    "Excalifont": "Excalifont",
    "Nunito": "Nunito",
    "ComicShanns": "Comic Shanns",
    "Cascadia": "Cascadia Code",
    "Lilita": "Lilita One",
    "Assistant": "Assistant",
    "Virgil": "Virgil",
}


def fetch(url):
    with urllib.request.urlopen(url) as response:
        return response.read()


def rename(font, family):
    """Force the family/style names, so an axis instance named
    'Nunito ExtraLight Medium' still registers as plain 'Nunito'."""
    table = font["name"]
    for record in list(table.names):
        if record.nameID in (1, 16):
            table.setName(family, record.nameID, record.platformID,
                          record.platEncID, record.langID)
        elif record.nameID in (2, 17):
            table.setName("Regular", record.nameID, record.platformID,
                          record.platEncID, record.langID)
        elif record.nameID == 4:
            table.setName(f"{family} Regular", record.nameID, record.platformID,
                          record.platEncID, record.langID)
        elif record.nameID == 6:
            table.setName(f"{family.replace(' ', '')}-Regular", record.nameID,
                          record.platformID, record.platEncID, record.langID)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for directory, family in FAMILIES.items():
        try:
            listing = json.loads(fetch(f"{REPO}/{FONTS}/{directory}"))
        except Exception as error:
            print(f"{family}: skipped ({error})", file=sys.stderr)
            continue

        woffs = [f for f in listing if f["name"].endswith(".woff2")]
        if not woffs:
            print(f"{family}: no woff2 found", file=sys.stderr)
            continue

        # The subsets differ only by unicode-range; the biggest covers the most.
        best = max(woffs, key=lambda f: f["size"])
        try:
            font = TTFont(io.BytesIO(fetch(best["download_url"])))
            if "fvar" in font:
                axes = {axis.axisTag: 400 for axis in font["fvar"].axes if axis.axisTag == "wght"}
                if axes:
                    font = instantiateVariableFont(font, axes, inplace=False)
            rename(font, family)
            font.flavor = None
            path = OUT / f"{family.replace(' ', '')}.ttf"
            font.save(path)
            print(f"{family}: {path.name} ({len(font.getGlyphOrder())} glyphs)")
        except Exception as error:
            print(f"{family}: conversion failed ({error})", file=sys.stderr)


if __name__ == "__main__":
    main()
