import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:jmap_dart_client/jmap/core/id.dart';
import 'package:jmap_dart_client/jmap/mail/email/email.dart';
import 'package:jmap_dart_client/jmap/mail/mailbox/mailbox.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:model/email/presentation_email.dart';
import 'package:model/email/read_actions.dart';
import 'package:model/mailbox/presentation_mailbox.dart';
import 'package:tmail_ui_user/features/email/domain/model/mark_read_action.dart';
import 'package:tmail_ui_user/features/email/domain/state/mark_as_email_read_state.dart';
import 'package:tmail_ui_user/features/mailbox_dashboard/presentation/controller/mailbox_dashboard_controller.dart';
import 'package:tmail_ui_user/features/mailbox_dashboard/presentation/controller/search_controller.dart';
import 'package:tmail_ui_user/features/thread_detail/presentation/extension/mark_collapsed_email_unread_success.dart';
import 'package:tmail_ui_user/features/thread_detail/presentation/thread_detail_controller.dart';

import 'mark_collapsed_email_read_success_test.mocks.dart';

/// Redfluent Mail v0.39.3-rf10: reading an email in the open email / thread view moves the folder's unread
/// badge at once. MailboxController does that when the dashboard's view state carries a MarkAsEmailReadSuccess
/// for the folder (mailbox_controller.dart, `ever(mailboxDashBoardController.viewState ...)`), so the success
/// must reach the dashboard, with the folder filled in.
@GenerateNiceMocks([
  MockSpec<ThreadDetailController>(),
  MockSpec<MailboxDashBoardController>(),
  MockSpec<SearchController>(),
])
void main() {
  late MockThreadDetailController threadDetailController;
  late MockMailboxDashBoardController dashboard;
  late MockSearchController searchController;

  final inboxId = MailboxId(Id('inbox'));
  final inbox = PresentationMailbox(inboxId);
  final emailId = EmailId(Id('e1'));

  setUp(() {
    threadDetailController = MockThreadDetailController();
    dashboard = MockMailboxDashBoardController();
    searchController = MockSearchController();
    when(threadDetailController.mailboxDashBoardController).thenReturn(dashboard);
    when(dashboard.searchController).thenReturn(searchController);
    when(searchController.isSearchEmailRunning).thenReturn(false);
    when(dashboard.emailsInCurrentMailbox).thenReturn(<PresentationEmail>[].obs);
    when(dashboard.mapMailboxById).thenReturn({inboxId: inbox});
    when(threadDetailController.emailIdsPresentation)
        .thenReturn(<EmailId, PresentationEmail?>{}.obs);
  });

  MarkAsEmailReadSuccess dispatched() {
    final state = verify(dashboard.dispatchState(captureAny)).captured.single
        as Either<dynamic, dynamic>;
    return state.fold((_) => fail('a failure was dispatched'), (s) => s as MarkAsEmailReadSuccess);
  }

  group('markCollapsedEmailReadSuccess', () {
    test('hands the success to the dashboard, so the mailbox list can move the unread badge', () {
      threadDetailController.markCollapsedEmailReadSuccess(MarkAsEmailReadSuccess(
        emailId,
        ReadActions.markAsRead,
        MarkReadAction.tap,
        inboxId,
      ));

      final success = dispatched();
      expect(success.emailId, emailId);
      expect(success.readActions, ReadActions.markAsRead);
      expect(success.mailboxId, inboxId);
    });

    test('marking unread is handed over the same way (the badge goes up)', () {
      threadDetailController.markCollapsedEmailReadSuccess(MarkAsEmailReadSuccess(
        emailId,
        ReadActions.markAsUnread,
        MarkReadAction.tap,
        inboxId,
      ));

      expect(dispatched().readActions, ReadActions.markAsUnread);
    });

    test('an email fetched by id has no mailboxContain: the folder comes from its mailboxIds', () {
      when(threadDetailController.emailIdsPresentation).thenReturn(
        <EmailId, PresentationEmail?>{
          emailId: PresentationEmail(id: emailId, mailboxIds: {inboxId: true}),
        }.obs,
      );

      threadDetailController.markCollapsedEmailReadSuccess(MarkAsEmailReadSuccess(
        emailId,
        ReadActions.markAsRead,
        MarkReadAction.tap,
        null,
      ));

      expect(dispatched().mailboxId, inboxId);
    });

    test('a folder the success already names is kept', () {
      final otherId = MailboxId(Id('other'));
      when(threadDetailController.emailIdsPresentation).thenReturn(
        <EmailId, PresentationEmail?>{
          emailId: PresentationEmail(id: emailId, mailboxIds: {inboxId: true}),
        }.obs,
      );

      threadDetailController.markCollapsedEmailReadSuccess(MarkAsEmailReadSuccess(
        emailId,
        ReadActions.markAsRead,
        MarkReadAction.tap,
        otherId,
      ));

      expect(dispatched().mailboxId, otherId);
    });

    test('clears the view state first, so reading the same email twice (unread elsewhere in between) is not swallowed', () {
      threadDetailController.markCollapsedEmailReadSuccess(MarkAsEmailReadSuccess(
        emailId,
        ReadActions.markAsRead,
        MarkReadAction.tap,
        inboxId,
      ));

      verifyInOrder([dashboard.clearState(), dashboard.dispatchState(any)]);
    });

    test('no folder known (not on the success, not in the email): nothing is handed over', () {
      threadDetailController.markCollapsedEmailReadSuccess(MarkAsEmailReadSuccess(
        emailId,
        ReadActions.markAsRead,
        MarkReadAction.tap,
        null,
      ));

      verifyNever(dashboard.dispatchState(any));
      verifyNever(dashboard.clearState());
    });

    test('still updates the visible email list as before', () {
      threadDetailController.markCollapsedEmailReadSuccess(MarkAsEmailReadSuccess(
        emailId,
        ReadActions.markAsRead,
        MarkReadAction.tap,
        inboxId,
      ));

      verify(dashboard.updateEmailList(any)).called(1);
    });
  });
}
