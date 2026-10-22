import 'package:core/presentation/extensions/color_extension.dart';
import 'package:core/presentation/resources/image_paths.dart';
import 'package:core/presentation/utils/theme_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations.dart';
import 'package:tmail_ui_user/main/utils/app_utils.dart';

/// Sign-in page: opens the Apple Mail setup guide (/guide/ on this webmail's host) in a new tab.
class SetupGuideLinkWidget extends StatelessWidget {
  const SetupGuideLinkWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const color = AppColor.loginTextFieldFocusedBorder;
    return OutlinedButton.icon(
      key: const ValueKey('setup_guide_link'),
      onPressed: AppUtils.openSetupGuide,
      icon: SvgPicture.asset(
        Get.find<ImagePaths>().icPhoneSetup,
        width: 18,
        height: 18,
        colorFilter: const ColorFilter.mode(color, BlendMode.srcIn),
      ),
      label: Text(
        AppLocalizations.of(context).setupGuide,
        style: ThemeUtils.defaultTextStyleInterFont.copyWith(
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
      ),
    );
  }
}
