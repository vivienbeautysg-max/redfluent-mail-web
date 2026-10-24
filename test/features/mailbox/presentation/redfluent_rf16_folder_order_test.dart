import 'dart:convert';

import 'package:core/presentation/resources/image_paths.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:jmap_dart_client/http/http_client.dart';
import 'package:jmap_dart_client/jmap/account_id.dart';
import 'package:jmap_dart_client/jmap/core/id.dart';
import 'package:jmap_dart_client/jmap/core/state.dart' as jmap;
import 'package:jmap_dart_client/jmap/mail/mailbox/mailbox.dart';
import 'package:jmap_dart_client/jmap/mail/mailbox/namespace.dart';
import 'package:model/mailbox/presentation_mailbox.dart';
import 'package:tmail_ui_user/features/mailbox/data/network/mailbox_api.dart';
import 'package:tmail_ui_user/features/mailbox/presentation/model/mailbox_actions.dart';
import 'package:tmail_ui_user/features/mailbox/presentation/model/mailbox_collection.dart';
import 'package:tmail_ui_user/features/mailbox/presentation/model/mailbox_tree.dart';
import 'package:tmail_ui_user/features/mailbox/presentation/model/mailbox_tree_builder.dart';
import 'package:tmail_ui_user/features/mailbox/presentation/utils/folder_order_utils.dart';
import 'package:tmail_ui_user/features/mailbox/presentation/widgets/folder_order_dialog.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations_delegate.dart';
import 'package:tmail_ui_user/main/localizations/localization_service.dart';
import 'package:uuid/uuid.dart';

import '../../../fixtures/session_fixtures.dart';

PresentationMailbox _folder(String id, String role, String name, [int? sortOrder]) {
  return PresentationMailbox(
    MailboxId(Id(id)),
    name: MailboxName(name),
    role: Role(role),
    sortOrder: sortOrder == null ? null : SortOrder(sortValue: sortOrder),
  );
}

// The five system folders exactly as Stalwart reported them for a real account
// (Mailbox/get, 2026-10-24): every sortOrder is 0, Junk Mail listed first.
List<PresentationMailbox> _stalwartFolders() => [
      _folder('c', 'junk', 'Junk Mail', 0),
      _folder('d', 'drafts', 'Drafts', 0),
      _folder('a', 'inbox', 'Inbox', 0),
      _folder('e', 'trash', 'Deleted Items', 0),
      _folder('b', 'sent', 'Sent Items', 0),
    ];

List<String?> _roles(MailboxTree tree) =>
    tree.root.childrenItems!.map((node) => node.item.role?.value).toList();

List<String?> _rolesOf(List<PresentationMailbox> folders) =>
    folders.map((folder) => folder.role?.value).toList();

Future<MailboxTree> _defaultTree(List<PresentationMailbox> mailboxes) async {
  final collection = await TreeBuilder().generateMailboxTreeInUI(
    allMailboxes: mailboxes,
    currentCollection: MailboxCollection.empty(),
  );
  return collection.defaultTree;
}

