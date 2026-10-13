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
    outside GB2312 and the UI strings that no other BUNDLED font can draw: with these fonts, 261, 253
    newly kept (the other 8 no font at all draws, so the rule above already kept them). Without it,
    they would wait for an engine font slice and show a box first; the other Big5 level-1 hanzi are
    kept by the rules above or drawn at once by another bundled font (NotoSansKR).
with all OpenType layout features, names and hinting. Any other character is drawn by the next family
of ConstantsUI.webFontFamilyFallback that has it (NotoSansKR), else by the web engine's own fallback,
which loads the matching font slice from web/fonts/ first.

  python3 scripts/subset_noto_sans_sc.py ORIGINAL.ttf
    ORIGINAL.ttf = upstream's file, e.g. in the fork:
      git show v0.39.3:assets/fonts/fallback/NotoSansSC-Regular.ttf > /tmp/NotoSansSC-Regular.ttf
    or in the published repository (first commit = unmodified upstream tree):
      git show $(git rev-list --max-parents=0 HEAD):assets/fonts/fallback/NotoSansSC-Regular.ttf > /tmp/NotoSansSC-Regular.ttf
  Run from the repository root, after scripts/prebuild.sh: the scan of Dart sources below also reads
  the localizations `flutter pub get` generates (workplace/lib/l10n/*.dart, not committed; 6 Vietnamese
  letters are only there) and the committed font was made with them, so the script refuses to run
  when they are missing. Writes, only after checking the result (each file is first written next to its target
  as <name>.new, removed again if anything fails; the font is replaced last):
    test/main/fonts/gb2312.txt          (the GB2312 characters, one line per GB2312 row, from Python's
                                         gb2312 codec)
    test/main/fonts/big5_level1_rf7.txt (the 253 Big5 level-1 characters newly kept by rf7, in Big5
                                         order, one line per Big5 lead byte)
    assets/fonts/fallback/NotoSansSC-Regular.ttf
  test/main/fonts/redfluent_rf6_font_fallback_test.dart checks the font maps every character of both
  lists. Before anything is replaced, the subset must map every wanted character upstream maps
  (including the Latin, punctuation and full-width ranges), give each character it maps upstream's
  outline, advances and instructions, keep upstream's hinting tables (prep, fpgm, cvt, gasp) and name
  records 0 (copyright), 13 and 14 (license), and the Big5 list must be exactly what the written font
  implies; it may map a few characters more than wanted (with these inputs fontTools also keeps
  U+220B and U+2245). The layout tables (GSUB, GPOS...) are subset by fontTools and not compared.
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
from fontTools.pens.recordingPen import DecomposingRecordingPen
from fontTools.ttLib import TTFont

ORIGINAL_SHA256 = "ae82f4e2a55e1316a55bcc1d05e9555ce08d8bda07e893b486896b626fd852ff"
OUT = "assets/fonts/fallback/NotoSansSC-Regular.ttf"
GB2312_LIST = "test/main/fonts/gb2312.txt"
BIG5_LIST = "test/main/fonts/big5_level1_rf7.txt"
NAME_IDS = (0, 13, 14)  # copyright, license description, license URL
HINT_TABLES = ("prep", "fpgm", "cvt ", "gasp")
OTHER_BUNDLED = "assets/fonts/fallback"
ENGINE_FONTS = "web/fonts"
ARB = "lib/l10n/intl_zh_Hans.arb"
GENERATED_L10N = "workplace/lib/l10n/workplace_localizations.dart"  # made by flutter pub get
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
    """Big5 level-1 hanzi: 0xA440-0xC67E (5,401 characters), as (lead byte, code point) in Big5 order."""
    out = []
    for b1 in range(0xA4, 0xC7):
        for b2 in list(range(0x40, 0x7F)) + list(range(0xA1, 0xFF)):
            if (b1, b2) > (0xC6, 0x7E):
                continue
            try:
                out.append((b1, ord(bytes([b1, b2]).decode("big5"))))
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


def drawings(path, cps):
    """Code point -> (outline with components resolved, advance and side bearing, vertical ones,
    the glyph's TrueType instructions)."""
    with TTFont(path) as f:
        best, glyphs, glyf = f.getBestCmap(), f.getGlyphSet(), f["glyf"]
        vmtx = f["vmtx"] if "vmtx" in f else None
        out = {}
        for c in cps:
            name = best[c]
            pen = DecomposingRecordingPen(glyphs)
            glyphs[name].draw(pen)
            program = getattr(glyf[name], "program", None)
            out[c] = (pen.value, f["hmtx"][name], vmtx[name] if vmtx is not None else None,
                      program.getBytecode() if program is not None else b"")
        return out


def font_wide(path):
    """Name records 0/13/14 and the font-wide hinting tables, to compare with upstream's."""
    with TTFont(path) as f:
        names = {i: sorted((r.platformID, r.platEncID, r.langID, r.toUnicode())
                           for r in f["name"].names if r.nameID == i) for i in NAME_IDS}
        return names, {t: f.getTableData(t) for t in HINT_TABLES if t in f}


def big5_text(pairs):
    """The Big5 list file: the characters in Big5 order, one line per Big5 lead byte."""
    rows = {}
    for b1, c in pairs:
        rows.setdefault(b1, []).append(chr(c))
    return "".join("".join(r) + "\n" for r in rows.values())


def main():
    if len(sys.argv) != 2 or not os.path.isfile(ARB):
        sys.exit(__doc__)
    src = sys.argv[1]
    sha = hashlib.sha256(read(src, "rb")).hexdigest()
    if sha != ORIGINAL_SHA256:
        sys.exit("%s is not upstream's NotoSansSC-Regular.ttf (sha256 %s)" % (src, sha))
    if not os.path.isfile(GENERATED_L10N):
        sys.exit("%s is missing: run scripts/prebuild.sh first (see the usage above)" % GENERATED_L10N)
    rows, b5_order = gb2312_rows(), big5_level1()
    gb, ui, b5 = {c for r in rows for c in r}, ui_chars(), {c for _, c in b5_order}
    if len(gb) != 7445 or len(b5) != 5401 or len(b5_order) != 5401:
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
    big5_new = big5_box_first - only_here
    # Everything is written next to its target first and checked. The font is replaced last: a run cut
    # short between the renames leaves new lists next to the old font (which the font test checks), never
    # a new font next to old lists. A run that ends with an error removes every .new file it wrote.
    pending = [(GB2312_LIST + ".new", GB2312_LIST), (BIG5_LIST + ".new", BIG5_LIST), (OUT + ".new", OUT)]
    try:
        with TTFont(src, recalcTimestamp=False) as font:
            sub.populate(unicodes=wanted & have)
            sub.subset(font)
            font.save(OUT + ".new")
        with open(GB2312_LIST + ".new", "w", encoding="utf-8", newline="\n") as f:
            f.writelines("".join(map(chr, r)) + "\n" for r in rows)
        with open(BIG5_LIST + ".new", "w", encoding="utf-8", newline="\n") as f:
            f.write(big5_text((b1, c) for b1, c in b5_order if c in big5_new))

        # Check the files actually written before they replace the committed ones.
        kept = cmap(OUT + ".new", lazy=False)
        listed = read(BIG5_LIST + ".new")
        # The list as the written font implies it: Big5 level 1 it maps that only the rf7 rule keeps.
        implied = big5_text((b1, c) for b1, c in b5_order
                            if c in kept and c not in gb and c not in ui and c not in only_here and c not in bundled)
        up, sub_drawn = drawings(src, kept & have), drawings(OUT + ".new", kept & have)
        (up_names, up_hint), (sub_names, sub_hint) = font_wide(src), font_wide(OUT + ".new")
        problems = {
            "UI": sorted(c for c in ui if c in have and c not in kept),
            "GB2312": sorted(c for c in gb if c not in kept),
            "drawable by no other font": sorted(have - kept - elsewhere),
            "Big5 level 1 needing an engine slice": sorted(c for c in b5 & have if c not in kept and c not in bundled),
            "wanted (incl. Latin, punctuation, full-width ranges) but dropped": sorted((wanted & have) - kept),
            "not in upstream's font": sorted(kept - have),
            "outline, advances or instructions differ from upstream":
                sorted(c for c in kept & have if up[c] != sub_drawn[c]),
            "Big5 list and font disagree": sorted({ord(c) for c in listed if c != "\n"}
                                                  ^ {ord(c) for c in implied if c != "\n"}),
        }
        bad = ["%s %d (%s)" % (k, len(v), "".join(map(chr, v[:20]))) for k, v in problems.items() if v]
        if listed != implied and not problems["Big5 list and font disagree"]:
            bad.append("Big5 list not in Big5 order / one line per lead byte")
        names_bad = [str(i) for i in NAME_IDS if not up_names[i] or up_names[i] != sub_names[i]]
        if names_bad:
            bad.append("name records missing or not upstream's: nameID %s" % ", ".join(names_bad))
        if up_hint != sub_hint:
            bad.append("hinting tables differ from upstream: %s" % ", ".join(
                sorted(t.strip() for t in set(up_hint) | set(sub_hint) if up_hint.get(t) != sub_hint.get(t))))
        if bad:
            sys.exit("subset rejected, nothing written: " + "; ".join(bad))
        done = []
        try:
            for new, path in pending:
                os.replace(new, path)
                done.append(path)
        except OSError as e:
            sys.exit("replacing failed after %s (%s): run the script again" % (", ".join(done) or "nothing", e))
    finally:
        for new, _ in pending:
            try:
                if os.path.exists(new):
                    os.remove(new)
            except OSError as e:
                print("could not remove %s: %s" % (new, e), file=sys.stderr)

    no_glyph_ui = sorted(chr(c) for c in ui if c not in have and c > 0x2E7F)
    print("%s: %d -> %d bytes, %d -> %d code points (GB2312 %d, UI %d, only this font can draw %d, "
          "Big5 level 1 outside GB2312 that no other bundled font draws %d, of which newly kept %d; "
          "%d other fonts read)%s" % (
              OUT, os.path.getsize(src), os.path.getsize(OUT), len(have), len(kept), len(gb), len(ui),
              len(only_here), len(big5_box_first), len(big5_new), n_fonts,
              "; not in upstream's font either: " + "".join(no_glyph_ui) if no_glyph_ui else ""))
    left = have - kept
    print("left to other fonts: %d code points: %d drawn at once by another bundled font, %d only by an "
          "engine font (drawn once its file is loaded)" % (len(left), len(left & bundled), len(left - bundled)))
    print("kept beyond the wanted characters:", " ".join("U+%04X" % c for c in sorted(kept - wanted)) or "none")
    print("sha256", hashlib.sha256(read(OUT, "rb")).hexdigest())
    print("%s: %d rows, %d characters; %s: %d lines, %d characters" % (
        GB2312_LIST, len(rows), len(gb), BIG5_LIST, listed.count("\n"), len(big5_new)))


if __name__ == "__main__":
    main()
