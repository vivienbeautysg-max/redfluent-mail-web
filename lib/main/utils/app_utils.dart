import 'package:core/core.dart';
import 'package:core/utils/external_link_policy.dart';
import 'package:date_format/date_format.dart' as date_format;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart' as intl;
import 'package:tmail_ui_user/main/localizations/app_localizations.dart';
import 'package:tmail_ui_user/main/localizations/language_code_constants.dart';
import 'package:tmail_ui_user/main/utils/app_config.dart';
import 'package:tmail_ui_user/main/universal_import/html_stub.dart' as html;
import 'package:url_launcher/url_launcher.dart';

class AppUtils {
  const AppUtils._();

  static void launchLink(String url, {bool isNewTab = true}) {
    log('AppUtils::launchLink: url = $url');
    final uri = Uri.tryParse(url);
    if (uri == null || !ExternalLinkPolicy.canLaunchFromContent(uri)) {
      logWarning('AppUtils::launchLink: refused, scheme not allowed: $url');
      return;
    }
    if (PlatformInfo.isWeb && HtmlUtils.isSafariBelow17()) {
      // url_launcher_web blocks javascript: and always passes
      // noopener,noreferrer; this branch bypasses that library entirely, so
      // restore both properties here.
      html.window.open(url, isNewTab ? '_blank' : '_self', HtmlUtils.windowFeatures(noOpener: true));
    } else {
      launchUrl(
        uri,
        webOnlyWindowName: isNewTab ? '_blank' : '_self',
        mode: LaunchMode.externalApplication,
      );
    }
  }

  /// localStorage key read once (then removed) by the guide page (/guide/app.js).
  static const String setupGuideEmailKey = 'rf-guide-email';

  /// The Apple Mail setup guide in a new tab. With the signed-in address it goes along in this
  /// origin's localStorage (never in the URL), so the guide's profile form opens with it filled in;
  /// without one (sign-in page) any address left from an earlier session is removed first.
  static void openSetupGuide([String? email]) {
    final address = email?.trim() ?? '';
    try {
      if (RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(address)) {
        html.window.localStorage[setupGuideEmailKey] = address;
      } else {
        html.window.localStorage.remove(setupGuideEmailKey);
      }
    } catch (e) {
      logWarning('AppUtils::openSetupGuide: localStorage not available: $e');
    }
    launchLink(AppConfig.setupGuideUrl());
  }

  /// sessionStorage key read by the password page (/account/password/app.js).
  static const String changePasswordEmailKey = 'rf-pw-email';

  /// Same tab on purpose: the password page links back to the webmail, and
  /// after a change the webmail's saved credentials are stale anyway.
  /// The signed-in address goes along in this tab's sessionStorage (never in
  /// the URL), so the page opens with it filled in.
  static Future<bool> openChangePasswordPage([String? email]) {
    final address = email?.trim() ?? '';
    try {
      if (RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(address)) {
        html.window.sessionStorage[changePasswordEmailKey] = address;
      } else {
        html.window.sessionStorage.remove(changePasswordEmailKey);
      }
    } catch (e) {
      logWarning('AppUtils::openChangePasswordPage: sessionStorage not available: $e');
    }
    return launchUrl(
      AppConfig.changePasswordUri(),
      webOnlyWindowName: '_self',
    );
  }

  static bool isDirectionRTL(BuildContext context) {
    return intl.Bidi.isRtlLanguage(Localizations.localeOf(context).languageCode);
  }

  static TextDirection getCurrentDirection(BuildContext context) => Directionality.maybeOf(context) ?? TextDirection.ltr;

  static bool isEmailLocalhost(String email) {
    return StringConvert.isEmailLocalhost(email);
  }

  static void copyEmailAddressToClipboard(BuildContext context, String emailAddress) {
    Clipboard.setData(ClipboardData(text: emailAddress)).then((_){
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).email_address_copied_to_clipboard))
      );
    });
  }

  static void copyLinkToClipboard(BuildContext context, String link) {
    Clipboard.setData(ClipboardData(text: link)).then((_) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).linkCopiedToClipboard)),
      );
    });
  }

  static date_format.DateLocale getCurrentDateLocale() {
    final currentLanguageCode = Get.locale?.languageCode;
    if (currentLanguageCode == LanguageCodeConstants.french) {
      return const date_format.FrenchDateLocale();
    } else if (currentLanguageCode == LanguageCodeConstants.english) {
      return const date_format.EnglishDateLocale();
    } else if (currentLanguageCode == LanguageCodeConstants.vietnamese) {
      return const date_format.VietnameseDateLocale();
    } else if (currentLanguageCode == LanguageCodeConstants.russian) {
      return const date_format.RussianDateLocale();
    } else if (currentLanguageCode == LanguageCodeConstants.arabic) {
      return const date_format.ArabicDateLocale();
    } else if (currentLanguageCode == LanguageCodeConstants.italian) {
      return const date_format.ItalianDateLocale();
    } else if (currentLanguageCode == LanguageCodeConstants.german) {
      return const date_format.GermanDateLocale();
    } else if (currentLanguageCode == LanguageCodeConstants.portuguese) {
      return const date_format.PortugueseDateLocale();
    } else {
      return const date_format.EnglishDateLocale();
    }
  }

  static String getTimeZone() {
    final timeZoneOffset = DateTime.now().timeZoneOffset.inHours;
    final timeZoneOffsetAsString = timeZoneOffset >= 0 ? '+$timeZoneOffset' : '$timeZoneOffset';
    return 'GMT$timeZoneOffsetAsString';
  }
}
