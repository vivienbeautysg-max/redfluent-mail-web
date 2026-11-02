import 'package:core/presentation/resources/image_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:tmail_ui_user/features/mailbox_dashboard/presentation/model/profile_setting/profile_setting_action_type.dart';
import 'package:tmail_ui_user/features/manage_account/presentation/model/account_menu_item.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations.dart';
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

/// Redfluent Mail v0.39.3-rf18: "AI access" opens the page where users make keys for their own AI tools
/// (/account/ai/ on the webmail's own host) from the avatar menu and Settings.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppConfig.aiAccessUrl', () {
    test('is /account/ai/ on the webmail origin, so customer staff stay on mail.<their domain>', () {
      const cases = {
        'https://mail.redfluent.com/': 'https://mail.redfluent.com/account/ai/',
        'https://mail.longda.sg/dashboard?context=inbox#top': 'https://mail.longda.sg/account/ai/',
        'https://mail.example.com/settings/profiles': 'https://mail.example.com/account/ai/',
        'http://localhost:8080/': 'http://localhost:8080/account/ai/',
      };
      cases.forEach((page, want) => expect(AppConfig.aiAccessUrl(Uri.parse(page)), want, reason: page));
    });

    test('without an http(s) host it is the page on mail.redfluent.com', () {
      for (final page in ['file:///data/user/0/app/', 'about:blank', 'https:/no-host']) {
        expect(AppConfig.aiAccessUrl(Uri.parse(page)), 'https://mail.redfluent.com/account/ai/', reason: page);
      }
      expect(AppConfig.aiAccessUrl(), AppConfig.aiAccessFallbackUrl);
    });

    test('the guide and privacy URLs are unchanged (rf9, rf11)', () {
      expect(AppConfig.setupGuideUrl(Uri.parse('https://mail.longda.sg/x')), 'https://mail.longda.sg/guide/');
      expect(AppConfig.privacyPolicyUrl(Uri.parse('https://mail.longda.sg/x')),
          'https://mail.longda.sg/legal/privacy/');
    });
  });

  group('opening the AI access page', () {
    late RecordingUrlLauncher launcher;
    late UrlLauncherPlatform original;
    String? stored() => html.window.localStorage[AppUtils.aiAccessEmailKey];

    setUp(() {
      original = UrlLauncherPlatform.instance;
      launcher = RecordingUrlLauncher();
      UrlLauncherPlatform.instance = launcher;
      html.window.localStorage.remove(AppUtils.aiAccessEmailKey);
      html.window.localStorage.remove(AppUtils.setupGuideEmailKey);
    });

    tearDown(() {
      UrlLauncherPlatform.instance = original;
      html.window.localStorage.remove(AppUtils.aiAccessEmailKey);
      html.window.localStorage.remove(AppUtils.setupGuideEmailKey);
    });

    test('the key is the one the page reads', () {
      expect(AppUtils.aiAccessEmailKey, 'rf-ai-email');
    });

    test('signed in: the address is handed over in localStorage, never in the URL', () async {
      AppUtils.openAiAccess(' staff@example.com ');
      await Future<void>.delayed(Duration.zero);
      expect(stored(), 'staff@example.com');
      expect(launcher.launches, [AppConfig.aiAccessUrl()]);
      expect(launcher.launches.single, isNot(contains('staff')));
      expect(html.window.localStorage[AppUtils.setupGuideEmailKey], isNull, reason: "the guide's key is not touched");
    });

    test('no / invalid address: a stale one is removed and the page still opens', () async {
      html.window.localStorage[AppUtils.aiAccessEmailKey] = 'old@example.com';
      AppUtils.openAiAccess();
      expect(stored(), isNull);
      html.window.localStorage[AppUtils.aiAccessEmailKey] = 'old@example.com';
      AppUtils.openAiAccess('not an address');
      expect(stored(), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(launcher.launches, [AppConfig.aiAccessUrl(), AppConfig.aiAccessUrl()]);
    });
  });

  group('menus', () {
    test('avatar menu: Manage account, Set up on iPhone or Mac, AI access, Sign out', () async {
      await AppLocalizations.load(LocalizationService.defaultLocale);
      final l10n = AppLocalizations();
      expect(ProfileSettingActionType.values.map((t) => t.getTitle(l10n)),
          ['Manage account', 'Set up on iPhone or Mac', 'AI access', 'Sign out']);
      expect(ProfileSettingActionType.aiAccess.getIcon(ImagePaths()), 'assets/images/ic_ai_access.svg');
      expect(ProfileSettingActionType.aiAccess.getKey(), 'aiAccess');
    });

    test('Settings item: own name and icon, no explanation line, right after the guide', () async {
      await AppLocalizations.load(LocalizationService.defaultLocale);
      final l10n = AppLocalizations();
      expect(AccountMenuItem.aiAccess.getName(l10n), 'AI access');
      expect(AccountMenuItem.aiAccess.getExplanation(l10n), '');
      expect(AccountMenuItem.aiAccess.getAliasBrowser(), 'ai-access');
      expect(AccountMenuItem.aiAccess.getIcon(ImagePaths()), 'assets/images/ic_ai_access.svg');
      expect(AccountMenuItem.values.indexOf(AccountMenuItem.aiAccess),
          AccountMenuItem.values.indexOf(AccountMenuItem.setupGuide) + 1);
    });

    tearDown(Get.reset);
  });

  group('"AI access" is translated in every language of the picker:', () {
    const expected = {
      'fr_FR': 'Accès IA',
      'en_US': 'AI access',
      'vi_VN': 'Truy cập AI',
      'ru_RU': 'Доступ для ИИ',
      'ar_TN': 'وصول الذكاء الاصطناعي',
      'it_IT': 'Accesso IA',
      'de_DE': 'KI-Zugriff',
      'mn_MN': 'AI хандалт',
      'pt_BR': 'Acesso de IA',
      'zh_Hans': 'AI 接入',
    };

    test('the expectations cover exactly the supported locales', () {
      expect(LocalizationService.supportedLocales.map((l) => l.toString()).toSet(), expected.keys.toSet());
    });

    for (final locale in LocalizationService.supportedLocales) {
      test('$locale', () async {
        await AppLocalizations.load(locale);
        expect(AppLocalizations().aiAccess, expected[locale.toString()]);
      });
    }

    tearDownAll(() => AppLocalizations.load(LocalizationService.defaultLocale));
  });
}
