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
import 'package:jmap_dart_client/jmap/core/session/session.dart';
import 'package:jmap_dart_client/jmap/mail/mailbox/mailbox.dart';
import 'package:jmap_dart_client/jmap/mail/mailbox/mailbox_rights.dart';
import 'package:jmap_dart_client/jmap/mail/mailbox/namespace.dart';
import 'package:model/mailbox/presentation_mailbox.dart';
import 'package:tmail_ui_user/features/email/domain/model/move_action.dart';
import 'package:tmail_ui_user/features/mailbox/data/network/mailbox_api.dart';
import 'package:tmail_ui_user/features/mailbox/domain/model/move_mailbox_request.dart';
import 'package:tmail_ui_user/features/mailbox/domain/repository/mailbox_repository.dart';
import 'package:tmail_ui_user/features/mailbox/domain/state/move_mailbox_state.dart';
import 'package:tmail_ui_user/features/mailbox/domain/usecases/move_mailbox_interactor.dart';
import 'package:tmail_ui_user/features/mailbox/presentation/model/mailbox_collection.dart';
import 'package:tmail_ui_user/features/mailbox/presentation/model/mailbox_node.dart';
import 'package:tmail_ui_user/features/mailbox/presentation/model/mailbox_tree_builder.dart';
import 'package:tmail_ui_user/features/mailbox/presentation/utils/folder_order_utils.dart';
import 'package:tmail_ui_user/features/mailbox/presentation/widgets/folder_order_dialog.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations_delegate.dart';
import 'package:tmail_ui_user/main/localizations/localization_service.dart';
import 'package:uuid/uuid.dart';

import '../../../fixtures/session_fixtures.dart';

PresentationMailbox _system(String id, String role, String name, [int sortOrder = 0]) {
  return PresentationMailbox(
    MailboxId(Id(id)),
    name: MailboxName(name),
    role: Role(role),
    sortOrder: SortOrder(sortValue: sortOrder),
  );
}

/// A folder the user made (no role), as Stalwart reports it: sortOrder 0 unless someone reordered it (2026-10-24, a
/// folder created by JMAP and one created by IMAP on the real engine both came back with 0).
PresentationMailbox _own(String id, String name, {String? parent, int? sortOrder, MailboxRights? rights}) {
  return PresentationMailbox(
    MailboxId(Id(id)),
    name: MailboxName(name),
    parentId: parent == null ? null : MailboxId(Id(parent)),
    sortOrder: sortOrder == null ? null : SortOrder(sortValue: sortOrder),
    myRights: rights,
  );
}

PresentationMailbox _team(String id, String name, {String? parent, int? sortOrder}) {
  return PresentationMailbox(
    MailboxId(Id(id)),
    name: MailboxName(name),
    parentId: parent == null ? null : MailboxId(Id(parent)),
    sortOrder: sortOrder == null ? null : SortOrder(sortValue: sortOrder),
    namespace: Namespace('Delegated[team@example.com]'),
  );
}

// The five system folders as Stalwart reports them (all 0), the personal folders of MAX's sidebar (Outbox, Templates)
// plus a folder with two subfolders, a lone subfolder, and two subfolders of Inbox.
List<PresentationMailbox> _account() => [
      _system('c', 'junk', 'Junk Mail'),
      _system('d', 'drafts', 'Drafts'),
      _system('a', 'inbox', 'Inbox'),
      _system('e', 'trash', 'Deleted Items'),
      _system('b', 'sent', 'Sent Items'),
      _own('f', 'Templates', sortOrder: 0),
      _own('g', 'Outbox', sortOrder: 0),
      _own('h', 'clients', sortOrder: 0),
      _own('j', 'Beta', parent: 'h', sortOrder: 0),
      _own('i', 'Acme', parent: 'h', sortOrder: 0),
      _own('k', 'Old', parent: 'f', sortOrder: 0),
      _own('w', 'Work', parent: 'a', sortOrder: 0),
      _own('v', 'Archive', parent: 'a', sortOrder: 0),
    ];

