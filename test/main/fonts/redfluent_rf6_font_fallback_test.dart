import 'dart:convert';
import 'dart:io';

import 'package:core/presentation/constants/constants_ui.dart';
import 'package:core/presentation/resources/image_paths.dart';
import 'package:core/presentation/utils/theme_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:jmap_dart_client/jmap/core/id.dart';
import 'package:jmap_dart_client/jmap/core/unsigned_int.dart';
import 'package:jmap_dart_client/jmap/mail/mailbox/mailbox.dart';
import 'package:linagora_design_flutter/linagora_design_flutter.dart';
import 'package:model/mailbox/expand_mode.dart';
import 'package:model/mailbox/presentation_mailbox.dart';
import 'package:tmail_ui_user/features/mailbox/presentation/model/mailbox_node.dart';
import 'package:tmail_ui_user/features/mailbox/presentation/widgets/sidebar/sidebar_mailbox_item.dart';
import 'package:tmail_ui_user/features/mailbox_dashboard/presentation/widgets/compose_button_widget.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations_delegate.dart';
import 'package:tmail_ui_user/main/localizations/localization_service.dart';

/// Redfluent Mail v0.39.3-rf6: no "tofu" (boxes) before Chinese appears.
///
/// The sidebar is drawn by the design system (package linagora_design_flutter), whose text styles
/// name TwakeInter with `package:` and no `fontFamilyFallback`. Flutter rewrites a packaged style's
/// fallback entries to `packages/<package>/<family>` (painting/text_style.dart, `fontFamilyFallback`
/// getter), so those texts had only TwakeInter: on the web, Chinese then waited for the engine's
/// glyph fallback (download a Noto slice from fonts/, re-layout) and showed boxes meanwhile.
/// rf6 gives every design-system style the app's bundled fallback chain
/// (ConstantsUI.webFontFamilyFallback, NotoSansSC before NotoSansKR), set by ThemeUtils.buildAppTheme.
/// rf7: the chain is checked against the bundled families, the NotoSansSC subset against the whole of
/// GB2312, and a late fallback change only throws in debug/profile builds. Every test sets up what it
/// needs, so each one also passes when run alone.
void main() {
  group('rf6: design-system text styles carry the bundled fallback chain', () {
    testWidgets('text theme, theme extension, typography and sidebar styles', _designSystemStyles);
    testWidgets('the app theme built from them', _appTheme);
  });

  group('rf6: the sidebar as the app draws it in Simplified Chinese', () {
    testWidgets('every painted span resolves the bundled chain, never a packages/ fallback', _sidebarSpans);
  });

  group('rf7: the fallback chain names bundled families', () {
    testWidgets('every family of ConstantsUI.webFontFamilyFallback but sans-serif is in FontManifest.json',
        (tester) async {
      final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
      final bundled = {for (final f in manifest) (f as Map<String, dynamic>)['family'] as String};
      final missing = [
        for (final family in ConstantsUI.webFontFamilyFallback)
          if (family != 'sans-serif' && !bundled.contains(family)) family,
      ];
      // ignore: avoid_print
      print('RF7-FAMILIES chain=${ConstantsUI.webFontFamilyFallback.length} notBundled=$missing');
      expect(missing, isEmpty, reason: 'not declared under fonts: in pubspec.yaml, so never drawn');
    });
  });

  group('rf6/rf7: the bundled NotoSansSC subset', () {
    test('maps every zh_Hans UI character and every GB2312 character, and is not upstream\'s 10.5 MB file', () {
      final font = File('assets/fonts/fallback/NotoSansSC-Regular.ttf').readAsBytesSync();
      final cmap = _cmap(font);
      final arb = jsonDecode(File('lib/l10n/intl_zh_Hans.arb').readAsStringSync()) as Map<String, dynamic>;
      final missing = <String>{
        for (final e in arb.entries)
          if (!e.key.startsWith('@') && e.value is String)
            for (final r in (e.value as String).runes)
              if (r >= 0x20 && !cmap.contains(r)) String.fromCharCode(r),
      };
      // GB2312 as Python's gb2312 codec decodes it, one line per GB2312 row (scripts/subset_noto_sans_sc.py).
      final gb2312 = File('test/main/fonts/gb2312.txt').readAsStringSync().runes.where((r) => r != 0x0A).toSet();
      final missingGb2312 = [for (final r in gb2312) if (!cmap.contains(r)) String.fromCharCode(r)];
      // ignore: avoid_print
      print('RF6-SUBSET bytes=${font.length} codePoints=${cmap.length} uiCharsMissing=${missing.length} '
          'gb2312=${gb2312.length} gb2312Missing=${missingGb2312.length}');
      expect(gb2312.length, 7445, reason: 'test/main/fonts/gb2312.txt must hold the whole GB2312 set');
      expect(missing, isEmpty, reason: 'zh_Hans UI characters the bundled NotoSansSC cannot draw');
      expect(missingGb2312, isEmpty, reason: 'GB2312 characters the bundled NotoSansSC cannot draw');
      // rf7: common Traditional characters no other bundled font has (Big5 level 1) are drawn at once.
      expect(cmap.containsAll('妳夠嗎啟'.runes), isTrue, reason: 'rf7 Big5 level-1 characters are gone');
      expect(font.length, lessThan(8 * 1024 * 1024), reason: 'upstream\'s full 10.5 MB NotoSansSC is back');
    });
  });

  group('rf6/rf7: the design system fallback is set once', () {
    testWidgets('same list again: allowed; a different list once the styles are built: StateError (debug, profile)',
        (tester) => _onDesktop(() async {
              await _pumpApp(tester, const SizedBox.shrink()); // builds the styles with the app's list
              expect(LinagoraTextTheme.fontFamilyFallback, ConstantsUI.webFontFamilyFallback);
              LinagoraTextTheme.fontFamilyFallback = List.of(ConstantsUI.webFontFamilyFallback);
              expect(() => LinagoraTextTheme.fontFamilyFallback = const ['Roboto'], throwsStateError);
              expect(() => LinagoraTextTheme.debugSetFontFamilyFallback(const ['Roboto'], releaseMode: false),
                  throwsStateError);
              expect(LinagoraTextTheme.fontFamilyFallback, ConstantsUI.webFontFamilyFallback);
            }));

    testWidgets('release build: logged, never thrown; the styles keep the list they were built with',
        (tester) => _onDesktop(() async {
              await _pumpApp(tester, const SizedBox.shrink());
              final logged = <String>[];
              final originalDebugPrint = debugPrint;
              debugPrint = (String? message, {int? wrapWidth}) => logged.add(message ?? '');
              try {
                LinagoraTextTheme.debugSetFontFamilyFallback(const ['Roboto'], releaseMode: true);
              } finally {
                debugPrint = originalDebugPrint;
              }
              expect(logged.single, contains('must be set before the first design system text style is built'));
              expect(LinagoraTextTheme.fontFamilyFallback, ConstantsUI.webFontFamilyFallback);
              expect(LinagoraTextTheme.material().bodyMedium?.fontFamilyFallback, ConstantsUI.webFontFamilyFallback);
            }));
  });
}

