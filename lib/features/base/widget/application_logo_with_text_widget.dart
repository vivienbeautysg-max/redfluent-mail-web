import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations.dart';

/// Redfluent Mail brand lockup ("Soft Landing": red dot on a line + "Redfluent Mail"), replaces the rf1..rf12
/// mark.png + Inter text. The SVG has its text outlined (no font needed); the light file is for light
/// surfaces, the dark file for dark ones (the line and the wordmark swap Ink for Paper, the dot stays red).
class ApplicationLogoWidthTextWidget extends StatelessWidget {
  static const String lockupLightPath = 'assets/images/redfluent_lockup_mail_light.svg';
  static const String lockupDarkPath = 'assets/images/redfluent_lockup_mail_dark.svg';

  /// viewBox of both lockup files (0 0 764.9 76.85): width / height
  static const double lockupAspectRatio = 764.9 / 76.85;

  /// lockup height = iconSize * this, so the wordmark is about as tall as the old "mark + text" logo's text
  static const double lockupHeightFactor = 0.75;

  /// The desktop navigation bar's leading slot is sidebarMenuWidth (236) - NavigationBarStyle.horizontalMargin (30)
  /// = 206 px wide, and a Row gives its children unbounded width, so the default size (33 -> a 246 px lockup) would
  /// overflow it by 40 px. 26 -> a 194 px lockup.
  static const double navigationBarIconSize = 26;

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
    final height = (iconSize ?? 33) * lockupHeightFactor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final content = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: SvgPicture.asset(
        isDark ? lockupDarkPath : lockupLightPath,
        width: height * lockupAspectRatio,
        height: height,
        semanticsLabel: AppLocalizations.of(context).app_name,
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
