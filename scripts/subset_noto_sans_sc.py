#!/usr/bin/env python3
"""Redfluent Mail (v0.39.3-rf6): make the bundled NotoSansSC a subset of upstream's file.

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
with all OpenType layout features, names and hinting. Any other character is drawn by the next family
of ConstantsUI.webFontFamilyFallback that has it (NotoSansKR), else by the web engine's own fallback,
which loads the matching font slice from web/fonts/ first.

  python3 scripts/subset_noto_sans_sc.py ORIGINAL.ttf
    ORIGINAL.ttf = upstream's file, e.g. in the fork:
      git show v0.39.3:assets/fonts/fallback/NotoSansSC-Regular.ttf > /tmp/NotoSansSC-Regular.ttf
    or in the published repository (first commit = unmodified upstream tree):
      git show $(git rev-list --max-parents=0 HEAD):assets/fonts/fallback/NotoSansSC-Regular.ttf > /tmp/NotoSansSC-Regular.ttf
  Writes assets/fonts/fallback/NotoSansSC-Regular.ttf (run from the repository root).
Requires fontTools with brotli (to read web/fonts/*.woff2); made with fonttools 4.60.1 + brotli 1.1.0,
with which the output is byte-for-byte reproducible.
License: SIL Open Font License 1.1, unchanged (the OFL allows subsetting; Noto declares no Reserved
Font Name)."""
import hashlib
import json
import os
import re
import sys

from fontTools import subset
from fontTools.ttLib import TTFont

ORIGINAL_SHA256 = "ae82f4e2a55e1316a55bcc1d05e9555ce08d8bda07e893b486896b626fd852ff"
OUT = "assets/fonts/fallback/NotoSansSC-Regular.ttf"
OTHER_BUNDLED = "assets/fonts/fallback"
ENGINE_FONTS = "web/fonts"
ARB = "lib/l10n/intl_zh_Hans.arb"
DART_DIRS = ["lib", "core/lib", "model/lib", "scribe/lib", "workplace/lib", "labels/lib"]
RANGES = [(0x20, 0x7E), (0xA0, 0xFF), (0x2000, 0x206F), (0x3000, 0x303F), (0xFE10, 0xFE1F),
          (0xFE30, 0xFE4F), (0xFF00, 0xFFEF)]


def gb2312():
    out = set()
    for b1 in range(0xA1, 0xF8):
        for b2 in range(0xA1, 0xFF):
            try:
                out.add(ord(bytes([b1, b2]).decode("gb2312")))
            except UnicodeDecodeError:
                pass
    return out


def ui_chars():
    arb = json.load(open(ARB, encoding="utf-8"))
    chars = {ord(c) for k, v in arb.items() if not k.startswith("@") and isinstance(v, str) for c in v}
    for d in DART_DIRS:
        for root, _, files in os.walk(d):
            for f in files:
                # messages_*.dart are generated from the .arb files (zh_Hant is not offered by the app)
                if f.endswith(".dart") and not re.match(r"messages_.*\.dart$", f):
                    chars |= {ord(c) for c in open(os.path.join(root, f), encoding="utf-8").read() if ord(c) > 0x7F}
    return chars


def cmap_union(paths):
    out = set()
    for p in paths:
        out |= set(TTFont(p, lazy=True).getBestCmap() or {})
    return out


def drawable_elsewhere():
    """Code points the other bundled fallback fonts / the engine's fallback fonts can draw."""
    bundled = [os.path.join(OTHER_BUNDLED, f) for f in sorted(os.listdir(OTHER_BUNDLED))
               if f.endswith(".ttf") and f != os.path.basename(OUT)]
    engine = [os.path.join(root, f) for root, _, files in os.walk(ENGINE_FONTS) for f in sorted(files)
              if f.endswith(".woff2")]
    if len(engine) < 700:
        sys.exit("%s should hold the engine's 724 fallback fonts (rf4)" % ENGINE_FONTS)
    return cmap_union(bundled), cmap_union(engine), len(bundled) + len(engine)


def main():
    if len(sys.argv) != 2 or not os.path.isfile(ARB):
        sys.exit(__doc__)
    src = sys.argv[1]
    sha = hashlib.sha256(open(src, "rb").read()).hexdigest()
    if sha != ORIGINAL_SHA256:
        sys.exit("%s is not upstream's NotoSansSC-Regular.ttf (sha256 %s)" % (src, sha))
    gb, ui = gb2312(), ui_chars()
    bundled, engine, n_fonts = drawable_elsewhere()
    elsewhere = bundled | engine
    font = TTFont(src, recalcTimestamp=False)
    have = set(font.getBestCmap())
    only_here = have - elsewhere
    wanted = gb | ui | only_here | {c for a, b in RANGES for c in range(a, b + 1)}
    opts = subset.Options()
    opts.layout_features = ["*"]
    opts.name_IDs = ["*"]
    opts.name_languages = ["*"]
    opts.notdef_outline = True
    sub = subset.Subsetter(opts)
    sub.populate(unicodes=wanted & have)
    sub.subset(font)
    font.save(OUT)

    kept = set(TTFont(OUT).getBestCmap())
    lost_ui = sorted(chr(c) for c in ui if c in have and c not in kept)
    lost_gb = [c for c in gb if c in have and c not in kept]
    undrawable = have - kept - elsewhere
    if lost_ui or lost_gb or undrawable:
        sys.exit("subset lost characters: UI %s, GB2312 %d, drawable by no other font %d" % (
            "".join(lost_ui), len(lost_gb), len(undrawable)))
    no_glyph_ui = sorted(chr(c) for c in ui if c not in have and c > 0x2E7F)
    print("%s: %d -> %d bytes, %d -> %d code points (GB2312 %d, UI %d, only this font can draw %d; "
          "%d other fonts read)%s" % (
              OUT, os.path.getsize(src), os.path.getsize(OUT), len(have), len(kept), len(gb), len(ui),
              len(only_here), n_fonts,
              "; not in upstream's font either: " + "".join(no_glyph_ui) if no_glyph_ui else ""))
    left = have - kept
    print("left to other fonts: %d code points: %d drawn at once by another bundled font, %d only by an "
          "engine font (drawn once its file is loaded)" % (len(left), len(left & bundled), len(left - bundled)))
    print("sha256", hashlib.sha256(open(OUT, "rb").read()).hexdigest())


if __name__ == "__main__":
    main()
