import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:jmap_dart_client/jmap/mail/mailbox/mailbox.dart';
import 'package:model/extensions/mailbox_name_extension.dart';
import 'package:model/extensions/presentation_mailbox_extension.dart';
import 'package:model/mailbox/expand_mode.dart';
import 'package:model/mailbox/mailbox_state.dart';
import 'package:model/mailbox/presentation_mailbox.dart';
import 'package:model/mailbox/select_mode.dart';
import 'package:tmail_ui_user/features/mailbox/presentation/model/mailbox_collection.dart';

import 'mailbox_node.dart';
import 'mailbox_tree.dart';

class TreeBuilder {
  Future<MailboxCollection> generateMailboxTreeInUI({
    required List<PresentationMailbox> allMailboxes,
    required MailboxCollection currentCollection,
    MailboxId? mailboxIdSelected,
    MailboxId? mailboxIdExpanded,
  }) async {
    final Map<(String?, MailboxId), MailboxNode> mailboxDictionary = HashMap();

    final newDefaultTree = MailboxTree(MailboxNode.root());
    final newPersonalTree = MailboxTree(MailboxNode.root());
    final newTeamMailboxTree = MailboxTree(MailboxNode.root());
  
    final List<PresentationMailbox> newAllMailboxes = <PresentationMailbox>[];
    final List<MailboxNode> mailboxNodes = <MailboxNode>[];
    final claimedSidebarTreeEntryIds = <Object>{};
    final nodeConnections = _MailboxNodeDisjointSet();
    final nodeLookup = _buildNodeLookup(currentCollection);

    for (var mailbox in allMailboxes) {
      final currentMailboxNode = nodeLookup[_mailboxKey(mailbox)];

      final isDeactivated = mailbox.id == mailboxIdSelected;
      final newMailboxNode = MailboxNode(
        isDeactivated ? mailbox.withMailboxSate(MailboxState.deactivated) : mailbox,
        nodeState: isDeactivated ? MailboxState.deactivated : MailboxState.activated,
        expandMode: currentMailboxNode?.expandMode ?? ExpandMode.COLLAPSE,
        selectMode: currentMailboxNode?.selectMode ?? SelectMode.INACTIVE,
        sidebarTreeEntryId: _claimSidebarTreeEntryId(
          currentMailboxNode,
          claimedSidebarTreeEntryIds,
        ),
      );

      mailboxNodes.add(newMailboxNode);
      mailboxDictionary.putIfAbsent(_mailboxKey(mailbox), () => newMailboxNode);
    }

    for (var index = 0; index < allMailboxes.length; index++) {
      final mailbox = allMailboxes[index];
      final currentNode = mailboxNodes[index];

      _placeNodeInTree(
        mailbox: mailbox,
        currentNode: currentNode,
        mailboxDictionary: mailboxDictionary,
        nodeConnections: nodeConnections,
        defaultTree: newDefaultTree,
        personalTree: newPersonalTree,
        teamMailboxTree: newTeamMailboxTree,
        onBeforeAddToParent: _propagateDeactivationIfNeeded,
      );

      newAllMailboxes.add(currentNode.item);
    }

    _finalizeTrees(newDefaultTree, newPersonalTree, newTeamMailboxTree);

    return MailboxCollection(
      allMailboxes: newAllMailboxes,
      defaultTree: newDefaultTree,
      personalTree: newPersonalTree,
      teamMailboxTree: newTeamMailboxTree,
    );
  }