List<PresentationMailbox> _with(List<PresentationMailbox> folders, Map<String, int> sortOrders) => [
      for (final folder in folders)
        sortOrders.containsKey(folder.id.id.value)
          ? folder.copyWith(sortOrder: SortOrder(sortValue: sortOrders[folder.id.id.value]!))
          : folder,
    ];

Future<MailboxCollection> _build(List<PresentationMailbox> mailboxes) {
  return TreeBuilder().generateMailboxTreeInUI(allMailboxes: mailboxes, currentCollection: MailboxCollection.empty());
}

/// Accepts every move (MoveMailboxInteractor only calls moveMailbox).
class _MovingRepository implements MailboxRepository {
  @override
  Future<bool> moveMailbox(Session session, AccountId accountId, MoveMailboxRequest request) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<String> _names(List<MailboxNode>? nodes) =>(nodes ?? []).map((node) => node.item.name!.name).toList();

List<String> _namesOf(List<PresentationMailbox> folders) => folders.map((folder) => folder.name!.name).toList();

MailboxNode _node(MailboxCollection collection, String id) {
  return (collection.defaultTree.findNode((node) => node.item.id.id.value == id) ??
      collection.personalTree.findNode((node) => node.item.id.id.value == id))!;
}

void main() {
  group('rf17 order of the own folders:', () {
    test('nobody reordered them (all 0): by name ignoring case, as before rf17', () async {
      final collection = await _build(_account());
      expect(_names(collection.personalTree.root.childrenItems), ['clients', 'Outbox', 'Templates']);
      expect(_names(_node(collection, 'h').childrenItems), ['Acme', 'Beta']);
      expect(_names(_node(collection, 'a').childrenItems), ['Archive', 'Work']);
    });

    test('a missing sortOrder counts as 0', () async {
      final collection = await _build([_own('t', 'Templates'), _own('o', 'Outbox'), _own('c', 'clients', sortOrder: 0)]);
      expect(_names(collection.personalTree.root.childrenItems), ['clients', 'Outbox', 'Templates']);
    });

    test('the order the user saved wins over the name, at every level', () async {
      final collection = await _build(_with(_account(), {'f': 10, 'h': 20, 'g': 30, 'j': 10, 'i': 20, 'w': 10, 'v': 20}));
      expect(_names(collection.personalTree.root.childrenItems), ['Templates', 'clients', 'Outbox']);
      expect(_names(_node(collection, 'h').childrenItems), ['Beta', 'Acme']);
      expect(_names(_node(collection, 'a').childrenItems), ['Work', 'Archive']);
    });

    test('a folder still at 0 (made after the user placed the others) comes after them', () async {
      final collection = await _build([
        ..._with(_account(), {'f': 10, 'g': 20, 'h': 30}),
        _own('z', 'Aardvark', sortOrder: 0),
      ]);
      expect(_names(collection.personalTree.root.childrenItems), ['Templates', 'Outbox', 'clients', 'Aardvark']);
    });

    test('the system folders keep their rf16 order next to own folders', () async {
      final collection = await _build(_with(_account(), {'f': 10, 'h': 20, 'g': 30}));
      expect(collection.defaultTree.root.childrenItems!.map((node) => node.item.role?.value).toList(),
          ['inbox', 'drafts', 'sent', 'trash', 'junk']);
    });

    test('own folders named like system folders (and not deletable) still sort by name, as before rf17', () async {
      final locked = MailboxRights(true, true, true, true, true, true, false, false, true);
      final collection = await _build([_own('t', 'Templates', rights: locked, sortOrder: 0), _own('r', 'Archive', rights: locked)]);
      expect(_names(collection.personalTree.root.childrenItems), ['Archive', 'Templates']);
    });

    test('team mailboxes keep their own sorting (by name), whatever their sortOrder', () async {
      final collection = await _build([
        _team('r', 'team'),
        _team('z', 'Zeta', parent: 'r', sortOrder: 10),
        _team('l', 'Alpha', parent: 'r', sortOrder: 20),
      ]);
      expect(_names(collection.teamMailboxTree.root.childrenItems!.single.childrenItems), ['Alpha', 'Zeta']);
    });

    test('the same rule applies when the tree is rebuilt after a change', () async {
      final collection = await TreeBuilder().generateMailboxTreeInUIAfterRefreshChanges(
        allMailboxes: [..._with(_account(), {'f': 10, 'g': 20}), _own('z', 'Aardvark', sortOrder: 0)],
        currentCollection: MailboxCollection.empty(),
      );
      expect(_names(collection.personalTree.root.childrenItems), ['Templates', 'Outbox', 'Aardvark', 'clients']);
    });

    test('the comparison is a consistent order (antisymmetric, transitive)', () {
      final folders = [
        _own('1', 'b', sortOrder: 0), _own('2', 'A', sortOrder: 0), _own('3', 'c', sortOrder: 10),
        _own('4', 'a', sortOrder: 10), _own('5', 'd', sortOrder: 20), _own('6', 'e'), _own('7', 'B', sortOrder: 20),
      ];
      int sign(int x) => x.sign;
      for (final a in folders) {
        expect(TreeBuilder.compareFoldersByUserOrder(a, a), 0);
        for (final b in folders) {
          expect(sign(TreeBuilder.compareFoldersByUserOrder(a, b)), -sign(TreeBuilder.compareFoldersByUserOrder(b, a)));
          for (final c in folders) {
            if (TreeBuilder.compareFoldersByUserOrder(a, b) <= 0 && TreeBuilder.compareFoldersByUserOrder(b, c) <= 0) {
              expect(TreeBuilder.compareFoldersByUserOrder(a, c) <= 0, isTrue);
            }
          }
        }
      }
    });
  });

  group('rf17 which folders "Reorder folders" lists:', () {
    late MailboxCollection collection;
    List<String> listedFor(PresentationMailbox mailbox) => _namesOf(FolderOrderUtils.foldersToReorderWith(
          mailbox,
          defaultTree: collection.defaultTree,
          personalTree: collection.personalTree,
        ));
    PresentationMailbox item(String id) => _node(collection, id).item;

    setUp(() async => collection = await _build(_account()));

    test('a top-level personal folder: the top-level personal folders, not the system folders', () {
      expect(listedFor(item('f')), ['clients', 'Outbox', 'Templates']);
    });

    test('a subfolder: the folders under the same parent', () {
      expect(listedFor(item('i')), ['Acme', 'Beta']);
      expect(listedFor(item('w')), ['Archive', 'Work']);
    });

    test('a system folder: the top-level system folders (rf16)', () {
      expect(listedFor(item('a')), ['Inbox', 'Drafts', 'Sent Items', 'Deleted Items', 'Junk Mail']);
    });

    test('Starred, which the sidebar shows among the system folders, is not listed', () {
      collection.defaultTree.root.childrenItems!.insert(1, MailboxNode(PresentationMailbox.favoriteFolder));
      expect(listedFor(item('a')), ['Inbox', 'Drafts', 'Sent Items', 'Deleted Items', 'Junk Mail']);
      expect(listedFor(PresentationMailbox.favoriteFolder), ['Inbox', 'Drafts', 'Sent Items', 'Deleted Items', 'Junk Mail']);
    });

    test('a folder alone under its parent lists only itself (the menu then offers nothing)', () {
      expect(listedFor(item('k')), ['Old']);
    });

    test('a folder whose parent is not shown is not listed with the top-level folders', () async {
      // Templates not subscribed: the sidebar shows its subfolder Old at the top level, but Old's place is under Templates
      collection = await _build(_account().where((folder) => folder.id.id.value != 'f').toList());
      expect(_names(collection.personalTree.root.childrenItems), ['clients', 'Old', 'Outbox']);
      expect(listedFor(item('g')), ['clients', 'Outbox']);
      expect(listedFor(item('k')), isEmpty);
    });

    test('team mailboxes and folders of another account list nothing', () {
      expect(listedFor(_team('z', 'Zeta', parent: 'r')), isEmpty);
      expect(FolderOrderUtils.canReorderSiblingsOf(_team('z', 'Zeta', parent: 'r')), isFalse);
    });

    test('own folders at any depth can be reordered with their neighbours; system and virtual folders cannot', () {
      expect(FolderOrderUtils.canReorderSiblingsOf(item('f')), isTrue);
      expect(FolderOrderUtils.canReorderSiblingsOf(item('i')), isTrue);
      expect(FolderOrderUtils.canReorderSiblingsOf(item('w')), isTrue);
      expect(FolderOrderUtils.canReorderSiblingsOf(item('a')), isFalse);
      expect(FolderOrderUtils.canReorderSiblingsOf(PresentationMailbox.favoriteFolder), isFalse);
      expect(FolderOrderUtils.scopeOf(item('a')), FolderOrderScope.systemFolders);
      expect(FolderOrderUtils.scopeOf(item('f')), FolderOrderScope.siblingFolders);
    });
  });

  group('rf17 sortOrder written for own folders:', () {
    test('a custom order is written as 10, 20, 30, ...', () {
      final templates = _own('f', 'Templates'), outbox = _own('g', 'Outbox'), clients = _own('h', 'clients');
      expect(FolderOrderUtils.sortOrderPatches([templates, clients, outbox], scope: FolderOrderScope.siblingFolders),
          {templates.id: 10, clients.id: 20, outbox.id: 30});
    });

    test('the order by name is the default: written as 0, and Reset gives it', () {
      final folders = [_own('f', 'Templates', sortOrder: 10), _own('h', 'clients', sortOrder: 20), _own('g', 'Outbox', sortOrder: 30)];
      final reset = FolderOrderUtils.defaultOrder(folders, scope: FolderOrderScope.siblingFolders);
      expect(_namesOf(reset), ['clients', 'Outbox', 'Templates']);
      expect(FolderOrderUtils.isDefaultOrder(reset, scope: FolderOrderScope.siblingFolders), isTrue);
      expect(FolderOrderUtils.sortOrderPatches(reset, scope: FolderOrderScope.siblingFolders),
          {folders[1].id: 0, folders[2].id: 0, folders[0].id: 0});
    });

    test('own folders default to the name even where the system order would differ', () {
      // mayDelete=false + a system name puts a folder in the system order (Templates before Archive); by name it is after.
      final locked = MailboxRights(true, true, true, true, true, true, false, false, true);
      final folders = [_own('t', 'Templates', rights: locked), _own('r', 'Archive', rights: locked)];
      expect(_namesOf(FolderOrderUtils.defaultOrder(folders)), ['Templates', 'Archive']);
      expect(_namesOf(FolderOrderUtils.defaultOrder(folders, scope: FolderOrderScope.siblingFolders)), ['Archive', 'Templates']);
    });

    test('Save writes nothing when nothing changes, and 0 when the default order still has places stored', () {
      const own = FolderOrderScope.siblingFolders;
      final byName = [_own('h', 'clients'), _own('g', 'Outbox'), _own('f', 'Templates')];
      expect(FolderOrderUtils.hasStoredOrder(byName), isFalse);
      expect(FolderOrderUtils.needsSave(byName, byName, scope: own), isFalse);
      expect(FolderOrderUtils.needsSave(byName, [byName[2], byName[0], byName[1]], scope: own), isTrue);
      // the folder the user had put first was deleted: the other two kept 20 and 30, also the order by name
      final leftOver = [_own('h', 'clients', sortOrder: 20), _own('g', 'Outbox', sortOrder: 30)];
      expect(FolderOrderUtils.hasStoredOrder(leftOver), isTrue);
      expect(FolderOrderUtils.needsSave(leftOver, leftOver, scope: own), isTrue);
      expect(FolderOrderUtils.sortOrderPatches(leftOver, scope: own), {leftOver[0].id: 0, leftOver[1].id: 0});
      // an order of the user's own, saved as it is: nothing to write
      final custom = [_own('f', 'Templates', sortOrder: 10), _own('h', 'clients', sortOrder: 20)];
      expect(FolderOrderUtils.needsSave(custom, custom, scope: own), isFalse);
      // the same for the system folders (rf16)
      final system = [_system('a', 'inbox', 'Inbox', 10), _system('d', 'drafts', 'Drafts', 20)];
      expect(FolderOrderUtils.needsSave(system, system), isTrue);
      expect(FolderOrderUtils.needsSave([system[0].copyWith(sortOrder: SortOrder(sortValue: 0))], [system[0].copyWith(sortOrder: SortOrder(sortValue: 0))]), isFalse);
    });
  });

  group('rf17 moving a folder:', () {
    Future<Map<String, dynamic>> moveBody(MoveMailboxRequest request) async {
      Object? body;
      final dio = Dio(BaseOptions(method: 'POST'))..options.baseUrl = 'http://domain.com/jmap';
      dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        body = options.data;
        handler.next(options);
      }));
      DioAdapter(dio: dio).onPost(
        '',
        (server) => server.reply(200, {
          'sessionState': 'abc',
          'methodResponses': [
            ['Mailbox/set', {'accountId': '123', 'oldState': 's1', 'newState': 's2', 'updated': {'k': null}}, 'c0'],
          ],
        }),
        data: Matchers.any,
      );
      final moved = await MailboxAPI(HttpClient(dio), const Uuid())
          .moveMailbox(SessionFixtures.aliceSession, AccountId(Id('123')), request);
      expect(moved, isTrue);
      final sent = (body is String ? jsonDecode(body as String) : body) as Map<String, dynamic>;
      final calls = sent['methodCalls'] as List;
      expect(calls.single[0], 'Mailbox/set');
      return (calls.single[1]['update'] as Map<String, dynamic>);
    }

