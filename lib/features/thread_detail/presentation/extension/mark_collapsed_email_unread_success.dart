import 'package:dartz/dartz.dart';
import 'package:jmap_dart_client/jmap/mail/email/keyword_identifier.dart';
import 'package:model/email/email_in_thread_status.dart';
import 'package:model/email/read_actions.dart';
import 'package:model/extensions/presentation_email_extension.dart';
import 'package:tmail_ui_user/features/email/domain/state/mark_as_email_read_state.dart';
import 'package:tmail_ui_user/features/mailbox_dashboard/presentation/extensions/update_current_emails_flags_extension.dart';
import 'package:tmail_ui_user/features/thread_detail/presentation/extension/close_thread_detail_action.dart';
import 'package:tmail_ui_user/features/thread_detail/presentation/thread_detail_controller.dart';

extension MarkCollapsedEmailReadSuccess on ThreadDetailController {
  void markCollapsedEmailReadSuccess(MarkAsEmailReadSuccess success) {
    _updateEmailListInMailboxDashboardController(success);
    _updateEmailKeywordInThreadDetailController(success);
    _updateEmailCollapsedStatusInThreadDetailController(success);
  }

  void _updateEmailListInMailboxDashboardController(
    MarkAsEmailReadSuccess success,
  ) {
    mailboxDashBoardController.updateEmailFlagByEmailIds(
      [success.emailId],
      readAction: success.readActions,
    );
    _updateMailboxUnreadCount(success);
  }

  /// MailboxController moves a folder's unread badge when the dashboard's view state carries a
  /// MarkAsEmailReadSuccess. Only the dashboard's own mark-as-read put one there, so reading an email
  /// here left the badge until a push or a reload. A thread email fetched by id has no mailboxContain,
  /// so the folder is looked up from its mailboxIds; without a folder there is nothing to move.
  /// The state is cleared first: reading the same email twice in a row (it was marked unread elsewhere in
  /// between) gives an equal state, which an Rx value would swallow.
  void _updateMailboxUnreadCount(MarkAsEmailReadSuccess success) {
    final mailboxId = success.mailboxId ??
        emailIdsPresentation[success.emailId]
            ?.findMailboxContain(mailboxDashBoardController.mapMailboxById)
            ?.id;
    if (mailboxId == null) return;

    mailboxDashBoardController.clearState();
    mailboxDashBoardController.dispatchState(Right(MarkAsEmailReadSuccess(
      success.emailId,
      success.readActions,
      success.markReadAction,
      mailboxId,
    )));
  }

  void _updateEmailKeywordInThreadDetailController(
    MarkAsEmailReadSuccess success,
  ) {
    if (success.readActions == ReadActions.markAsRead) {
      emailIdsPresentation[success.emailId]
        ?.keywords
        ?[KeyWordIdentifier.emailSeen] = true;
    } else {
      emailIdsPresentation[success.emailId]
        ?.keywords?.remove(KeyWordIdentifier.emailSeen);
    }
  }

  void _updateEmailCollapsedStatusInThreadDetailController(
    MarkAsEmailReadSuccess success,
  ) {
    if (success.readActions == ReadActions.markAsRead) return;
    if (emailIdsPresentation.length == 1) {
      closeThreadDetailAction();
    } else {
      emailIdsPresentation[success.emailId] = emailIdsPresentation
        [success.emailId]
        ?.copyWith(
          emailInThreadStatus: EmailInThreadStatus.collapsed,
        );
    }
  }
}