  Future<MailboxCollection> generateMailboxTreeInUIAfterRefreshChanges({
    required List<PresentationMailbox> allMailboxes,
    required MailboxCollection currentCollection,
  }) async {
    final Map<(String?, MailboxId), MailboxNode> mailboxDictionary = HashMap();

    final newDefaultTree = MailboxTree(MailboxNode.root());
    final newPersonalTree = MailboxTree(MailboxNode.root());
    final newTeamMailboxTree = MailboxTree(MailboxNode.root());
    final List<MailboxNode> mailboxNodes = <MailboxNode>[];
    final claimedSidebarTreeEntryIds = <Object>{};
    final nodeConnections = _MailboxNodeDisjointSet();
    final nodeLookup = _buildNodeLookup(currentCollection);

    for (var mailbox in allMailboxes) {
      final currentMailboxNode = nodeLookup[_mailboxKey(mailbox)];

      final newMailboxNode = MailboxNode(
        mailbox,
        expandMode: currentMailboxNode?.expandMode ?? ExpandMode.COLLAPSE,
        selectMode: currentMailboxNode?.selectMode ?? SelectMode.INACTIVE,
        sidebarTreeEntryId: _claimSidebarTreeEntryId(
          currentMailboxNode,
          claimedSidebarTreeEntryIds,
        ),
      );

      mailboxNodes.add(newMailboxNode);
      mailboxDictionary.putIfAbsent(_mailboxKey(mailbox), () => newMailboxNode);
    }

    for (var index = 0; index < allMailboxes.length; index++) {
      final mailbox = allMailboxes[index];
      final currentNode = mailboxNodes[index];

      _placeNodeInTree(
        mailbox: mailbox,
        currentNode: currentNode,
        mailboxDictionary: mailboxDictionary,
        nodeConnections: nodeConnections,
        defaultTree: newDefaultTree,
        personalTree: newPersonalTree,
        teamMailboxTree: newTeamMailboxTree,
      );
    }

    _finalizeTrees(newDefaultTree, newPersonalTree, newTeamMailboxTree);

    return MailboxCollection(
      allMailboxes: allMailboxes,
      defaultTree: newDefaultTree,
      personalTree: newPersonalTree,
      teamMailboxTree: newTeamMailboxTree,
    );
  }

  void _placeNodeInTree({
    required PresentationMailbox mailbox,
    required MailboxNode currentNode,
    required Map<(String?, MailboxId), MailboxNode> mailboxDictionary,
    required _MailboxNodeDisjointSet nodeConnections,
    required MailboxTree defaultTree,
    required MailboxTree personalTree,
    required MailboxTree teamMailboxTree,
    void Function(MailboxNode parent, MailboxNode child)? onBeforeAddToParent,
  }) {
    final parentId = mailbox.parentId;
    final parentNode = parentId != null ? mailboxDictionary[(mailbox.namespace?.value, parentId)] : null;

    if (parentNode != null &&
        nodeConnections.tryConnect(
          parentNode.sidebarTreeEntryId,
          currentNode.sidebarTreeEntryId,
        )) {
      onBeforeAddToParent?.call(parentNode, currentNode);
      parentNode.addChildNode(currentNode);
    } else {
      final targetTree = _resolveTargetTree(mailbox, defaultTree, personalTree, teamMailboxTree);
      targetTree.root.addChildNode(currentNode);
    }
  }

  void _finalizeTrees(MailboxTree defaultTree, MailboxTree personalTree, MailboxTree teamMailboxTree) {
    sortNodeChildren(defaultTree.root);
    defaultTree.root.childrenItems?.forEach(_sortChildrenByUserOrder);
    _sortChildrenByUserOrder(personalTree.root);
    _applyTeamMailboxSorting(teamMailboxTree.root);
  }

  /// Redfluent (rf17): personal folders and the subfolders of every folder of
  /// the user's own account in the user's order ([compareFoldersByUserOrder]),
  /// by name as before when nobody reordered them. Team mailboxes keep their
  /// own sorting ([_applyTeamMailboxSorting]).
  void _sortChildrenByUserOrder(MailboxNode node) {
    final children = node.childrenItems;
    if (children == null || children.isEmpty) return;
    children.sort((a, b) => compareFoldersByUserOrder(a.item, b.item));
    for (final child in children) {
      _sortChildrenByUserOrder(child);
    }
  }

  void sortNodeChildren(MailboxNode mailboxNode) {
    mailboxNode.childrenItems?.sort((a, b) => compareSystemFolders(a.item, b.item));
  }

  /// Redfluent (rf16): sidebar order of the system folders. Stalwart reports
  /// sortOrder 0 for all of them, so sorting by sortOrder alone left the order
  /// to the server (Spam could come first). Equal sortOrders now fall back to
  /// [compareByDefaultFolderOrder]. A user's own order is saved as sortOrder
  /// 10, 20, 30, ...; a folder still at 0 was never placed by the user (for
  /// example one created later) and comes after the placed ones.
  static int compareSystemFolders(PresentationMailbox a, PresentationMailbox b) {
    final byUserOrder = compareByUserSortOrder(a, b);
    if (byUserOrder != 0) return byUserOrder;
    return compareByDefaultFolderOrder(a, b);
  }

