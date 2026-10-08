#!/usr/bin/env python3
"""Redfluent Mail (v0.39.3-rf6, Big5 level 1 added in rf7): make the bundled NotoSansSC a subset of
upstream's file.

The Flutter web engine downloads every font of FontManifest.json before the app starts
(flutter_web_sdk engine/initialization.dart, _downloadAssetFonts), so upstream's 10.5 MB
NotoSansSC-Regular.ttf was on every cold load. The subset keeps the glyphs (unchanged) of:
  * every character of the Simplified Chinese UI (lib/l10n/intl_zh_Hans.arb) and of non-ASCII
    characters written directly in the Dart sources (e.g. the language picker's own names);
  * the whole GB2312 character set: 6,763 hanzi (levels 1 and 2) + 682 symbols (punctuation,
    full-width forms, kana, Greek, Cyrillic, box drawing, pinyin...);
  * Basic Latin, Latin-1, General Punctuation, CJK Symbols and Punctuation, CJK Compatibility and
    Vertical Forms, Halfwidth and Fullwidth Forms;
  * every character that NO other font can draw: none of the other bundled fallback fonts
    (assets/fonts/fallback/*.ttf) and none of the web engine's fallback fonts in web/fonts/ (rf4)
    map it (mostly CJK Extension A and rare ideographs), so nothing upstream could draw becomes
    undrawable;
  * (rf7) every Big5 level-1 hanzi (0xA440-0xC67E, the 5,401 common Traditional Chinese characters)
    that no other BUNDLED font can draw (253 with these fonts): without it, they would wait for an
    engine font slice and show a box first; the other Big5 level-1 hanzi are drawn at once by GB2312
    above or by NotoSansKR.
with all OpenType layout features, names and hinting. Any other character is drawn by the next family
of ConstantsUI.webFontFamilyFallback that has it (NotoSansKR), else by the web engine's own fallback,
which loads the matching font slice from web/fonts/ first.

  python3 scripts/subset_noto_sans_sc.py ORIGINAL.ttf
    ORIGINAL.ttf = upstream's file, e.g. in the fork:
      git show v0.39.3:assets/fonts/fallback/NotoSansSC-Regular.ttf > /tmp/NotoSansSC-Regular.ttf
    or in the published repository (first commit = unmodified upstream tree):
      git show $(git rev-list --max-parents=0 HEAD):assets/fonts/fallback/NotoSansSC-Regular.ttf > /tmp/NotoSansSC-Regular.ttf
  Run from the repository root. Writes, only after checking the result:
    assets/fonts/fallback/NotoSansSC-Regular.ttf
    test/main/fonts/gb2312.txt   (the GB2312 characters, one line per GB2312 row, from Python's gb2312
                                  codec; test/main/fonts/redfluent_rf6_font_fallback_test.dart checks
                                  the font maps every one of them)
Requires scripts/requirements-subset.txt (fontTools + brotli, to read web/fonts/*.woff2); with those
versions the output is byte-for-byte reproducible.
License: SIL Open Font License 1.1, unchanged; the OFL allows subsetting. The font's copyright record
declares the Reserved Font Name 'Source' (Adobe, Source Han Sans); the subset keeps the family name
"Noto Sans SC", which does not use it, and all copyright and license name records."""
import hashlib
import json
import os
import re
import sys

from fontTools import subset
from fontTools.ttLib import TTFont

ORIGINAL_SHA256 = "ae82f4e2a55e1316a55bcc1d05e9555ce08d8bda07e893b486896b626fd852ff"
OUT = "assets/fonts/fallback/NotoSansSC-Regular.ttf"
GB2312_LIST = "test/main/fonts/gb2312.txt"
OTHER_BUNDLED = "assets/fonts/fallback"
ENGINE_FONTS = "web/fonts"
ARB = "lib/l10n/intl_zh_Hans.arb"
DART_DIRS = ["lib", "core/lib", "model/lib", "scribe/lib", "workplace/lib", "labels/lib"]
RANGES = [(0x20, 0x7E), (0xA0, 0xFF), (0x2000, 0x206F), (0x3000, 0x303F), (0xFE10, 0xFE1F),
          (0xFE30, 0xFE4F), (0xFF00, 0xFFEF)]


def read(path, mode="r"):
    with open(path, mode, **({} if "b" in mode else {"encoding": "utf-8"})) as f:
        return f.read()


def gb2312_rows():
    """GB2312 rows 1-87 (lead bytes 0xA1-0xF7), each a list of code points in GB2312 order."""
    rows = []
    for b1 in range(0xA1, 0xF8):
        row = []
        for b2 in range(0xA1, 0xFF):
            try:
                row.append(ord(bytes([b1, b2]).decode("gb2312")))
            except UnicodeDecodeError:
                pass
        if row:
            rows.append(row)
    return rows


def big5_level1():
    """Big5 level-1 hanzi: 0xA440-0xC67E (5,401 characters)."""
    out = set()
    for b1 in range(0xA4, 0xC7):
        for b2 in list(range(0x40, 0x7F)) + list(range(0xA1, 0xFF)):
            if (b1, b2) > (0xC6, 0x7E):
                continue
            try:
                out.add(ord(bytes([b1, b2]).decode("big5")))
            except UnicodeDecodeError:
                pass
    return out


