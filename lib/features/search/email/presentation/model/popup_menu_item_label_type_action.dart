import 'package:core/presentation/resources/image_paths.dart';
import 'package:labels/extensions/label_extension.dart';
import 'package:labels/model/label.dart';
import 'package:tmail_ui_user/features/base/model/popup_menu_item_action.dart';

class PopupMenuItemLabelTypeAction
    extends PopupMenuItemActionRequiredSelectedIcon<Label> {
  final ImagePaths imagePaths;

  PopupMenuItemLabelTypeAction(
    super.action,
    super.selectedAction,
    this.imagePaths,
  );

  @override
  String get actionName => action.safeDisplayName;

  @override
  String get selectedIcon => imagePaths.icFilterSelected;
}
