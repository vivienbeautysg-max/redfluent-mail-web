import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmail_ui_user/features/login/presentation/privacy_link_widget.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations_delegate.dart';
import 'package:tmail_ui_user/main/localizations/localization_service.dart';
import 'package:tmail_ui_user/main/utils/app_config.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/link.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Records what url_launcher would open instead of opening it.
class RecordingUrlLauncher extends UrlLauncherPlatform {
  final launches = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launches.add(url);
    return true;
  }
}

/// Redfluent Mail v0.39.3-rf9: the sign-in page's "Privacy policy" link opens the Redfluent Mail privacy
/// policy on the webmail's own host (/legal/privacy/, served by the gateway).
void main() {
  group('AppConfig.privacyPolicyUrl', () {
    test('is /legal/privacy/ on the webmail origin, so customer staff stay on mail.<their domain>', () {
      const cases = {
        'https://mail.redfluent.com/': 'https://mail.redfluent.com/legal/privacy/',
        'https://mail.longda.sg/': 'https://mail.longda.sg/legal/privacy/',
        'https://mail.example.com/dashboard?context=inbox#top': 'https://mail.example.com/legal/privacy/',
        'https://mail.example.com/login/oidc?code=x#y': 'https://mail.example.com/legal/privacy/',
        'http://localhost:8080/': 'http://localhost:8080/legal/privacy/',
      };
      cases.forEach((page, want) => expect(AppConfig.privacyPolicyUrl(Uri.parse(page)), want, reason: page));
    });

    test('without an http(s) host it is the Redfluent Mail policy on mail.redfluent.com', () {
      expect(AppConfig.linagoraPrivacyUrl, 'https://mail.redfluent.com/legal/privacy/');
      for (final page in ['file:///data/user/0/app/', 'about:blank', 'twakemail.mobile://redirect', 'https:/no-host']) {
        expect(AppConfig.privacyPolicyUrl(Uri.parse(page)), AppConfig.linagoraPrivacyUrl, reason: page);
      }
      // a VM test runs from a file: URI, like the mobile apps
      expect(AppConfig.privacyPolicyUrl(), AppConfig.linagoraPrivacyUrl);
    });
  });

  group('PrivacyLinkWidget', () {
    late RecordingUrlLauncher launcher;
    late UrlLauncherPlatform original;

    setUp(() {
      original = UrlLauncherPlatform.instance;
      launcher = RecordingUrlLauncher();
      UrlLauncherPlatform.instance = launcher;
    });

    tearDown(() => UrlLauncherPlatform.instance = original);

    Future<void> pumpAndTap(WidgetTester tester, Widget link) async {
      await tester.pumpWidget(MaterialApp(
        locale: LocalizationService.defaultLocale,
        supportedLocales: LocalizationService.supportedLocales,
        localeResolutionCallback: LocalizationService.resolveLocale,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: Center(child: link)),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Privacy policy', findRichText: true));
      await tester.pumpAndSettle();
    }

    testWidgets('by default opens AppConfig.privacyPolicyUrl()', (tester) async {
      await pumpAndTap(tester, const PrivacyLinkWidget());
      expect(launcher.launches, [AppConfig.privacyPolicyUrl()]);
      expect(launcher.launches.single, isNot(contains('www.redfluent.com')));
    });

    testWidgets('an explicit URL still wins', (tester) async {
      await pumpAndTap(tester, const PrivacyLinkWidget(privacyUrlString: 'https://example.com/p'));
      expect(launcher.launches, ['https://example.com/p']);
    });
  });
}