const _designSystemFamily = 'packages/linagora_design_flutter/TwakeInter';

/// Icon fonts (MaterialIcons...) draw private-use code points; they need no fallback.
bool _iconGlyphsOnly(String s) => s.runes.every((r) => (r >= 0xE000 && r <= 0xF8FF) || r >= 0xF0000);

/// Code points mapped by a TrueType/OpenType font (cmap formats 4 and 12).
Set<int> _cmap(Uint8List font) {
  final b = ByteData.sublistView(font);
  int? cmap;
  for (var i = 0; i < b.getUint16(4); i++) {
    final record = 12 + 16 * i;
    if (String.fromCharCodes(font.sublist(record, record + 4)) == 'cmap') cmap = b.getUint32(record + 8);
  }
  final codePoints = <int>{};
  for (var i = 0; i < b.getUint16(cmap! + 2); i++) {
    final sub = cmap + b.getUint32(cmap + 8 + 8 * i);
    final format = b.getUint16(sub);
    if (format == 4) {
      final segX2 = b.getUint16(sub + 6);
      final ends = sub + 14, starts = ends + segX2 + 2, deltas = starts + segX2, offsets = deltas + segX2;
      for (var s = 0; s < segX2; s += 2) {
        final start = b.getUint16(starts + s), end = b.getUint16(ends + s);
        final delta = b.getUint16(deltas + s), rangeOffset = b.getUint16(offsets + s);
        for (var c = start; c <= end && c != 0xFFFF; c++) {
          final g = rangeOffset == 0 ? c : b.getUint16(offsets + s + rangeOffset + 2 * (c - start));
          if (g != 0 && (g + delta) & 0xFFFF != 0) codePoints.add(c);
        }
      }
    } else if (format == 12) {
      for (var g = 0; g < b.getUint32(sub + 12); g++) {
        final o = sub + 16 + 12 * g;
        final start = b.getUint32(o), end = b.getUint32(o + 4), glyph = b.getUint32(o + 8);
        for (var c = start; c <= end; c++) {
          if (glyph + c - start != 0) codePoints.add(c);
        }
      }
    }
  }
  return codePoints;
}

