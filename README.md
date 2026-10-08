# Redfluent Mail — web client

Source code of the webmail served at **https://mail.redfluent.com**.

It is a **modified version of [Twake Mail](https://github.com/linagora/tmail-flutter)
v0.39.3 by LINAGORA**, licensed under the **GNU AGPL-3.0** (see [LICENSE](LICENSE) and
[NOTICE](NOTICE)). This repository is published to meet AGPL-3.0 section 13: every user of
the hosted service can get the complete source of the version they use.

- First commit: the unmodified upstream tree (tag `v0.39.3`, commit `a64d633`).
- Later commits: Redfluent's changes (one per release tag). `git diff $(git rev-list --max-parents=0 HEAD) HEAD` shows all of them.
- The upstream README is kept as [README.upstream.md](README.upstream.md).

## Changes from upstream

Branding (tag `v0.39.3-rf1`), plus the rows marked (rf2) and (rf3). Nothing else.

| Area | Change |
|---|---|
| Product name | "Twake Mail" → "Redfluent Mail" in all UI strings (`lib/main/localizations/app_localizations.dart`, `lib/l10n/intl_*.arb`), page title, PWA manifest, logout page |
| Logo | Redfluent mark + product name (`lib/features/base/widget/application_logo_with_text_widget.dart`), favicon, PWA icons, loading screen |
| Loading screen | Upstream animation and "Twake Workplace" image replaced by the Redfluent mark (`web/index.html`) |
| Mobile banner | The "download the Twake Mail app" banner is removed (`web/index.html`); in rf3 also its text script `web/i18n/` (translater.js + JSON), which failed on every page load once the banner was gone |
| Login page | Upstream marketing column removed; "powered by LINAGORA" artwork replaced by the AGPL-3.0 source link (`lib/features/login/presentation/source_code_link_widget.dart`); privacy link → https://www.redfluent.com/privacy |
| Colour | Primary blue → `#0A66D8` (`core/lib/presentation/extensions/color_extension.dart`) |
| Language (rf2) | Simplified Chinese can be picked in Settings → Language (`lib/main/localizations/localization_service.dart`, `lib/l10n/intl_zh_Hans.arb`) |
| Default language (rf2) | Always English until the user picks a language; the browser / OS language is not used (`LocalizationService.getInitialLocale`, `lib/main.dart`) |
| Change password (rf2) | Web only: a "Change password" entry in the settings menu opens the self-service page `/account/password/` of the same server in the same tab (`lib/features/manage_account/presentation/menu/`) |
| Translations (rf2) | Leftover "Twake" product names in some translations → "Redfluent Mail" (`lib/l10n/intl_*.arb`) |
| Translations (rf3) | "Change password" translated in every language of the language picker: fr, vi, ru, ar, it, de, mn, pt_BR (`lib/l10n/intl_*.arb`) |

## Build

Same as upstream (Flutter 3.38.9, as pinned in the upstream `Dockerfile`):

```bash
bash scripts/prebuild.sh
flutter build web --release --source-maps --no-web-resources-cdn
```

Runtime configuration is upstream's `assets/env.file`; the deployment sets
`SERVER_URL=https://mail.redfluent.com/`.

## Releases

Each GitHub release carries the exact `build/web` tree that is deployed (tarball + SHA-256),
built from the tagged commit.