  /// Redfluent (rf17): the user's own folders: sortOrder as for the system
  /// folders, then the name (their order before rf17, when nobody reordered
  /// them).
  static int compareFoldersByUserOrder(PresentationMailbox a, PresentationMailbox b) {
    final byUserOrder = compareByUserSortOrder(a, b);
    if (byUserOrder != 0) return byUserOrder;
    return compareByName(a, b);
  }

  /// The user's order: lower sortOrder first, a folder at 0 (never placed by
  /// the user) after the placed ones; 0 when both have the same sortOrder.
  static int compareByUserSortOrder(PresentationMailbox a, PresentationMailbox b) {
    final aSortOrder = sortOrderValueOf(a);
    final bSortOrder = sortOrderValueOf(b);
    if (aSortOrder == bSortOrder) return 0;
    if (aSortOrder == 0) return 1;
    if (bSortOrder == 0) return -1;
    return aSortOrder.compareTo(bSortOrder);
  }

  /// By name, ignoring case, like [MailboxName.compareAlphabetically].
  static int compareByName(PresentationMailbox a, PresentationMailbox b) {
    return (a.name?.name.toLowerCase() ?? '').compareTo(b.name?.name.toLowerCase() ?? '');
  }

  /// Inbox, Drafts, Outbox, Sent, Trash, Spam, Junk, Templates, Archive, then
  /// any other folder by name.
  static int compareByDefaultFolderOrder(PresentationMailbox a, PresentationMailbox b) {
    final byRole = systemFolderSortIndexOf(a).compareTo(systemFolderSortIndexOf(b));
    if (byRole != 0) return byRole;
    return (a.name?.name.toLowerCase() ?? '').compareTo(b.name?.name.toLowerCase() ?? '');
  }

  /// The JMAP sortOrder, 0 when the server sent none (its RFC 8621 default).
  static int sortOrderValueOf(PresentationMailbox mailbox) {
    return mailbox.sortOrder?.value.value.toInt() ?? 0;
  }

  void sortByMailboxNameNodeChildren(MailboxNode mailboxNode) {
    mailboxNode.childrenItems?.sortByCompare<MailboxName?>(
      (node) => node.item.name,
      (name, other) => name?.compareAlphabetically(other) ?? -1,
    );
  }

  static const Map<String, int> _systemFolderRoleIndex = {
    PresentationMailbox.inboxRole:     0,
    PresentationMailbox.draftsRole:    1,
    PresentationMailbox.outboxRole:    2,
    PresentationMailbox.sentRole:      3,
    PresentationMailbox.trashRole:     4,
    PresentationMailbox.spamRole:      5,
    PresentationMailbox.junkRole:      6,
    PresentationMailbox.templatesRole: 7,
    PresentationMailbox.archiveRole:   8,
  };

  int _systemFolderSortIndex(MailboxNode node) => systemFolderSortIndexOf(node.item);

  static int systemFolderSortIndexOf(PresentationMailbox mailbox) {
    final roleValue = mailbox.role?.value ?? '';
    if (roleValue.isNotEmpty) {
      return _systemFolderRoleIndex[roleValue] ?? _systemFolderRoleIndex.length;
    }
    // No role: mayDelete=false means the server does not allow deletion,
    // which identifies a system folder. Fall back to case-insensitive name
    // matching to determine its canonical sort position.
    if (mailbox.myRights?.mayDelete == false) {
      final nameLower = mailbox.name?.name.toLowerCase() ?? '';
      return _systemFolderRoleIndex[nameLower] ?? _systemFolderRoleIndex.length;
    }
    return _systemFolderRoleIndex.length;
  }

  void _sortWithSystemFoldersFirst(MailboxNode node) {
    final children = node.childrenItems;
    if (children == null || children.isEmpty) return;
    final indexCache = {for (final child in children) child: _systemFolderSortIndex(child)};
    children.sort((a, b) {
      final aIndex = indexCache[a]!;
      final bIndex = indexCache[b]!;
      final aIsSystem = aIndex < _systemFolderRoleIndex.length;
      final bIsSystem = bIndex < _systemFolderRoleIndex.length;
      if (aIsSystem && bIsSystem) return aIndex.compareTo(bIndex);
      if (aIsSystem) return -1;
      if (bIsSystem) return 1;
      return a.item.name?.compareAlphabetically(b.item.name) ?? -1;
    });
  }

