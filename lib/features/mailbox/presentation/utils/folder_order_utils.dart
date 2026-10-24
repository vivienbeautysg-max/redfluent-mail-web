import 'package:flutter/foundation.dart';
import 'package:jmap_dart_client/jmap/mail/mailbox/mailbox.dart';
import 'package:model/extensions/presentation_mailbox_extension.dart';
import 'package:model/mailbox/presentation_mailbox.dart';
import 'package:tmail_ui_user/features/mailbox/presentation/model/mailbox_tree_builder.dart';

/// Redfluent (rf16): the user's own order of the system folders.
///
/// The order is stored on the server as each folder's JMAP sortOrder, so it
/// follows the user to every browser and device. Positions are written as
/// 10, 20, 30, ...; an order equal to the default one is written as 0 for
/// every folder, which is what the server reports when nobody reordered them.
class FolderOrderUtils {
  const FolderOrderUtils._();

  static const int sortOrderStep = 10;

  /// The sidebar offers "Reorder folders" on its top-level system folders
  /// (Starred included), not on personal folders, subfolders or team mailboxes.
  static bool canReorderFrom(PresentationMailbox mailbox) {
    return mailbox.isDefault && mailbox.isPersonal && mailbox.parentId == null;
  }

  /// [folders] in the order the sidebar shows when nobody reordered them.
  static List<PresentationMailbox> defaultOrder(List<PresentationMailbox> folders) {
    return List.of(folders)..sort(TreeBuilder.compareByDefaultFolderOrder);
  }

  static bool isDefaultOrder(List<PresentationMailbox> folders) {
    return isSameOrder(folders, defaultOrder(folders));
  }

  static bool isSameOrder(List<PresentationMailbox> a, List<PresentationMailbox> b) {
    return listEquals(
      a.map((folder) => folder.id).toList(),
      b.map((folder) => folder.id).toList(),
    );
  }

  /// The sortOrder to write for each folder so the sidebar shows [ordered] in
  /// this order. Every folder is written, also one whose value looks unchanged:
  /// another device may have changed it since the dialog was opened.
  static Map<MailboxId, int> sortOrderPatches(List<PresentationMailbox> ordered) {
    final writeDefault = isDefaultOrder(ordered);
    return {
      for (var index = 0; index < ordered.length; index++)
        ordered[index].id: writeDefault ? 0 : (index + 1) * sortOrderStep,
    };
  }
}