def ui_chars():
    arb = json.loads(read(ARB))
    chars = {ord(c) for k, v in arb.items() if not k.startswith("@") and isinstance(v, str) for c in v}
    for d in DART_DIRS:
        for root, _, files in os.walk(d):
            for f in files:
                # messages_*.dart are generated from the .arb files (zh_Hant is not offered by the app)
                if f.endswith(".dart") and not re.match(r"messages_.*\.dart$", f):
                    chars |= {ord(c) for c in read(os.path.join(root, f)) if ord(c) > 0x7F}
    return chars


def cmap(path, lazy=True):
    with TTFont(path, lazy=lazy) as f:
        return set(f.getBestCmap() or {})


def drawable_elsewhere():
    """Code points the other bundled fallback fonts / the engine's fallback fonts can draw."""
    bundled = [os.path.join(OTHER_BUNDLED, f) for f in sorted(os.listdir(OTHER_BUNDLED))
               if f.endswith(".ttf") and f != os.path.basename(OUT)]
    engine = [os.path.join(root, f) for root, _, files in os.walk(ENGINE_FONTS) for f in sorted(files)
              if f.endswith(".woff2")]
    if len(engine) < 700:
        sys.exit("%s should hold the engine's 724 fallback fonts (rf4)" % ENGINE_FONTS)
    return set().union(*map(cmap, bundled)), set().union(*map(cmap, engine)), len(bundled) + len(engine)


def main():
    if len(sys.argv) != 2 or not os.path.isfile(ARB):
        sys.exit(__doc__)
    src = sys.argv[1]
    sha = hashlib.sha256(read(src, "rb")).hexdigest()
    if sha != ORIGINAL_SHA256:
        sys.exit("%s is not upstream's NotoSansSC-Regular.ttf (sha256 %s)" % (src, sha))
    rows = gb2312_rows()
    gb, ui, b5 = {c for r in rows for c in r}, ui_chars(), big5_level1()
    if len(gb) != 7445 or len(b5) != 5401:
        sys.exit("unexpected codec tables: GB2312 %d (want 7445), Big5 level 1 %d (want 5401)" % (len(gb), len(b5)))
    bundled, engine, n_fonts = drawable_elsewhere()
    elsewhere = bundled | engine
    have = cmap(src, lazy=False)
    only_here = have - elsewhere
    big5_box_first = (b5 & have) - gb - ui - bundled
    wanted = gb | ui | only_here | big5_box_first | {c for a, b in RANGES for c in range(a, b + 1)}

    opts = subset.Options()
    opts.layout_features = ["*"]
    opts.name_IDs = ["*"]
    opts.name_languages = ["*"]
    opts.notdef_outline = True
    sub = subset.Subsetter(opts)
    tmp = OUT + ".new"
    with TTFont(src, recalcTimestamp=False) as font:
        sub.populate(unicodes=wanted & have)
        sub.subset(font)
        font.save(tmp)

    # Check the file actually written before it replaces the committed one.
    kept = cmap(tmp, lazy=False)
    problems = {
        "UI": sorted(c for c in ui if c in have and c not in kept),
        "GB2312": sorted(c for c in gb if c not in kept),
        "drawable by no other font": sorted(have - kept - elsewhere),
        "Big5 level 1 needing an engine slice": sorted(c for c in b5 & have if c not in kept and c not in bundled),
        "not in upstream's font": sorted(kept - have),
    }
    bad = {k: v for k, v in problems.items() if v}
    if bad:
        os.remove(tmp)
        sys.exit("subset rejected, nothing written: " + "; ".join(
            "%s %d (%s)" % (k, len(v), "".join(map(chr, v[:20]))) for k, v in bad.items()))
    os.replace(tmp, OUT)
    with open(GB2312_LIST + ".new", "w", encoding="utf-8", newline="\n") as f:
        f.writelines("".join(map(chr, r)) + "\n" for r in rows)
    os.replace(GB2312_LIST + ".new", GB2312_LIST)

    no_glyph_ui = sorted(chr(c) for c in ui if c not in have and c > 0x2E7F)
    print("%s: %d -> %d bytes, %d -> %d code points (GB2312 %d, UI %d, only this font can draw %d, "
          "Big5 level 1 added because no other bundled font draws them %d; %d other fonts read)%s" % (
              OUT, os.path.getsize(src), os.path.getsize(OUT), len(have), len(kept), len(gb), len(ui),
              len(only_here), len(big5_box_first - only_here), n_fonts,
              "; not in upstream's font either: " + "".join(no_glyph_ui) if no_glyph_ui else ""))
    left = have - kept
    print("left to other fonts: %d code points: %d drawn at once by another bundled font, %d only by an "
          "engine font (drawn once its file is loaded)" % (len(left), len(left & bundled), len(left - bundled)))
    print("sha256", hashlib.sha256(read(OUT, "rb")).hexdigest())
    print("%s: %d rows, %d characters" % (GB2312_LIST, len(rows), len(gb)))


if __name__ == "__main__":
    main()