void main() {
  group('rf16 default order of the system folders:', () {
    test('equal sortOrders (Stalwart reports 0) give Inbox, Drafts, Sent, Trash, Junk', () async {
      expect(_roles(await _defaultTree(_stalwartFolders())), ['inbox', 'drafts', 'sent', 'trash', 'junk']);
    });

    test('the order does not depend on the order the server lists the folders in', () async {
      final folders = _stalwartFolders();
      for (var shift = 0; shift < folders.length; shift++) {
        final rotated = [...folders.skip(shift), ...folders.take(shift)];
        expect(_roles(await _defaultTree(rotated)), ['inbox', 'drafts', 'sent', 'trash', 'junk']);
        expect(_roles(await _defaultTree(rotated.reversed.toList())), ['inbox', 'drafts', 'sent', 'trash', 'junk']);
      }
    });

    test('a missing sortOrder counts as 0 (the JMAP default)', () async {
      final folders = [
        _folder('c', 'junk', 'Junk Mail'),
        _folder('a', 'inbox', 'Inbox', 0),
        _folder('b', 'sent', 'Sent Items'),
      ];
      expect(_roles(await _defaultTree(folders)), ['inbox', 'sent', 'junk']);
    });

    test('a sortOrder the user saved wins over the default order', () async {
      final folders = [
        _folder('a', 'inbox', 'Inbox', 20),
        _folder('b', 'sent', 'Sent Items', 30),
        _folder('c', 'junk', 'Junk Mail', 10),
        _folder('d', 'drafts', 'Drafts', 50),
        _folder('e', 'trash', 'Deleted Items', 40),
      ];
      expect(_roles(await _defaultTree(folders)), ['junk', 'inbox', 'sent', 'trash', 'drafts']);
    });

    test('a folder still at 0 (created after the user placed the others) comes after them', () async {
      final folders = [
        _folder('a', 'inbox', 'Inbox', 20),
        _folder('n', 'archive', 'Archive', 0),
        _folder('c', 'junk', 'Junk Mail', 10),
        _folder('d', 'drafts', 'Drafts', 0),
        _folder('b', 'sent', 'Sent Items', 30),
      ];
      expect(_roles(await _defaultTree(folders)), ['junk', 'inbox', 'sent', 'drafts', 'archive']);
    });

    test('the same rule applies when the tree is rebuilt after a change', () async {
      final collection = await TreeBuilder().generateMailboxTreeInUIAfterRefreshChanges(
        allMailboxes: _stalwartFolders(),
        currentCollection: MailboxCollection.empty(),
      );
      expect(_roles(collection.defaultTree), ['inbox', 'drafts', 'sent', 'trash', 'junk']);
    });
  });

  group('rf16 sortOrder written for a new order:', () {
    test('a custom order is written as 10, 20, 30, ...', () {
      final folders = _stalwartFolders();
      final inbox = folders[2], drafts = folders[1], sent = folders[4], trash = folders[3], junk = folders[0];
      final patches = FolderOrderUtils.sortOrderPatches([inbox, sent, drafts, junk, trash]);
      expect(patches, {
        inbox.id: 10,
        sent.id: 20,
        drafts.id: 30,
        junk.id: 40,
        trash.id: 50,
      });
    });

    test('every folder is written, also one whose value looks unchanged (another device may have changed it)', () {
      final folders = [
        _folder('c', 'junk', 'Junk Mail', 10),
        _folder('a', 'inbox', 'Inbox', 20),
        _folder('b', 'sent', 'Sent Items', 30),
      ];
      // Inbox and Sent swap places, Junk Mail stays first at 10.
      final patches = FolderOrderUtils.sortOrderPatches([folders[0], folders[2], folders[1]]);
      expect(patches, {folders[0].id: 10, folders[2].id: 20, folders[1].id: 30});
    });

    test('an unchanged order is recognised (the controller then sends nothing)', () {
      final folders = _stalwartFolders();
      expect(FolderOrderUtils.isSameOrder(folders, List.of(folders)), isTrue);
      expect(FolderOrderUtils.isSameOrder(folders, folders.reversed.toList()), isFalse);
      expect(FolderOrderUtils.isSameOrder(folders, folders.sublist(1)), isFalse);
    });

    test('the default order is written as 0, so a reset leaves nothing behind', () {
      final custom = [
        _folder('c', 'junk', 'Junk Mail', 10),
        _folder('a', 'inbox', 'Inbox', 20),
        _folder('b', 'sent', 'Sent Items', 30),
      ];
      final reset = FolderOrderUtils.defaultOrder(custom);
      expect(_rolesOf(reset), ['inbox', 'sent', 'junk']);
      expect(FolderOrderUtils.isDefaultOrder(reset), isTrue);
      expect(FolderOrderUtils.sortOrderPatches(reset), {
        custom[1].id: 0,
        custom[2].id: 0,
        custom[0].id: 0,
      });
    });
  });

  group('rf16 "Reorder folders" in the sidebar menu:', () {
    test('offered on the top-level system folders, Starred included', () {
      expect(FolderOrderUtils.canReorderFrom(_folder('a', 'inbox', 'Inbox', 0)), isTrue);
      expect(FolderOrderUtils.canReorderFrom(_folder('c', 'junk', 'Junk Mail', 0)), isTrue);
      expect(FolderOrderUtils.canReorderFrom(PresentationMailbox.favoriteFolder), isTrue);
    });

    test('not offered on personal folders, subfolders or team mailboxes', () {
      expect(FolderOrderUtils.canReorderFrom(PresentationMailbox(MailboxId(Id('t')), name: MailboxName('Templates'))), isFalse);
      expect(
        FolderOrderUtils.canReorderFrom(PresentationMailbox(MailboxId(Id('s')),
            name: MailboxName('Work'), role: Role('inbox'), parentId: MailboxId(Id('a')))),
        isFalse,
      );
      expect(
        FolderOrderUtils.canReorderFrom(PresentationMailbox(MailboxId(Id('x')),
            name: MailboxName('Inbox'), role: Role('inbox'), namespace: Namespace('Delegated[team@example.com]'))),
        isFalse,
      );
    });

    test('the menu entry has its own title and icon', () async {
      await AppLocalizations.load(LocalizationService.defaultLocale);
      expect(MailboxActions.reorderFolders.getContextMenuTitle(AppLocalizations()), 'Reorder folders');
      expect(MailboxActions.reorderFolders.getContextMenuIcon(ImagePaths()), 'assets/images/ic_reorder_folders.svg');
    });
  });

  group('rf16 Mailbox/set:', () {
    Future<({jmap.State? newState, Set<Id> notUpdated})> send(
      Map<String, dynamic> setResponse,
      void Function(Object? body) onBody,
    ) {
      final dio = Dio(BaseOptions(method: 'POST'))..options.baseUrl = 'http://domain.com/jmap';
      dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        onBody(options.data);
        handler.next(options);
      }));
      DioAdapter(dio: dio).onPost(
        '',
        (server) => server.reply(200, {
          'sessionState': 'abc',
          'methodResponses': [
            ['Mailbox/set', setResponse, 'c0'],
          ],
        }),
        data: Matchers.any,
      );
      return MailboxAPI(HttpClient(dio), const Uuid()).updateMailboxSortOrders(
        SessionFixtures.aliceSession,
        AccountId(Id('123')),
        {MailboxId(Id('c')): 10, MailboxId(Id('a')): 20},
      );
    }

    test('writes every sortOrder in one Mailbox/set and returns the new state', () async {
      Object? body;
      final result = await send(
        {'accountId': '123', 'oldState': 's1', 'newState': 's2', 'updated': {'c': null, 'a': null}},
        (b) => body = b,
      );
      final request = (body is String ? jsonDecode(body as String) : body) as Map<String, dynamic>;
      final calls = request['methodCalls'] as List;
      expect(calls, hasLength(1));
      expect(calls.single[0], 'Mailbox/set');
      expect(calls.single[1]['accountId'], '123');
      expect(calls.single[1]['update'], {
        'c': {'sortOrder': 10},
        'a': {'sortOrder': 20},
      });
      expect(result.newState, jmap.State('s2'));
      expect(result.notUpdated, isEmpty);
    });

    test('reports the folders the server refused', () async {
      final result = await send(
        {
          'accountId': '123',
          'oldState': 's1',
          'newState': 's2',
          'updated': {'c': null},
          'notUpdated': {
            'a': {'type': 'forbidden'},
          },
        },
        (_) {},
      );
      expect(result.newState, jmap.State('s2'));
      expect(result.notUpdated, {Id('a')});
    });
  });

  group('rf16 reorder dialog:', () {
    late List<PresentationMailbox>? popped;
    late bool closed;

    Future<void> openDialog(
      WidgetTester tester,
      List<PresentationMailbox> folders, {
      Locale locale = LocalizationService.defaultLocale,
    }) async {
      popped = null;
      closed = false;
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: LocalizationService.supportedLocales,
        localeResolutionCallback: LocalizationService.resolveLocale,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  popped = await showDialog<List<PresentationMailbox>>(
                    context: context,
                    builder: (_) => FolderOrderDialog(folders: folders, imagePaths: ImagePaths()),
                  );
                  closed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    List<String> shownNames(WidgetTester tester) {
      const folderNames = {'Inbox', 'Drafts', 'Sent', 'Trash', 'Spam'};
      final texts = tester.widgetList<Text>(
        find.descendant(of: find.byKey(const Key('folder_order_list')), matching: find.byType(Text)),
      );
      return texts.map((text) => text.data!).where(folderNames.contains).toList();
    }

    Future<void> dragHandle(WidgetTester tester, int index, double dy) async {
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(Key('folder_order_handle_$index'))));
      await tester.pump();
      for (var step = 0; step < 10; step++) {
        await gesture.moveBy(Offset(0, dy / 10));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets('lists the folders with their display names, in the given order', (tester) async {
      await openDialog(tester, FolderOrderUtils.defaultOrder(_stalwartFolders()));
      expect(find.text('Reorder folders'), findsOneWidget);
      expect(shownNames(tester), ['Inbox', 'Drafts', 'Sent', 'Trash', 'Spam']);
    });

    testWidgets('dragging Spam to the top and saving pops the new order', (tester) async {
      await openDialog(tester, FolderOrderUtils.defaultOrder(_stalwartFolders()));
      await dragHandle(tester, 4, -4 * 52.0 - 30);
      expect(shownNames(tester), ['Spam', 'Inbox', 'Drafts', 'Sent', 'Trash']);
      await tester.tap(find.byKey(const Key('folder_order_save_button')));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(_rolesOf(popped!), ['junk', 'inbox', 'drafts', 'sent', 'trash']);
    });

    testWidgets('Reset to default is disabled on the default order and restores it after a change', (tester) async {
      await openDialog(tester, FolderOrderUtils.defaultOrder(_stalwartFolders()));
      final reset = find.byKey(const Key('folder_order_reset_button'));
      expect(tester.widget<TextButton>(reset).onPressed, isNull);

      await dragHandle(tester, 0, 2 * 52.0);
      expect(shownNames(tester), ['Drafts', 'Sent', 'Inbox', 'Trash', 'Spam']);
      expect(tester.widget<TextButton>(reset).onPressed, isNotNull);

      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(shownNames(tester), ['Inbox', 'Drafts', 'Sent', 'Trash', 'Spam']);
      await tester.tap(find.byKey(const Key('folder_order_save_button')));
      await tester.pumpAndSettle();
      expect(_rolesOf(popped!), ['inbox', 'drafts', 'sent', 'trash', 'junk']);
    });

    testWidgets('Cancel pops nothing, so nothing is saved', (tester) async {
      await openDialog(tester, FolderOrderUtils.defaultOrder(_stalwartFolders()));
      await dragHandle(tester, 4, -4 * 52.0 - 30);
      await tester.tap(find.byKey(const Key('folder_order_cancel_button')));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(popped, isNull);
    });

    // 1280 x 900 desktop, 320 x 640 small phone, 640 x 320 phone held sideways (the list scrolls, Save stays visible)
    for (final locale in LocalizationService.supportedLocales) {
      testWidgets('no overflow and Save reachable on desktop, small phone and sideways phone in $locale', (tester) async {
        await openDialog(tester, FolderOrderUtils.defaultOrder(_stalwartFolders()), locale: locale);
        for (final size in const [Size(1280, 900), Size(320, 640), Size(640, 320)]) {
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$size');
          final save = find.byKey(const Key('folder_order_save_button'));
          final saveRect = tester.getRect(save);
          expect(saveRect.bottom <= size.height && saveRect.right <= size.width, isTrue, reason: 'Save at $saveRect in $size');
        }
      });
    }
  });

  group('rf16 texts are translated in every language of the picker:', () {
    const expected = {
      'fr_FR': 'Réorganiser les dossiers',
      'en_US': 'Reorder folders',
      'vi_VN': 'Sắp xếp lại thư mục',
      'ru_RU': 'Изменить порядок папок',
      'ar_TN': 'إعادة ترتيب المجلدات',
      'it_IT': 'Riordina le cartelle',
      'de_DE': 'Ordner neu anordnen',
      'mn_MN': 'Хавтасны дарааллыг өөрчлөх',
      'pt_BR': 'Reordenar pastas',
      'zh_Hans': '调整文件夹顺序',
    };

    test('the expectations cover exactly the supported locales', () {
      expect(LocalizationService.supportedLocales.map((l) => l.toString()).toSet(), expected.keys.toSet());
    });

    for (final locale in LocalizationService.supportedLocales) {
      test('$locale', () async {
        await AppLocalizations.load(locale);
        final l10n = AppLocalizations();
        expect(l10n.reorderFolders, expected[locale.toString()]);
        List<String> texts() => [
              AppLocalizations().reorderFoldersHint,
              AppLocalizations().folderOrderSaved,
              AppLocalizations().folderOrderSaveFailed,
            ];
        final translated = texts();
        expect(translated.every((text) => text.isNotEmpty), isTrue);
        if (locale.toString() != 'en_US') {
          await AppLocalizations.load(LocalizationService.defaultLocale);
          final english = texts();
          for (var i = 0; i < english.length; i++) {
            expect(translated[i], isNot(english[i]));
          }
        }
      });
    }

    tearDownAll(() => AppLocalizations.load(LocalizationService.defaultLocale));
  });
}