/// Problems of one style: empty when [style] draws TwakeInter first, then exactly the bundled chain.
List<String> _problems(TextStyle? style, {bool requireFamily = true}) {
  if (style == null) return ['missing'];
  final fallback = style.fontFamilyFallback;
  return [
    if (requireFamily && style.fontFamily != _designSystemFamily) 'fontFamily=${style.fontFamily}',
    if (!listEquals(fallback, ConstantsUI.webFontFamilyFallback)) 'fontFamilyFallback=$fallback',
    if (fallback != null && fallback.any((f) => f.startsWith('packages/'))) 'packaged fallback',
  ];
}

void _expectAll(Map<String, TextStyle?> styles, {bool requireFamily = true}) {
  final bad = <String>[
    for (final e in styles.entries)
      if (_problems(e.value, requireFamily: requireFamily).isNotEmpty)
        '${e.key}: ${_problems(e.value, requireFamily: requireFamily).join(', ')}',
  ];
  // ignore: avoid_print
  print('RF6-STYLES checked=${styles.length} without-fallback=${bad.length}');
  expect(bad, isEmpty, reason: '${bad.length} of ${styles.length} styles lack the chain');
}

Future<void> _designSystemStyles(WidgetTester tester) => _onDesktop(() async {
      late BuildContext appContext;
      await _pumpApp(tester, Builder(builder: (context) {
        appContext = context;
        return const SizedBox.shrink();
      }));

      final text = LinagoraTextTheme.material();
      final extension = LinagoraTextThemeExtension.material();
      final typography = LinagoraTypography.material();
      final sidebar = LinagoraSidebarStyle.of(appContext);
      _expectAll({
        'TextTheme.displayLarge': text.displayLarge,
        'TextTheme.displayMedium': text.displayMedium,
        'TextTheme.displaySmall': text.displaySmall,
        'TextTheme.headlineLarge': text.headlineLarge,
        'TextTheme.headlineMedium': text.headlineMedium,
        'TextTheme.headlineSmall': text.headlineSmall,
        'TextTheme.titleLarge': text.titleLarge,
        'TextTheme.titleMedium': text.titleMedium,
        'TextTheme.titleSmall': text.titleSmall,
        'TextTheme.labelLarge': text.labelLarge,
        'TextTheme.labelMedium': text.labelMedium,
        'TextTheme.labelSmall': text.labelSmall,
        'TextTheme.bodyLarge': text.bodyLarge,
        'TextTheme.bodyMedium': text.bodyMedium,
        'TextTheme.bodySmall': text.bodySmall,
        'Extension.titleSemibold': extension.titleSemibold,
        'Extension.titleSmall2': extension.titleSmall2,
        'Extension.bodyLargeBold': extension.bodyLargeBold,
        'Extension.bodyLarge1': extension.bodyLarge1,
        'Extension.bodyLarge2': extension.bodyLarge2,
        'Extension.bodyMedium1': extension.bodyMedium1,
        'Extension.bodyMedium2': extension.bodyMedium2,
        'Extension.bodyMedium3': extension.bodyMedium3,
        'Extension.bodyMedium4': extension.bodyMedium4,
        for (final v in LinagoraTypographyVariant.values) 'Typography.${v.name}': typography.resolve(v),
        'SidebarStyle.labelTextStyle': sidebar.labelTextStyle,
        'SidebarStyle.badgeTextStyle': sidebar.badgeTextStyle,
        'SidebarButtonStyles.primaryAction':
            LinagoraSidebarButtonStyles.primaryAction(appContext).textStyle?.resolve(const <WidgetState>{}),
      });
    });

