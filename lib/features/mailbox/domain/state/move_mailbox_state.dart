import 'package:core/presentation/state/failure.dart';
import 'package:core/presentation/state/success.dart';
import 'package:jmap_dart_client/jmap/mail/mailbox/mailbox.dart';
import 'package:tmail_ui_user/features/email/domain/model/move_action.dart';

class LoadingMoveMailbox extends UIState {}

class MoveMailboxSuccess extends UIState {

  final MailboxId mailboxIdSelected;
  final MoveAction moveAction;
  final MailboxId? parentId;
  final MailboxId? destinationMailboxId;
  final String? destinationMailboxDisplayName;
  /// Redfluent (rf17): MoveMailboxRequest.previousSortOrder, for Undo.
  final int previousSortOrder;

  MoveMailboxSuccess(
    this.mailboxIdSelected,
    this.moveAction,
    {
      this.parentId,
      this.destinationMailboxId,
      this.destinationMailboxDisplayName,
      this.previousSortOrder = 0,
    }
  );

  @override
  List<Object?> get props => [
    mailboxIdSelected,
    moveAction,
    parentId,
    destinationMailboxId,
    destinationMailboxDisplayName,
    previousSortOrder,
  ];
}

class MoveMailboxFailure extends FeatureFailure {

  MoveMailboxFailure(dynamic exception) : super(exception: exception);
}