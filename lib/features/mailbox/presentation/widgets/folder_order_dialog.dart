import 'package:core/presentation/extensions/color_extension.dart';
import 'package:core/presentation/resources/image_paths.dart';
import 'package:core/presentation/utils/theme_utils.dart';
import 'package:core/presentation/views/dialog/confirm_dialog_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:model/mailbox/presentation_mailbox.dart';
import 'package:tmail_ui_user/features/mailbox/presentation/extensions/presentation_mailbox_extension.dart';
import 'package:tmail_ui_user/features/mailbox/presentation/utils/folder_order_utils.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations.dart';

/// Redfluent (rf16): lets the user drag the system folders into their own
/// order. Pops with the new order on Save, with null on Cancel; saving it is
/// up to the caller (MailboxController writes it to the server).
class FolderOrderDialog extends StatefulWidget {
  final List<PresentationMailbox> folders;
  final ImagePaths imagePaths;

  const FolderOrderDialog({
    super.key,
    required this.folders,
    required this.imagePaths,
  });

  @override
  State<FolderOrderDialog> createState() => _FolderOrderDialogState();
}

class _FolderOrderDialogState extends State<FolderOrderDialog> {
  late List<PresentationMailbox> _folders = List.of(widget.folders);

  void _moveFolder(int oldIndex, int newIndex) {
    setState(() {
      final folder = _folders.removeAt(oldIndex);
      _folders.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, folder);
    });
  }

  void _resetToDefault() {
    setState(() => _folders = FolderOrderUtils.defaultOrder(_folders));
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context);

    return Dialog(
      key: const Key('folder_order_dialog'),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 421),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: 24,
            end: 24,
            top: 24,
            bottom: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                // The title and the hint scroll with the list, so a short
                // screen (a phone held sideways) still shows every row.
                child: ReorderableListView.builder(
                  key: const Key('folder_order_list'),
                  shrinkWrap: true,
                  buildDefaultDragHandles: false,
                  header: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        appLocalizations.reorderFolders,
                        style: ThemeUtils.textStyleM3HeadlineSmall.copyWith(
                          color: AppColor.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        appLocalizations.reorderFoldersHint,
                        style: ThemeUtils.textStyleM3BodyMedium1.copyWith(
                          fontSize: 14,
                          height: 20 / 14,
                          color: AppColor.steelGrayA540,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                  itemCount: _folders.length,
                  onReorder: _moveFolder,
                  proxyDecorator: (child, index, animation) => Material(
                    elevation: 4,
                    color: Colors.white,
                    borderRadius: const BorderRadius.all(Radius.circular(10)),
                    child: child,
                  ),
                  itemBuilder: (context, index) => _FolderOrderRow(
                    key: ValueKey(_folders[index].id),
                    folder: _folders[index],
                    index: index,
                    imagePaths: widget.imagePaths,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildActions(context, appLocalizations),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context, AppLocalizations appLocalizations) {
    final isDefaultOrder = FolderOrderUtils.isDefaultOrder(_folders);

    // Wraps onto a second line instead of being cut off in long languages.
    final resetButton = TextButton(
      key: const Key('folder_order_reset_button'),
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(100)),
        ),
      ),
      onPressed: isDefaultOrder ? null : _resetToDefault,
      child: Text(
        appLocalizations.resetToDefault,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: ThemeUtils.textStyleM3LabelLarge(
          color: isDefaultOrder ? AppColor.m3Tertiary : AppColor.primaryMain,
        ),
      ),
    );

    // Flexible: on a very narrow screen the labels shorten instead of overflowing.
    final dialogButtons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SizedBox(
            height: 40,
            child: ConfirmDialogButton(
              key: const Key('folder_order_cancel_button'),
              label: appLocalizations.cancel,
              textColor: AppColor.primaryMain,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              onTapAction: () => Navigator.of(context).pop(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: SizedBox(
            height: 40,
            child: ConfirmDialogButton(
              key: const Key('folder_order_save_button'),
              label: appLocalizations.save,
              backgroundColor: AppColor.primaryMain,
              textColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              onTapAction: () => Navigator.of(context).pop(_folders),
            ),
          ),
        ),
      ],
    );

    // One row (Reset left, Cancel + Save right) when everything fits at its
    // natural width, otherwise Reset above the two buttons.
    return OverflowBar(
      alignment: MainAxisAlignment.spaceBetween,
      overflowAlignment: OverflowBarAlignment.end,
      overflowSpacing: 8,
      children: [resetButton, dialogButtons],
    );
  }
}

class _FolderOrderRow extends StatelessWidget {
  final PresentationMailbox folder;
  final int index;
  final ImagePaths imagePaths;

  const _FolderOrderRow({
    super.key,
    required this.folder,
    required this.index,
    required this.imagePaths,
  });

  @override
  Widget build(BuildContext context) {
    final name = folder.getDisplayName(context);

    return ReorderableDelayedDragStartListener(
      index: index,
      child: Container(
        height: 48,
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsetsDirectional.only(start: 12),
        decoration: const BoxDecoration(
          color: AppColor.colorBgMailboxSelected,
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        child: Row(
          children: [
            SvgPicture.asset(
              folder.getMailboxIcon(imagePaths),
              width: 20,
              height: 20,
              excludeFromSemantics: true,
              colorFilter: AppColor.steelGrayA540.asFilter(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ThemeUtils.textStyleM3BodyMedium1.copyWith(
                  fontSize: 15,
                  color: AppColor.textPrimary,
                ),
              ),
            ),
            ReorderableDragStartListener(
              key: Key('folder_order_handle_$index'),
              index: index,
              // Screen readers get "Move up" / "Move down" from
              // ReorderableListView itself.
              child: const MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Icon(
                    Icons.drag_indicator,
                    size: 20,
                    color: AppColor.steelGrayA540,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