Future<void> _appTheme(WidgetTester tester) => _onDesktop(() async {
      late ThemeData theme;
      await _pumpApp(tester, Builder(builder: (context) {
        theme = Theme.of(context);
        return const SizedBox.shrink();
      }));
      final ext = theme.extension<LinagoraTextThemeExtension>()!;
      Map<String, TextStyle?> slots(String name, TextTheme t) => {
            '$name.displayLarge': t.displayLarge,
            '$name.displayMedium': t.displayMedium,
            '$name.displaySmall': t.displaySmall,
            '$name.headlineLarge': t.headlineLarge,
            '$name.headlineMedium': t.headlineMedium,
            '$name.headlineSmall': t.headlineSmall,
            '$name.titleLarge': t.titleLarge,
            '$name.titleMedium': t.titleMedium,
            '$name.titleSmall': t.titleSmall,
            '$name.labelLarge': t.labelLarge,
            '$name.labelMedium': t.labelMedium,
            '$name.labelSmall': t.labelSmall,
            '$name.bodyLarge': t.bodyLarge,
            '$name.bodyMedium': t.bodyMedium,
            '$name.bodySmall': t.bodySmall,
          };
      _expectAll({
        ...slots('textTheme', theme.textTheme),
        ...slots('primaryTextTheme', theme.primaryTextTheme),
        'extension.titleSemibold': ext.titleSemibold,
        'extension.bodyMedium2': ext.bodyMedium2,
        'ThemeUtils.defaultTextStyleInterFont': ThemeUtils.defaultTextStyleInterFont,
      });
    });

