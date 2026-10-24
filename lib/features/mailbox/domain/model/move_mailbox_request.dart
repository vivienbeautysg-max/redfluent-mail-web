
import 'package:equatable/equatable.dart';
import 'package:jmap_dart_client/jmap/mail/mailbox/mailbox.dart';
import 'package:tmail_ui_user/features/email/domain/model/move_action.dart';

class MoveMailboxRequest with EquatableMixin {

  final MailboxId? destinationMailboxId;
  final String? destinationMailboxDisplayName;
  final MailboxId? parentId;
  final MailboxId mailboxId;
  final MoveAction moveAction;
  /// Redfluent (rf17): the folder's sortOrder under its new parent, written
  /// with the move: 0 when it is moved (no place among its new neighbours
  /// yet), its old value when the move is undone.
  final int sortOrder;
  /// Redfluent (rf17): the folder's sortOrder before the move, handed back in
  /// MoveMailboxSuccess so that Undo puts the folder back in its place.
  final int previousSortOrder;

  MoveMailboxRequest(
    this.mailboxId,
    this.moveAction,
    {
      this.parentId,
      this.destinationMailboxId,
      this.destinationMailboxDisplayName,
      this.sortOrder = 0,
      this.previousSortOrder = 0,
    }
  );

  @override
  List<Object?> get props => [
    mailboxId,
    moveAction,
    parentId,
    destinationMailboxId,
    destinationMailboxDisplayName,
    sortOrder,
    previousSortOrder,
  ];
}