    test('writes sortOrder 0 with the new parent, so the folder keeps no place from its old parent', () async {
      expect(
        await moveBody(MoveMailboxRequest(MailboxId(Id('k')), MoveAction.moving,
            parentId: MailboxId(Id('f')), destinationMailboxId: MailboxId(Id('h')))),
        {'k': {'parentId': 'h', 'sortOrder': 0}},
      );
    });

    test('also when it is moved to the top level', () async {
      expect(
        await moveBody(MoveMailboxRequest(MailboxId(Id('k')), MoveAction.moving, parentId: MailboxId(Id('f')))),
        {'k': {'parentId': null, 'sortOrder': 0}},
      );
    });

    test('Undo writes the old place back with the old parent', () async {
      expect(
        await moveBody(MoveMailboxRequest(MailboxId(Id('k')), MoveAction.undo,
            parentId: MailboxId(Id('h')), destinationMailboxId: MailboxId(Id('f')), sortOrder: 20)),
        {'k': {'parentId': 'f', 'sortOrder': 20}},
      );
    });

    test('the place before the move is handed on to Undo', () async {
      final result = await MoveMailboxInteractor(_MovingRepository())
          .execute(SessionFixtures.aliceSession, AccountId(Id('123')), MoveMailboxRequest(MailboxId(Id('k')),
              MoveAction.moving, parentId: MailboxId(Id('f')), destinationMailboxId: MailboxId(Id('h')), previousSortOrder: 20))
          .last;
      final success = result.fold((failure) => null, (success) => success);
      expect(success, isA<MoveMailboxSuccess>());
      expect((success as MoveMailboxSuccess).previousSortOrder, 20);
      expect(success.parentId, MailboxId(Id('f')));
    });
  });

  group('rf17 reorder dialog for own folders:', () {
    late List<PresentationMailbox>? popped;

    Future<void> openDialog(WidgetTester tester, List<PresentationMailbox> folders,
        {Locale locale = LocalizationService.defaultLocale}) async {
      popped = null;
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
                    builder: (_) => FolderOrderDialog(
                      folders: folders,
                      imagePaths: ImagePaths(),
                      scope: FolderOrderScope.siblingFolders,
                    ),
                  );
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
      const folderNames = {'clients', 'Outbox', 'Templates'};
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

    List<PresentationMailbox> byName() => [_own('h', 'clients'), _own('g', 'Outbox'), _own('f', 'Templates')];

    testWidgets('explains that Reset sorts by name (not the Starred hint of the system folders)', (tester) async {
      await openDialog(tester, byName());
      expect(find.textContaining('Reset to default sorts them by name.'), findsOneWidget);
      expect(find.textContaining('Starred always comes right after Inbox.'), findsNothing);
      expect(shownNames(tester), ['clients', 'Outbox', 'Templates']);
    });

    testWidgets('Reset is disabled on the order by name, restores it after a drag, Save pops the order', (tester) async {
      await openDialog(tester, byName());
      final reset = find.byKey(const Key('folder_order_reset_button'));
      expect(tester.widget<TextButton>(reset).onPressed, isNull);

      await dragHandle(tester, 2, -2 * 52.0 - 30);
      expect(shownNames(tester), ['Templates', 'clients', 'Outbox']);
      expect(tester.widget<TextButton>(reset).onPressed, isNotNull);

      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(shownNames(tester), ['clients', 'Outbox', 'Templates']);

      await dragHandle(tester, 2, -2 * 52.0 - 30);
      await tester.tap(find.byKey(const Key('folder_order_save_button')));
      await tester.pumpAndSettle();
      expect(_namesOf(popped!), ['Templates', 'clients', 'Outbox']);
    });

    testWidgets('Reset is offered on the order by name while places are still stored; Save then pops that order', (tester) async {
      // a deleted folder had been put first: the three kept 20, 30, 40, which is also the order by name
      final leftOver = [_own('h', 'clients', sortOrder: 20), _own('g', 'Outbox', sortOrder: 30), _own('f', 'Templates', sortOrder: 40)];
      await openDialog(tester, leftOver);
      final reset = find.byKey(const Key('folder_order_reset_button'));
      expect(tester.widget<TextButton>(reset).onPressed, isNotNull);
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(shownNames(tester), ['clients', 'Outbox', 'Templates']);
      expect(tester.widget<TextButton>(reset).onPressed, isNull, reason: 'nothing more to reset');
      await tester.tap(find.byKey(const Key('folder_order_save_button')));
      await tester.pumpAndSettle();
      expect(_namesOf(popped!), ['clients', 'Outbox', 'Templates']);
      expect(FolderOrderUtils.needsSave(leftOver, popped!, scope: FolderOrderScope.siblingFolders), isTrue);
    });

    testWidgets('Reset sorts by name also where the system order would differ', (tester) async {
      // not deletable + a system name: the system order puts Templates before Archive, the name order after it
      final locked = MailboxRights(true, true, true, true, true, true, false, false, true);
      final templates = _own('t', 'Templates', rights: locked), archive = _own('r', 'Archive', rights: locked);
      await openDialog(tester, [archive, templates]);
      final reset = find.byKey(const Key('folder_order_reset_button'));
      expect(tester.widget<TextButton>(reset).onPressed, isNull, reason: 'Archive, Templates is the order by name');
      await tester.pumpWidget(const SizedBox());
      await openDialog(tester, [templates, archive]);
      await tester.tap(reset);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('folder_order_save_button')));
      await tester.pumpAndSettle();
      expect(_namesOf(popped!), ['Archive', 'Templates']);
    });

    for (final locale in LocalizationService.supportedLocales) {
      testWidgets('no overflow and Save reachable on desktop, small phone and sideways phone in $locale', (tester) async {
        await openDialog(tester, byName(), locale: locale);
        for (final size in const [Size(1280, 900), Size(320, 640), Size(640, 320)]) {
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$size');
          final saveRect = tester.getRect(find.byKey(const Key('folder_order_save_button')));
          expect(saveRect.bottom <= size.height && saveRect.right <= size.width, isTrue, reason: 'Save at $saveRect in $size');
        }
      });
    }
  });

  group('rf17 text is translated in every language of the picker:', () {
    for (final locale in LocalizationService.supportedLocales) {
      test('$locale: names that language\'s own "Reset to default" and is not the English text', () async {
        await AppLocalizations.load(locale);
        final hint = AppLocalizations().reorderFoldersByNameHint;
        expect(hint, contains(AppLocalizations().resetToDefault));
        expect(hint, isNot(AppLocalizations().reorderFoldersHint));
        if (locale.toString() != 'en_US') {
          await AppLocalizations.load(LocalizationService.defaultLocale);
          expect(hint, isNot(AppLocalizations().reorderFoldersByNameHint));
        }
      });
    }

    tearDownAll(() => AppLocalizations.load(LocalizationService.defaultLocale));
  });
}