  // Traversal strategy by depth:
  //   virtual root (isPersonal=true)  → alphabetical — orders team account roots
  //   team account root (isTeamMailboxes=true, depth=1) → system folders first, then alphabetical
  //   children/grandchildren (hasParentId=true) → alphabetical
  void _applyTeamMailboxSorting(MailboxNode node) {
    final children = node.childrenItems;
    if (children == null || children.isEmpty) return;
    if (node.item.isTeamMailboxes) {
      _sortWithSystemFoldersFirst(node);
    } else {
      sortByMailboxNameNodeChildren(node);
    }
    for (final child in children) {
      _applyTeamMailboxSorting(child);
    }
  }

  // Flattens all three trees into a single O(1) lookup map.
  // Avoids repeated O(n) DFS calls when resolving existing nodes for each mailbox.
  Map<(String?, MailboxId), MailboxNode> _buildNodeLookup(MailboxCollection collection) {
    final lookup = HashMap<(String?, MailboxId), MailboxNode>();
    final stack = <MailboxNode>[
      ...?collection.defaultTree.root.childrenItems,
      ...?collection.personalTree.root.childrenItems,
      ...?collection.teamMailboxTree.root.childrenItems,
    ];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      lookup[_mailboxKey(node.item)] = node;
      final children = node.childrenItems;
      if (children != null) stack.addAll(children);
    }
    return lookup;
  }

  (String?, MailboxId) _mailboxKey(PresentationMailbox mailbox) =>
      (mailbox.namespace?.value, mailbox.id);

  Object? _claimSidebarTreeEntryId(
    MailboxNode? currentMailboxNode,
    Set<Object> claimedSidebarTreeEntryIds,
  ) {
    final sidebarTreeEntryId = currentMailboxNode?.sidebarTreeEntryId;
    return sidebarTreeEntryId != null &&
            claimedSidebarTreeEntryIds.add(sidebarTreeEntryId)
        ? sidebarTreeEntryId
        : null;
  }

  MailboxTree _resolveTargetTree(
    PresentationMailbox mailbox,
    MailboxTree defaultTree,
    MailboxTree personalTree,
    MailboxTree teamMailboxTree,
  ) {
    if (mailbox.hasRole()) return defaultTree;
    return mailbox.isPersonal ? personalTree : teamMailboxTree;
  }

  void _propagateDeactivationIfNeeded(MailboxNode parentNode, MailboxNode currentNode) {
    if (parentNode.nodeState != MailboxState.deactivated) return;
    currentNode.updateItem(currentNode.item.withMailboxSate(MailboxState.deactivated));
    currentNode.updateNodeState(MailboxState.deactivated);
  }
}

/// Tracks the current forest while a mailbox tree is built.
///
/// Every successful parent-child attachment merges two components. Joining
/// nodes already in one component would form a cycle, so it is rejected.
/// The instance is local to one build and is released with that build.
class _MailboxNodeDisjointSet {
  final Map<Object, Object> _parentByNodeId = <Object, Object>{};
  final Map<Object, int> _rankByRootId = <Object, int>{};

  bool tryConnect(Object firstNodeId, Object secondNodeId) {
    final firstRootId = _findRoot(firstNodeId);
    final secondRootId = _findRoot(secondNodeId);
    if (firstRootId == secondRootId) return false;

    final firstRank = _rankByRootId[firstRootId] ?? 0;
    final secondRank = _rankByRootId[secondRootId] ?? 0;
    if (firstRank < secondRank) {
      _parentByNodeId[firstRootId] = secondRootId;
    } else {
      _parentByNodeId[secondRootId] = firstRootId;
      if (firstRank == secondRank) {
        _rankByRootId[firstRootId] = firstRank + 1;
      }
    }
    return true;
  }

  Object _findRoot(Object nodeId) {
    _parentByNodeId.putIfAbsent(nodeId, () => nodeId);
    var rootId = nodeId;
    while (_parentByNodeId[rootId] != rootId) {
      rootId = _parentByNodeId[rootId]!;
    }

    var currentNodeId = nodeId;
    while (currentNodeId != rootId) {
      final nextNodeId = _parentByNodeId[currentNodeId]!;
      _parentByNodeId[currentNodeId] = rootId;
      currentNodeId = nextNodeId;
    }
    return rootId;
  }
}
