import 'package:core/presentation/extensions/color_extension.dart';
import 'package:core/presentation/utils/theme_utils.dart';
import 'package:flutter/material.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations.dart';

/// Redfluent Mail: brand mark + product name (replaces the upstream logo-with-text artwork).
class ApplicationLogoWidthTextWidget extends StatelessWidget {
  static const String brandMarkPath = 'assets/images/redfluent_logo_mark.png';

  final VoidCallback? onTapAction;
  final EdgeInsetsGeometry? margin;
  final double? iconSize;

  const ApplicationLogoWidthTextWidget({
    super.key,
    this.onTapAction,
    this.margin,
    this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    final height = iconSize ?? 33;
    final content = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(brandMarkPath, width: height, height: height, fit: BoxFit.contain),
          SizedBox(width: height * 0.3),
          Text(
            AppLocalizations.of(context).app_name,
            maxLines: 1,
            style: ThemeUtils.defaultTextStyleInterFont.copyWith(
              fontSize: height * 0.64,
              fontWeight: FontWeight.w800,
              color: AppColor.colorNameEmail,
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: onTapAction == null
        ? content
        : InkWell(onTap: onTapAction, hoverColor: Colors.transparent, child: content),
    );
  }
}