/// Walks every RenderParagraph the sidebar paints and resolves, per text span, the family list the
/// engine receives (a span's null fontFamily / fontFamilyFallback inherits its parent's).
Future<void> _sidebarSpans(WidgetTester tester) => _onDesktop(() async {
      final imagePaths = ImagePaths();
      var id = 0;
      MailboxNode node(String name, {Role? role, int unread = 0, List<MailboxNode>? children}) => MailboxNode(
            PresentationMailbox(
              MailboxId(Id('m${id++}')),
              name: MailboxName(name),
              role: role,
              unreadEmails: UnreadEmails(UnsignedInt(unread)),
              totalEmails: TotalEmails(UnsignedInt(unread)),
            ),
            childrenItems: children,
            expandMode: ExpandMode.COLLAPSE,
          );
      final folders = [
        node('Inbox', role: PresentationMailbox.roleInbox, unread: 3),
        node('Drafts', role: PresentationMailbox.roleDrafts),
        node('Sent', role: PresentationMailbox.roleSent),
        node('Outbox'), // created by name by the app (rf4 shows 发件箱)
        node('Templates'), // created by name by the app (rf4 shows 模板)
        node('Spam', role: PresentationMailbox.roleSpam),
        node('Trash', role: PresentationMailbox.roleTrash),
        node('项目资料', children: [node('二〇二六')]), // a user folder with a sub-folder (expand control)
      ];

      await _pumpApp(
        tester,
        Builder(builder: (context) {
          final l10n = AppLocalizations.of(context);
          return SingleChildScrollView(
            child: SizedBox(
              width: 256,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ComposeButtonWidget(imagePaths: imagePaths, onTapAction: () {}),
                  LinagoraSidebarSectionHeader(
                    label: l10n.folders,
                    expanded: true,
                    onExpandTogglePressed: (_) {},
                    expandToggleLabel: l10n.collapse,
                  ),
                  for (final f in folders)
                    SidebarMailboxItem(mailboxNode: f, imagePaths: imagePaths, isWebDesktop: true),
                  LinagoraSidebarStorage(label: l10n.storageQuotas, progress: 0.3, caption: '3 GB / 10 GB'),
                  LinagoraSidebarVersion(text: '${l10n.version.toLowerCase()} 0.39.3'),
                ],
              ),
            ),
          );
        }),
      );

      final shown = <String>[];
      final bad = <String>[];
      var spans = 0;
      final paragraphs = tester.allRenderObjects.whereType<RenderParagraph>().toList();
      for (final p in paragraphs) {
        void visit(InlineSpan span, String? family, List<String>? fallback) {
          final style = span.style;
          family = style?.fontFamily ?? family;
          fallback = style?.fontFamilyFallback ?? fallback;
          if (span is TextSpan) {
            final t = span.text ?? '';
            if (t.trim().isNotEmpty && !_iconGlyphsOnly(t)) {
              spans++;
              shown.add(t);
              final ok = family == _designSystemFamily &&
                  listEquals(fallback, ConstantsUI.webFontFamilyFallback) &&
                  fallback!.contains('NotoSansSC') &&
                  fallback.indexOf('NotoSansSC') < fallback.indexOf('NotoSansKR');
              if (!ok) bad.add('"$t": family=$family fallback=$fallback');
            }
            for (final c in span.children ?? const <InlineSpan>[]) {
              visit(c, family, fallback);
            }
          }
        }

        visit(p.text, null, null);
      }
      // ignore: avoid_print
      print('RF6-SIDEBAR paragraphs=${paragraphs.length} spans=$spans without-fallback=${bad.length}');
      for (final b in bad) {
        // ignore: avoid_print
        print('  RF6-NO-FALLBACK $b');
      }
      // The scene really is the Chinese sidebar (guards against a test that silently draws nothing).
      for (final s in ['写邮件', '文件夹', '收件箱', '草稿', '已发送邮件', '发件箱', '模板', '已删除邮件', '项目资料']) {
        expect(shown.any((t) => t.contains(s)), isTrue, reason: '"$s" not drawn; drawn: $shown');
      }
      expect(shown.any((t) => t.contains('0.39.3')), isTrue, reason: 'version label not drawn: $shown');
      expect(bad, isEmpty, reason: '${bad.length} of $spans sidebar spans would wait for the engine glyph fallback');
    });

Future<void> _pumpApp(WidgetTester tester, Widget body) async {
  await tester.binding.setSurfaceSize(const Size(1280, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  // As in lib/main.dart: the theme is built from the context above GetMaterialApp.
  await tester.pumpWidget(Builder(
    builder: (context) => GetMaterialApp(
      theme: ThemeUtils.buildAppTheme(context),
      locale: LocalizationService.simplifiedChineseLocale,
      supportedLocales: LocalizationService.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: body),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

// ConstantsUI.fontFamilyFallback is null on mobile and the test binding reports Android; the web app
// gets the list. The override must be undone inside the test body (foundation debug variable).
Future<void> _onDesktop(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}
