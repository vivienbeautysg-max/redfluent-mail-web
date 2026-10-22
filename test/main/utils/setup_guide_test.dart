import 'package:core/presentation/resources/image_paths.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:tmail_ui_user/features/login/presentation/setup_guide_link_widget.dart';
import 'package:tmail_ui_user/features/mailbox_dashboard/presentation/model/profile_setting/profile_setting_action_type.dart';
import 'package:tmail_ui_user/features/manage_account/presentation/model/account_menu_item.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations_delegate.dart';
import 'package:tmail_ui_user/main/localizations/localization_service.dart';
import 'package:tmail_ui_user/main/universal_import/html_stub.dart' as html;
import 'package:tmail_ui_user/main/utils/app_config.dart';
import 'package:tmail_ui_user/main/utils/app_utils.dart';
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

/// Redfluent Mail v0.39.3-rf11: "Set up on iPhone or Mac" opens the Apple Mail guide (/guide/ on the
/// webmail's own host) from the sign-in page, the avatar menu and Settings.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppConfig.setupGuideUrl', () {
    test('is /guide/ on the webmail origin, so customer staff stay on mail.<their domain>', () {
      const cases = {
        'https://mail.redfluent.com/': 'https://mail.redfluent.com/guide/',
        'https://mail.longda.sg/login': 'https://mail.longda.sg/guide/',
        'https://mail.example.com/dashboard?context=inbox#top': 'https://mail.example.com/guide/',
        'http://localhost:8080/': 'http://localhost:8080/guide/',
      };
      cases.forEach((page, want) => expect(AppConfig.setupGuideUrl(Uri.parse(page)), want, reason: page));
    });

    test('without an http(s) host it is the guide on mail.redfluent.com', () {
      for (final page in ['file:///data/user/0/app/', 'about:blank', 'https:/no-host']) {
        expect(AppConfig.setupGuideUrl(Uri.parse(page)), 'https://mail.redfluent.com/guide/', reason: page);
      }
      expect(AppConfig.setupGuideUrl(), AppConfig.setupGuideFallbackUrl);
    });

    test('the privacy policy URL is unchanged by the shared helper (rf9)', () {
      expect(AppConfig.privacyPolicyUrl(Uri.parse('https://mail.longda.sg/x?y#z')),
          'https://mail.longda.sg/legal/privacy/');
      expect(AppConfig.privacyPolicyUrl(Uri.parse('about:blank')), AppConfig.linagoraPrivacyUrl);
    });
  });

  group('opening the guide', () {
    late RecordingUrlLauncher launcher;
    late UrlLauncherPlatform original;
    String? stored() => html.window.localStorage[AppUtils.setupGuideEmailKey];

    setUp(() {
      original = UrlLauncherPlatform.instance;
      launcher = RecordingUrlLauncher();
      UrlLauncherPlatform.instance = launcher;
      html.window.localStorage.remove(AppUtils.setupGuideEmailKey);
      Get.testMode = true;
      Get.put(ImagePaths());
    });

    tearDown(() {
      UrlLauncherPlatform.instance = original;
      html.window.localStorage.remove(AppUtils.setupGuideEmailKey);
      Get.reset();
    });

    test('signed in: the address is handed over in localStorage, never in the URL', () async {
      AppUtils.openSetupGuide(' staff@example.com ');
      await Future<void>.delayed(Duration.zero);
      expect(stored(), 'staff@example.com');
      expect(launcher.launches, [AppConfig.setupGuideUrl()]);
      expect(launcher.launches.single, isNot(contains('staff')));
    });

    test('no / invalid address: a stale one is removed', () async {
      html.window.localStorage[AppUtils.setupGuideEmailKey] = 'old@example.com';
      AppUtils.openSetupGuide();
      expect(stored(), isNull);
      html.window.localStorage[AppUtils.setupGuideEmailKey] = 'old@example.com';
      AppUtils.openSetupGuide('not an address');
      expect(stored(), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(launcher.launches.length, 2);
    });

    testWidgets('the sign-in page button opens the guide and clears a stale address', (tester) async {
      html.window.localStorage[AppUtils.setupGuideEmailKey] = 'old@example.com';
      await tester.pumpWidget(const MaterialApp(
        locale: LocalizationService.defaultLocale,
        supportedLocales: LocalizationService.supportedLocales,
        localeResolutionCallback: LocalizationService.resolveLocale,
        localizationsDelegates: [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: Center(child: SetupGuideLinkWidget())),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Set up on iPhone or Mac'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('setup_guide_link')));
      await tester.pumpAndSettle();
      expect(launcher.launches, [AppConfig.setupGuideUrl()]);
      expect(stored(), isNull);
    });
  });

  group('menus', () {
    test('avatar menu: Manage account, Set up on iPhone or Mac, Sign out', () async {
      await AppLocalizations.load(LocalizationService.defaultLocale);
      final l10n = AppLocalizations();
      expect(ProfileSettingActionType.values.map((t) => t.getTitle(l10n)),
          ['Manage account', 'Set up on iPhone or Mac', 'Sign out']);
      expect(ProfileSettingActionType.setupGuide.getIcon(ImagePaths()), 'assets/images/ic_phone_setup.svg');
    });

    test('Settings item: own name and icon, no explanation line', () async {
      await AppLocalizations.load(LocalizationService.defaultLocale);
      final l10n = AppLocalizations();
      expect(AccountMenuItem.setupGuide.getName(l10n), 'Set up on iPhone or Mac');
      expect(AccountMenuItem.setupGuide.getExplanation(l10n), '');
      expect(AccountMenuItem.setupGuide.getAliasBrowser(), 'setup-guide');
      expect(AccountMenuItem.setupGuide.getIcon(ImagePaths()), 'assets/images/ic_phone_setup.svg');
    });
  });

  group('"Set up on iPhone or Mac" is translated in every language of the picker:', () {
    const expected = {
      'fr_FR': 'Configurer sur iPhone ou Mac',
      'en_US': 'Set up on iPhone or Mac',
      'vi_VN': 'Thiết lập trên iPhone hoặc Mac',
      'ru_RU': 'Настроить на iPhone или Mac',
      'ar_TN': 'الإعداد على iPhone أو Mac',
      'it_IT': 'Configura su iPhone o Mac',
      'de_DE': 'Auf iPhone oder Mac einrichten',
      'mn_MN': 'iPhone эсвэл Mac дээр тохируулах',
      'pt_BR': 'Configurar no iPhone ou Mac',
      'zh_Hans': '在 iPhone 或 Mac 上设置',
    };

    test('the expectations cover exactly the supported locales', () {
      expect(LocalizationService.supportedLocales.map((l) => l.toString()).toSet(), expected.keys.toSet());
    });

    for (final locale in LocalizationService.supportedLocales) {
      test('$locale', () async {
        await AppLocalizations.load(locale);
        expect(AppLocalizations().setupGuide, expected[locale.toString()]);
      });
    }

    tearDownAll(() => AppLocalizations.load(LocalizationService.defaultLocale));
  });
}
