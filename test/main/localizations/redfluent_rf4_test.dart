import 'dart:convert';
import 'dart:io';

import 'package:core/presentation/constants/constants_ui.dart';
import 'package:core/presentation/resources/image_paths.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmap_dart_client/jmap/core/id.dart';
import 'package:jmap_dart_client/jmap/mail/email/email_address.dart';
import 'package:jmap_dart_client/jmap/mail/mailbox/mailbox.dart';
import 'package:jmap_dart_client/jmap/mail/mailbox/namespace.dart';
import 'package:model/mailbox/presentation_mailbox.dart';
import 'package:tmail_ui_user/features/base/widget/default_field/default_email_address_drop_down_button.dart';
import 'package:tmail_ui_user/features/composer/presentation/model/header_style_type.dart';
import 'package:tmail_ui_user/features/mailbox/presentation/extensions/presentation_mailbox_extension.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations.dart';
import 'package:tmail_ui_user/main/localizations/localization_service.dart';

/// Redfluent Mail v0.39.3-rf4: complete Chinese, self-hosted engine fallback fonts.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const zhHans = LocalizationService.simplifiedChineseLocale;
  const english = LocalizationService.defaultLocale;

  Map<String, dynamic> arb(String name) =>
      jsonDecode(File('lib/l10n/$name.arb').readAsStringSync()) as Map<String, dynamic>;

  const folderKeys = ['outboxMailboxDisplayName', 'templatesMailboxDisplayName'];
  const rf4Keys = [
    'headerStyleNormal',
    'headerStyleQuote',
    'headerStyleCode',
    'headerStyleHeading',
    'vacationTimeHint',
    'openSourceUnderAgpl',
    'sourceCode',
    'replyToNone',
  ];

  group('zh_Hans catalog:', () {
    test('no key of intl_zh_Hans.arb has an empty value', () {
      final zh = arb('intl_zh_Hans');
      final empty = zh.entries
          .where((e) => !e.key.startsWith('@'))
          .where((e) => e.value is! String || (e.value as String).trim().isEmpty)
          .map((e) => e.key);
      expect(empty, isEmpty);
    });

    test('every message key has a non-empty zh_Hans value, the folder and rf4 keys included', () {
      final keys = arb('intl_messages').keys.where((k) => !k.startsWith('@')).toSet();
      expect(keys, containsAll([...folderKeys, ...rf4Keys]));
      final zh = arb('intl_zh_Hans');
      final missing = keys.where((k) => (zh[k] as String?)?.trim().isNotEmpty != true);
      expect(missing, isEmpty);
    });
  });

  group('The rf4 strings are translated in every language of the picker:', () {
    const expected = <String, List<String>>{
      // normal, quote, code, heading 2, vacation hint, open source, source code, Reply-to "None"
      'en_US': ['Normal', 'Quote', 'Code', 'Header 2', 'hh:min AM/PM', 'Open source under AGPL-3.0', 'Source code', 'None'],
      'zh_Hans': ['正文', '引用', '代码', '标题 2', '上午/下午 时:分', '基于 AGPL-3.0 许可开源', '源代码', '无'],
      'fr_FR': ['Normal', 'Citation', 'Code', 'Titre 2', 'hh:mm', 'Logiciel libre sous licence AGPL-3.0', 'Code source', 'Aucun'],
      'vi_VN': ['Bình thường', 'Trích dẫn', 'Mã', 'Tiêu đề 2', 'hh:mm', 'Mã nguồn mở theo giấy phép AGPL-3.0', 'Mã nguồn', 'Không có'],
      'ru_RU': ['Обычный', 'Цитата', 'Код', 'Заголовок 2', 'чч:мм', 'Открытый исходный код по лицензии AGPL-3.0', 'Исходный код', 'Нет'],
      'ar_TN': ['عادي', 'اقتباس', 'رمز', 'عنوان 2', 'hh:mm ص/م', 'مفتوح المصدر بموجب ترخيص AGPL-3.0', 'الشيفرة المصدرية', 'لا شيء'],
      'it_IT': ['Normale', 'Citazione', 'Codice', 'Titolo 2', 'hh:mm', 'Open source con licenza AGPL-3.0', 'Codice sorgente', 'Nessuno'],
      'de_DE': ['Standard', 'Zitat', 'Code', 'Überschrift 2', 'hh:mm', 'Open Source unter der Lizenz AGPL-3.0', 'Quellcode', 'Keine'],
      'mn_MN': ['Энгийн', 'Ишлэл', 'Код', 'Гарчиг 2', 'hh:mm', 'AGPL-3.0 лицензтэй нээлттэй эх код', 'Эх код', 'Байхгүй'],
      'pt_BR': ['Normal', 'Citação', 'Código', 'Título 2', 'hh:mm', 'Código aberto sob a licença AGPL-3.0', 'Código-fonte', 'Nenhum'],
    };

    test('the expectations cover exactly the supported locales', () {
      expect(
        LocalizationService.supportedLocales.map((l) => l.toString()).toSet(),
        expected.keys.toSet(),
      );
    });

    for (final locale in LocalizationService.supportedLocales) {
      test('$locale', () async {
        await AppLocalizations.load(locale);
        final l10n = AppLocalizations();
        expect([
          l10n.headerStyleNormal,
          l10n.headerStyleQuote,
          l10n.headerStyleCode,
          l10n.headerStyleHeading(2),
          l10n.vacationTimeHint,
          l10n.openSourceUnderAgpl,
          l10n.sourceCode,
          l10n.replyToNone,
        ], expected[locale.toString()]);
        if (locale.languageCode != 'en') {
          expect(l10n.outboxMailboxDisplayName, isNot('Outbox'));
          expect(l10n.templatesMailboxDisplayName, isNot('Templates'));
        }
      });
    }

    test('composer heading styles use the catalog', () async {
      await AppLocalizations.load(zhHans);
      expect(
        HeaderStyleType.values.map((s) => s.getStyleName(AppLocalizations())),
        ['正文', '引用', '代码', '标题 1', '标题 2', '标题 3', '标题 4', '标题 5', '标题 6'],
      );
      await AppLocalizations.load(english);
      expect(
        HeaderStyleType.values.map((s) => s.getStyleName(AppLocalizations())),
        ['Normal', 'Quote', 'Code', 'Header 1', 'Header 2', 'Header 3', 'Header 4', 'Header 5', 'Header 6'],
      );
    });
  });

  group('Folders the app creates by name (no role on this server) show translated names:', () {
    var nextId = 0;
    PresentationMailbox folder(String name, {Role? role, MailboxId? parentId, Namespace? namespace}) =>
        PresentationMailbox(
          MailboxId(Id('m${nextId++}')),
          name: MailboxName(name),
          role: role,
          parentId: parentId,
          namespace: namespace,
        );
    String shown(PresentationMailbox m) => m.getDisplayNameWithoutContext(AppLocalizations());

    test('zh-Hans', () async {
      await AppLocalizations.load(zhHans);
      expect(shown(folder('Outbox')), '发件箱');
      expect(shown(folder('outbox')), '发件箱');
      expect(shown(folder('Templates')), '模板');
      expect(shown(folder('TEMPLATES')), '模板'); // name used by "Save as template" when it creates the folder
      expect(shown(folder('Templates', namespace: Namespace('Personal'))), '模板');
      expect(shown(folder('Inbox', role: PresentationMailbox.roleInbox)), '收件箱');
    });

    test('other folders keep their own name', () async {
      await AppLocalizations.load(zhHans);
      expect(shown(folder('Projects')), 'Projects');
      expect(shown(folder('Outbox 2024')), 'Outbox 2024');
      expect(shown(folder('Templates', parentId: MailboxId(Id('parent')))), 'Templates');
      expect(shown(folder('Outbox', namespace: Namespace('Delegated[team@example.com]'))), 'Outbox');
    });

    test('English UI unchanged', () async {
      await AppLocalizations.load(english);
      expect(shown(folder('Outbox')), 'Outbox');
      expect(shown(folder('TEMPLATES')), 'Templates');
    });
  });

  group('Identity Reply-to drop-down:', () {
    final none = EmailAddress(null, 'None');
    final me = EmailAddress(null, 'me@example.com');
    Widget box(EmailAddress? selected) => MaterialApp(
          home: Scaffold(
            body: DefaultEmailAddressDropDownButton(
              imagePaths: ImagePaths(),
              emailAddresses: [none, me],
              emailAddressSelected: selected,
              onEmailAddressSelected: (_) {},
              isEnabled: false,
              noneEmailAddress: none,
              noneLabel: '无',
            ),
          ),
        );

    testWidgets('the "None" placeholder shows its translated label, real addresses show the address', (tester) async {
      await tester.pumpWidget(box(none));
      expect(find.text('无'), findsOneWidget);
      expect(find.text('None'), findsNothing);
      await tester.pumpWidget(box(me));
      expect(find.text('me@example.com'), findsOneWidget);
    });
  });

  group('Fonts:', () {
    test('NotoSansSC comes before NotoSansKR in the web fallback list', () {
      const list = ConstantsUI.webFontFamilyFallback;
      expect(list.indexOf('NotoSansSC'), greaterThanOrEqualTo(0));
      expect(list.indexOf('NotoSansSC'), lessThan(list.indexOf('NotoSansKR')));
    });

    test('web/index.html loads the engine fallback fonts from web/fonts/, never from Google', () {
      final html = File('web/index.html').readAsStringSync();
      expect(RegExp(r"fontFallbackBaseUrl:\s*'fonts/'").allMatches(html).length, 2);
      expect(RegExp(r"fontFallbackBaseUrl:\s*''").hasMatch(html), isFalse);
      expect(html.contains('gstatic'), isFalse);
      expect(html.contains('googleapis'), isFalse);
    });

    test('every file listed in web/fonts/SHA256SUMS is shipped as woff2, each family with its OFL.txt', () {
      final lines = File('web/fonts/SHA256SUMS').readAsLinesSync().where((l) => l.isNotEmpty).toList();
      expect(lines.length, 724);
      final families = <String>{};
      for (final line in lines) {
        final path = line.split('  ')[1];
        final bytes = File('web/fonts/$path').readAsBytesSync();
        expect(utf8.decode(bytes.sublist(0, 4), allowMalformed: true), 'wOF2', reason: path);
        families.add(path.split('/').first);
      }
      expect(families, containsAll(['notosanssc', 'notosanstc', 'notosanshk', 'notosansjp', 'notosanskr']));
      for (final f in families) {
        expect(File('web/fonts/$f/OFL.txt').readAsStringSync(), contains('SIL OPEN FONT LICENSE Version 1.1'), reason: f);
      }
    });
  });
}
