import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tmail_ui_user/features/manage_account/data/datasource_impl/manage_account_datasource_impl.dart';
import 'package:tmail_ui_user/features/manage_account/data/local/language_cache_manager.dart';
import 'package:tmail_ui_user/features/manage_account/data/local/preferences_setting_manager.dart';
import 'package:tmail_ui_user/features/manage_account/data/repository/manage_account_repository_impl.dart';
import 'package:tmail_ui_user/features/manage_account/domain/state/save_language_state.dart';
import 'package:tmail_ui_user/features/manage_account/domain/usecases/save_language_interactor.dart';
import 'package:tmail_ui_user/features/manage_account/presentation/language_and_region/extensions/locale_extension.dart';
import 'package:tmail_ui_user/main/exceptions/thrower/cache_exception_thrower.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations_delegate.dart';
import 'package:tmail_ui_user/main/localizations/localization_service.dart';

/// Redfluent Mail v0.39.3-rf2: Simplified Chinese, English by default, remembered choice.
/// v0.39.3-rf3: "Change password" in every language of the picker.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const zhHans = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');
  const english = LocalizationService.defaultLocale;
  const delegates = <LocalizationsDelegate<dynamic>>[
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  void setDeviceLocale(Locale locale) {
    final dispatcher = TestWidgetsFlutterBinding.instance.platformDispatcher;
    dispatcher.localeTestValue = locale;
    dispatcher.localesTestValue = [locale];
  }

  Future<SharedPreferences> storage([Map<String, Object> values = const {}]) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  SaveLanguageInteractor saveLanguageInteractor(SharedPreferences prefs) {
    return SaveLanguageInteractor(
      ManageAccountRepositoryImpl(
        ManageAccountDataSourceImpl(
          LanguageCacheManager(prefs),
          PreferencesSettingManager(prefs),
          CacheExceptionThrower(),
        ),
      ),
    );
  }

  /// Same locale wiring as lib/main.dart.
  Widget app(Widget home) {
    return GetMaterialApp(
      supportedLocales: LocalizationService.supportedLocales,
      localizationsDelegates: delegates,
      localeResolutionCallback: LocalizationService.resolveLocale,
      locale: LocalizationService.getInitialLocale(),
      fallbackLocale: LocalizationService.fallbackLocale,
      home: home,
    );
  }

  final probe = Builder(
    builder: (context) => Text(
      '${Localizations.localeOf(context)}|${AppLocalizations.of(context).changePassword}',
    ),
  );

  setUp(() => Get.testMode = true);

  tearDown(() async {
    Get.reset();
    Get.locale = null;
    TestWidgetsFlutterBinding.instance.platformDispatcher.clearAllTestValues();
    await AppLocalizations.load(english);
  });

  group('Simplified Chinese:', () {
    test('supportedLocales includes zh-Hans (and no Traditional Chinese)', () {
      expect(LocalizationService.supportedLocales, contains(zhHans));
      expect(
        LocalizationService.supportedLocales.where((l) => l.scriptCode == 'Hant'),
        isEmpty,
      );
      expect(const AppLocalizationsDelegate().isSupported(zhHans), isTrue);
    });

    test('the zh_Hans catalog is loaded, not the English fallback', () async {
      await AppLocalizations.load(zhHans);

      expect(Intl.defaultLocale, 'zh_Hans');
      final l10n = AppLocalizations();
      expect(l10n.sign_out, '登出');
      expect(l10n.language, '语言');
      expect(l10n.changePassword, '修改密码');
      expect(l10n.languageChineseSimplified, '简体中文');
      expect(l10n.app_name, 'Redfluent Mail');
      expect(
        l10n.sendMessageFailureWithInvalidRecipients('a@b.c'),
        '邮件发送失败，因为以下收件人无效：a@b.c',
      );
    });

    test('intl_zh_Hans.arb translates every message key', () {
      Map<String, dynamic> arb(String name) =>
          jsonDecode(File('lib/l10n/$name.arb').readAsStringSync()) as Map<String, dynamic>;
      final keys = arb('intl_messages').keys.where((k) => !k.startsWith('@'));
      final zh = arb('intl_zh_Hans');
      final missing = keys.where((k) => (zh[k] as String?)?.trim().isNotEmpty != true);
      expect(missing, isEmpty);
    });

    testWidgets('a screen under zh-Hans renders Chinese', (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: zhHans,
        supportedLocales: LocalizationService.supportedLocales,
        localizationsDelegates: delegates,
        localeResolutionCallback: LocalizationService.resolveLocale,
        home: probe,
      ));
      await tester.pumpAndSettle();

      expect(find.text('zh_Hans|修改密码'), findsOneWidget);
    });

    test('language picker label', () async {
      String label(Locale locale) =>
          '${locale.getLanguageNameByCurrentLocale(AppLocalizations())} - ${locale.getSourceLanguageName()}';

      await AppLocalizations.load(english);
      expect(label(zhHans), 'Chinese (Simplified) - 简体中文');

      await AppLocalizations.load(zhHans);
      expect(label(zhHans), '简体中文 - 简体中文');
    });
  });

  group('"Change password" is translated in every language of the picker (rf3):', () {
    const expected = {
      'fr_FR': 'Modifier le mot de passe',
      'en_US': 'Change password',
      'vi_VN': 'Đổi mật khẩu',
      'ru_RU': 'Изменить пароль',
      'ar_TN': 'تغيير كلمة المرور',
      'it_IT': 'Cambia password',
      'de_DE': 'Passwort ändern',
      'mn_MN': 'Нууц үг солих',
      'pt_BR': 'Alterar senha',
      'zh_Hans': '修改密码',
    };

    test('the expectations cover exactly the supported locales', () {
      expect(
        LocalizationService.supportedLocales.map((l) => l.toString()).toSet(),
        expected.keys.toSet(),
      );
    });

    for (final locale in LocalizationService.supportedLocales) {
      test('$locale', () async {
        await AppLocalizations.load(locale);
        expect(AppLocalizations().changePassword, expected[locale.toString()]);
      });
    }
  });

  group('English is the default language:', () {
    for (final device in const [
      Locale('zh', 'CN'),
      zhHans,
      Locale('zh', 'TW'),
      Locale('fr', 'FR'),
      Locale('vi', 'VN'),
    ]) {
      test('no cached choice, device ${device.toLanguageTag()} -> en-US', () async {
        setDeviceLocale(device);
        Get.put(LanguageCacheManager(await storage()));

        expect(LocalizationService.getInitialLocale(), english);
      });
    }

    test('nothing registered yet (first start) -> en-US', () {
      setDeviceLocale(const Locale('zh', 'CN'));

      expect(LocalizationService.getInitialLocale(), english);
    });

    testWidgets('the app opens in English on a Chinese device with no cached choice', (tester) async {
      setDeviceLocale(const Locale('zh', 'CN'));
      Get.put(LanguageCacheManager(await storage()));

      await tester.pumpWidget(app(probe));
      await tester.pumpAndSettle();

      expect(find.text('en_US|Change password'), findsOneWidget);
    });

    testWidgets('initializeAppLanguage ignores the device language', (tester) async {
      setDeviceLocale(const Locale('zh', 'CN'));
      Get.put(LanguageCacheManager(await storage()));

      LocalizationService.initializeAppLanguage(serverLanguage: null);
      await tester.pumpAndSettle();

      expect(Get.locale, english);
    });

    test('resolveLocale falls back to English, not to the first supported locale (French)', () {
      const supported = LocalizationService.supportedLocales;
      expect(supported.first.languageCode, 'fr');
      expect(LocalizationService.resolveLocale(const Locale('es', 'ES'), supported), english);
      expect(LocalizationService.resolveLocale(null, supported), english);
      expect(LocalizationService.resolveLocale(zhHans, supported), zhHans);
      expect(LocalizationService.resolveLocale(const Locale('fr', 'FR'), supported), const Locale('fr', 'FR'));
    });
  });

  group('An explicit choice is remembered:', () {
    for (final (picked, expectedText) in const [
      (zhHans, 'zh_Hans|修改密码'),
      (Locale('fr', 'FR'), 'fr_FR|Modifier le mot de passe'),
      (Locale('en', 'US'), 'en_US|Change password'),
    ]) {
      testWidgets('${picked.toLanguageTag()} picked on the Language page survives a reload', (tester) async {
        final prefs = await storage();
        final states = await saveLanguageInteractor(prefs).execute(picked).toList();
        expect(states.last.fold((failure) => failure, (success) => success), isA<SaveLanguageSuccess>());

        // reload: new cache manager over the same browser storage, device language differs
        setDeviceLocale(const Locale('vi', 'VN'));
        Get.put(LanguageCacheManager(prefs));

        expect(LocalizationService.getInitialLocale(), picked);
        await tester.pumpWidget(app(probe));
        await tester.pumpAndSettle();
        expect(find.text(expectedText), findsOneWidget);
      });
    }

    testWidgets('a language "zh" stored in the server settings resolves to zh-Hans', (tester) async {
      Get.put(LanguageCacheManager(await storage()));

      LocalizationService.initializeAppLanguage(serverLanguage: 'zh');
      await tester.pumpAndSettle();

      expect(Get.locale, zhHans);
    });

    testWidgets('initializeAppLanguage restores a cached Chinese choice', (tester) async {
      final prefs = await storage();
      await LanguageCacheManager(prefs).persistLanguage(zhHans);
      Get.put(LanguageCacheManager(prefs));

      LocalizationService.initializeAppLanguage(serverLanguage: null);
      await tester.pumpAndSettle();

      expect(Get.locale, zhHans);
    });
  });
}
