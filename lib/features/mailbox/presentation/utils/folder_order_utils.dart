import 'package:flutter/foundation.dart';
import 'package:jmap_dart_client/jmap/mail/mailbox/mailbox.dart';
import 'package:model/extensions/presentation_mailbox_extension.dart';
import 'package:model/mailbox/presentation_mailbox.dart';
import 'package:tmail_ui_user/features/mailbox/presentation/model/mailbox_node.dart';
import 'package:tmail_ui_user/features/mailbox/presentation/model/mailbox_tree.dart';
import 'package:tmail_ui_user/features/mailbox/presentation/model/mailbox_tree_builder.dart';

/// Which folders one "Reorder folders" dialog puts in order, and so what its
/// default order is: the top-level system folders (rf16, the usual Inbox,
/// Drafts, Sent, ... order) or the user's own folders that share a parent
/// (rf17, by name).
enum FolderOrderScope { systemFolders, siblingFolders }

/// Redfluent (rf16, rf17): the user's own order of the folders.
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

  /// rf17: every folder of the user's own account that is not a system folder
  /// (a personal folder or a subfolder, at any depth) can be put in order
  /// among the folders next to it. Team mailboxes cannot; Starred and the
  /// other virtual folders have a role, so they count as system folders.
  static bool canReorderSiblingsOf(PresentationMailbox mailbox) {
    return !mailbox.isDefault && mailbox.isPersonal;
  }

  static FolderOrderScope scopeOf(PresentationMailbox mailbox) {
    return canReorderFrom(mailbox) ? FolderOrderScope.systemFolders : FolderOrderScope.siblingFolders;
  }

  /// The folders the dialog opened from [mailbox] lists, in sidebar order: the
  /// top-level system folders, or the folders under the same parent as
  /// [mailbox]. Empty when [mailbox] offers no reordering.
  static List<PresentationMailbox> foldersToReorderWith(
    PresentationMailbox mailbox, {
    required MailboxTree defaultTree,
    required MailboxTree personalTree,
  }) {
    final List<MailboxNode>? nodes;
    if (canReorderFrom(mailbox)) {
      nodes = defaultTree.root.childrenItems;
    } else if (canReorderSiblingsOf(mailbox)) {
      final parentId = mailbox.parentId;
      // Only folders with that same parent: a folder whose parent the sidebar
      // does not show (not subscribed) is listed at the top level, but its
      // place is among its parent's subfolders.
      nodes = (parentId == null
        ? personalTree.root.childrenItems
        : (defaultTree.findNode((node) => node.item.id == parentId)
            ?? personalTree.findNode((node) => node.item.id == parentId))?.childrenItems)
        ?.where((node) => node.item.parentId == parentId)
        .toList();
    } else {
      nodes = null;
    }
    return (nodes ?? <MailboxNode>[])
      .map((node) => node.item)
      .where((folder) => !folder.isVirtualFolder)
      .toList();
  }

  /// [folders] in the order the sidebar shows when nobody reordered them.
  static List<PresentationMailbox> defaultOrder(
    List<PresentationMailbox> folders, {
    FolderOrderScope scope = FolderOrderScope.systemFolders,
  }) {
    return List.of(folders)
      ..sort(scope == FolderOrderScope.systemFolders
        ? TreeBuilder.compareByDefaultFolderOrder
        : TreeBuilder.compareByName);
  }

  static bool isDefaultOrder(
    List<PresentationMailbox> folders, {
    FolderOrderScope scope = FolderOrderScope.systemFolders,
  }) {
    return isSameOrder(folders, defaultOrder(folders, scope: scope));
  }

  static bool isSameOrder(List<PresentationMailbox> a, List<PresentationMailbox> b) {
    return listEquals(
      a.map((folder) => folder.id).toList(),
      b.map((folder) => folder.id).toList(),
    );
  }

  /// rf17: whether the server keeps a place (a sortOrder other than 0) for
  /// any of [folders]. They can be in the default order and still have one,
  /// e.g. after the folder the user had put first was deleted.
  static bool hasStoredOrder(List<PresentationMailbox> folders) {
    return folders.any((folder) => TreeBuilder.sortOrderValueOf(folder) != 0);
  }

  /// rf17: whether saving [ordered] (the dialog opened on [before]) writes
  /// anything: a new order, or the default order while the server still
  /// keeps places for some of them. Those are written as 0, so a folder made
  /// later is sorted in with them again instead of being put after them.
  static bool needsSave(
    List<PresentationMailbox> before,
    List<PresentationMailbox> ordered, {
    FolderOrderScope scope = FolderOrderScope.systemFolders,
  }) {
    if (!isSameOrder(before, ordered)) return true;
    return isDefaultOrder(ordered, scope: scope) && hasStoredOrder(ordered);
  }

  /// The sortOrder to write for each folder so the sidebar shows [ordered] in
  /// this order. Every folder is written, also one whose value looks unchanged:
  /// another device may have changed it since the dialog was opened.
  static Map<MailboxId, int> sortOrderPatches(
    List<PresentationMailbox> ordered, {
    FolderOrderScope scope = FolderOrderScope.systemFolders,
  }) {
    final writeDefault = isDefaultOrder(ordered, scope: scope);
    return {
      for (var index = 0; index < ordered.length; index++)
        ordered[index].id: writeDefault ? 0 : (index + 1) * sortOrderStep,
    };
  }
}
