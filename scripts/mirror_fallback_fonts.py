#!/usr/bin/env python3
"""Self-host the Flutter web engine's fallback fonts (Redfluent Mail rf4).

The web engine downloads a Noto font slice whenever a text contains characters that none of the
app's own fonts can draw. It fetches '<fontFallbackBaseUrl><path>', where <path> comes from the
engine's fallback table (font_fallback_data.dart, compiled into build/web/main.dart.js) and the
default base is https://fonts.gstatic.com/s/. web/index.html sets the base to 'fonts/', so the same
<path>s must exist under web/fonts/. This script copies them there ONCE (prep time, not build time);
the files are committed. The list of paths is read from a compiled build, never typed by hand.

  python3 scripts/mirror_fallback_fonts.py manifest build/web/main.dart.js /tmp/engine-fonts.json
      every (font name, path) pair of the engine table, plus the default Roboto path
      (only fetched by the engine when the app bundles no 'Roboto' family; this app bundles one).
  python3 scripts/mirror_fallback_fonts.py fetch    /tmp/engine-fonts.json web/fonts
      download every NotoFont path of the table from https://fonts.gstatic.com/s/<path> to
      web/fonts/<path> (files already present are kept if their bytes are woff2), then write
      web/fonts/SHA256SUMS ("sha256  path", sorted).
  python3 scripts/mirror_fallback_fonts.py licenses /tmp/engine-fonts.json web/fonts <google/fonts commit>
      web/fonts/<family>/OFL.txt for every family, from github.com/google/fonts at that commit.
  python3 scripts/mirror_fallback_fonts.py verify   /tmp/engine-fonts.json web/fonts
      exit 1 unless every NotoFont path exists, is woff2, matches SHA256SUMS, every family has an
      OFL.txt, and SHA256SUMS lists nothing else.
"""
import concurrent.futures
import hashlib
import json
import os
import re
import sys
import urllib.request

GSTATIC = "https://fonts.gstatic.com/s/"
OFL_URL = "https://raw.githubusercontent.com/google/fonts/%s/ofl/%s/OFL.txt"
UA = "redfluent-mail-font-mirror/1.0"
PATH_RX = r"[a-z0-9]+/v[0-9]+/[A-Za-z0-9_.-]+\.(?:woff2|ttf|otf)"
ROBOTO = "roboto/v32/KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2"   # canvaskit/fonts.dart _robotoUrl
TABLE_SIZE = 724                                          # font_fallback_data.dart, Flutter 3.38.9


def family(path):
    return path.split("/", 1)[0]


def table(manifest):
    return [r["url"] for r in json.load(open(manifest, encoding="utf-8"))["fonts"] if r["url"] != ROBOTO]


def sha256(b):
    return hashlib.sha256(b).hexdigest()


def http_get(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def cmd_manifest(js, out):
    t = open(js, encoding="utf-8").read()
    pairs = re.findall(r"\"([A-Z][A-Za-z0-9 ]+?)\",\"(" + PATH_RX + r")\"", t)
    paths = re.findall(r"\"(" + PATH_RX + r")\"", t)
    paired = {p for _, p in pairs}
    extra = [p for p in paths if p not in paired]
    if len(pairs) != TABLE_SIZE or len(paired) != TABLE_SIZE or extra != [ROBOTO]:
        sys.exit("unexpected engine table in %s: %d pairs, %d distinct paths, other paths %r"
                 % (js, len(pairs), len(paired), extra))
    rows = [{"name": n, "url": p} for n, p in pairs] + [{"name": "Roboto (engine default)", "url": ROBOTO}]
    with open(out, "w", encoding="utf-8") as f:
        json.dump({"source": js, "count": len(rows), "fonts": rows}, f, indent=1)
    print("%s: %d table paths in %d families + default %s -> %s"
          % (js, len(pairs), len({family(p) for p in paired}), ROBOTO, out))


def cmd_fetch(manifest, dest):
    want = table(manifest)

    def one(path):
        p = os.path.join(dest, path)
        if os.path.exists(p) and open(p, "rb").read(4) == b"wOF2":
            return "kept"
        data = http_get(GSTATIC + path)
        if data[:4] != b"wOF2":
            raise SystemExit("not woff2: %s (%r)" % (path, data[:16]))
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p + ".part", "wb") as f:
            f.write(data)
        os.replace(p + ".part", p)
        return "downloaded"

    with concurrent.futures.ThreadPoolExecutor(8) as ex:
        res = list(ex.map(one, want))
    with open(os.path.join(dest, "SHA256SUMS"), "w", encoding="utf-8") as f:
        for path in sorted(want):
            f.write("%s  %s\n" % (sha256(open(os.path.join(dest, path), "rb").read()), path))
    size = sum(os.path.getsize(os.path.join(dest, p)) for p in want)
    print("%d files (%d downloaded, %d kept), %d families, %d bytes -> %s/SHA256SUMS"
          % (len(want), res.count("downloaded"), res.count("kept"), len({family(p) for p in want}), size, dest))


def cmd_licenses(manifest, dest, commit):
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        sys.exit("give the full google/fonts commit sha")
    fams = sorted({family(p) for p in table(manifest)})

    def one(fam):
        text = http_get(OFL_URL % (commit, fam))
        if b"SIL OPEN FONT LICENSE Version 1.1" not in text:
            raise SystemExit("%s: not an OFL 1.1 text" % fam)
        with open(os.path.join(dest, fam, "OFL.txt"), "wb") as f:
            f.write(text)
        return fam

    with concurrent.futures.ThreadPoolExecutor(8) as ex:
        done = list(ex.map(one, fams))
    print("%d OFL.txt files from google/fonts@%s" % (len(done), commit[:12]))


def cmd_verify(manifest, dest):
    want = sorted(table(manifest))
    sums = {}
    for line in open(os.path.join(dest, "SHA256SUMS"), encoding="utf-8"):
        h, p = line.rstrip("\n").split("  ", 1)
        sums[p] = h
    bad = []
    for path in want:
        p = os.path.join(dest, path)
        if not os.path.isfile(p):
            bad.append("missing " + path)
            continue
        b = open(p, "rb").read()
        if b[:4] != b"wOF2":
            bad.append("not woff2 " + path)
        if sums.get(path) != sha256(b):
            bad.append("sha256 mismatch " + path)
    bad += ["SHA256SUMS lists a path the engine does not use: " + p for p in sorted(set(sums) - set(want))]
    fams = sorted({family(p) for p in want})
    bad += ["no OFL.txt for " + f for f in fams if not os.path.isfile(os.path.join(dest, f, "OFL.txt"))]
    size = sum(os.path.getsize(os.path.join(dest, p)) for p in want if os.path.isfile(os.path.join(dest, p)))
    print("engine table: %d paths, %d families; shipped %d bytes" % (len(want), len(fams), size))
    for b in bad[:25]:
        print("  FAIL", b)
    print("RESULT", "PASS" if not bad else "FAIL (%d)" % len(bad))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    a = sys.argv[1:]
    cmds = {"manifest": (cmd_manifest, 2), "fetch": (cmd_fetch, 2), "licenses": (cmd_licenses, 3), "verify": (cmd_verify, 2)}
    if not a or a[0] not in cmds or len(a) - 1 != cmds[a[0]][1]:
        sys.exit(__doc__)
    cmds[a[0]][0](*a[1:])
