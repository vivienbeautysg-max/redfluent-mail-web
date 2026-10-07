import 'package:core/presentation/extensions/color_extension.dart';
import 'package:core/presentation/utils/theme_utils.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:tmail_ui_user/main/utils/app_config.dart';
import 'package:tmail_ui_user/main/utils/app_utils.dart';

/// AGPL-3.0 section 13: offers every network user the Corresponding Source of this modified version.
class SourceCodeLinkWidget extends StatelessWidget {
  const SourceCodeLinkWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final style = ThemeUtils.defaultTextStyleInterFont.copyWith(
      color: AppColor.colorTextBody,
      fontSize: 12,
      fontWeight: FontWeight.w400,
    );
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: style,
        children: [
          const TextSpan(text: 'Open source under AGPL-3.0 \u00b7 '),
          TextSpan(
            text: 'Source code',
            style: style.copyWith(color: AppColor.loginTextFieldFocusedBorder),
            recognizer: TapGestureRecognizer()..onTap = () => AppUtils.launchLink(AppConfig.sourceCodeUrl),
          ),
        ],
      ),
    );
  }
}
