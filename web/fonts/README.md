# web/fonts — the web engine's fallback fonts, served from this site

Redfluent Mail v0.39.3-rf4.

When a text contains characters that none of the app's fonts can draw (Chinese in the design-system
font, emoji, other scripts), the Flutter web engine downloads a matching Noto font slice from
`<fontFallbackBaseUrl><path>`. The `<path>`s come from the engine's fallback table
(`font_fallback_data.dart`, compiled into `main.dart.js`); the default base is
`https://fonts.gstatic.com/s/`.

Upstream Twake Mail sets `fontFallbackBaseUrl: ''` (no Google). The engine then requests the paths
from the site root, where they do not exist, so such text showed boxes. `web/index.html` now sets
`fontFallbackBaseUrl: 'fonts/'` and this directory holds the files:

- **What**: every path of the Flutter 3.38.9 engine's fallback table — 724 woff2 files, 144 Noto
  families, 21,739,792 bytes. Each file is byte-identical to `https://fonts.gstatic.com/s/<path>`
  (downloaded once on 2026-10-09); `SHA256SUMS` lists them. A browser only downloads the slices it
  needs for the characters on screen.
- **Not included**: `roboto/v32/...` (the engine's default font). The engine fetches it only when the
  app bundles no `Roboto` family; this app bundles one (`pubspec.yaml`).
- **Licence**: SIL Open Font License 1.1. `<family>/OFL.txt` is the licence file of each family from
  https://github.com/google/fonts (commit `2eb0b48d5f760f62e286216f0859a8c540dbc1bd`), with that
  family's copyright line.
- **Regenerate** (after a Flutter upgrade the table can change): build, then
  `python3 scripts/mirror_fallback_fonts.py manifest build/web/main.dart.js /tmp/f.json`,
  `... fetch /tmp/f.json web/fonts`, `... licenses /tmp/f.json web/fonts <google/fonts commit>`,
  `... verify /tmp/f.json web/fonts`.
