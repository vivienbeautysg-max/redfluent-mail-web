import 'package:core/utils/app_logger.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:tmail_ui_user/features/manage_account/data/local/language_cache_manager.dart';
import 'package:tmail_ui_user/main/localizations/language_code_constants.dart';
import 'package:tmail_ui_user/main/routes/route_navigation.dart';

typedef OnServerLanguageApplied = Function(Locale locale);

class LocalizationService extends Translations {

  static const defaultLocale = Locale(LanguageCodeConstants.english, 'US');
  static const fallbackLocale = Locale(LanguageCodeConstants.english, 'US');
  static const brazilianPortugueseLocale = Locale(
    LanguageCodeConstants.portuguese,
    'BR',
  );
  // No region subtag: the catalog is intl_zh_Hans.arb, looked up as 'zh_Hans'.
  static const simplifiedChineseLocale = Locale.fromSubtags(
    languageCode: LanguageCodeConstants.chinese,
    scriptCode: 'Hans',
  );

  static final supportedLanguageCodes = [
    LanguageCodeConstants.french,
    LanguageCodeConstants.english,
    LanguageCodeConstants.vietnamese,
    LanguageCodeConstants.russian,
    LanguageCodeConstants.arabic,
    LanguageCodeConstants.italian,
    LanguageCodeConstants.german,
    LanguageCodeConstants.mongolian,
    LanguageCodeConstants.portuguese,
    LanguageCodeConstants.chinese,
  ];

  static const List<Locale> supportedLocales = [
    Locale(LanguageCodeConstants.french, 'FR'),
    Locale(LanguageCodeConstants.english, 'US'),
    Locale(LanguageCodeConstants.vietnamese, 'VN'),
    Locale(LanguageCodeConstants.russian, 'RU'),
    Locale(LanguageCodeConstants.arabic, 'TN'),
    Locale(LanguageCodeConstants.italian, 'IT'),
    Locale(LanguageCodeConstants.german, 'DE'),
    Locale(LanguageCodeConstants.mongolian, 'MN'),
    Locale(LanguageCodeConstants.portuguese, 'BR'),
    simplifiedChineseLocale,
  ];

  static void changeLocale(Locale newLocale) {
    final normalizedLocale = _normalizeLocale(newLocale);
    log('LocalizationService::changeLocale(): New locale is $normalizedLocale');
    Get.updateLocale(normalizedLocale);
  }

  // Tracks catalog state, not permanent: only pt_BR ships a full catalog
  // (bare pt and pt_AO/pt_MZ would land on the partial intl_pt.arb, pt_PT
  // has none), so every Portuguese variant resolves to pt_BR. Drop the
  // pt case here when a dedicated catalog for it lands.
  static Locale _normalizeLocale(Locale locale) {
    if (locale.languageCode == LanguageCodeConstants.portuguese) {
      return brazilianPortugueseLocale;
    }
    // Same for Chinese: only zh_Hans ships a catalog, and LanguageCacheManager
    // keeps no script subtag, so a stored zh_Hans comes back as plain zh.
    if (locale.languageCode == LanguageCodeConstants.chinese) {
      return simplifiedChineseLocale;
    }
    return locale;
  }

  // Redfluent Mail: English unless the user picked a language. The browser /
  // OS language is deliberately not used.
  static Locale getInitialLocale() {
    try {
      final cachedLocale = _getCachedLocale();
      if (cachedLocale != null) return _normalizeLocale(cachedLocale);

      return defaultLocale;
    } catch (e) {
      logWarning('LocalizationService::getInitialLocale:Exception is $e');
      return defaultLocale;
    }
  }

  static Locale? _getCachedLocale() {
    try {
      final languageCacheManager = getBinding<LanguageCacheManager>();
      return languageCacheManager?.getStoredLanguage();
    } catch (e) {
      logWarning('LocalizationService::getCachedLocale: Exception: $e');
      return null;
    }
  }

  // GetMaterialApp.localeResolutionCallback. GetMaterialApp always passes its
  // own `locale` here (see getInitialLocale); anything unsupported resolves to
  // English, not to supportedLocales.first (French).
  static Locale resolveLocale(Locale? locale, Iterable<Locale> supportedLocales) {
    for (final supported in supportedLocales) {
      if (supported.languageCode == locale?.languageCode) {
        return locale!;
      }
    }
    return defaultLocale;
  }

  static String supportedLocalesToLanguageTags() {
    final listLanguageTags = supportedLocales.map((locale) => locale.toLanguageTag()).join(', ');
    log('LocalizationService::supportedLocalesToLanguageTags:listLanguageTags: $listLanguageTags');
    return listLanguageTags;
  }

  static void initializeAppLanguage({
    String? serverLanguage,
    OnServerLanguageApplied? onServerLanguageApplied,
  }) {
    log('LocalizationService::initializeAppLanguage:Server language: $serverLanguage');
    try {
      // From server
      if (serverLanguage != null &&
          _useServerLocale(
            languageCode: serverLanguage,
            onServerLanguageApplied: onServerLanguageApplied,
          )) {
        return;
      }

      if (_useCachedLocale()) return;

      _useDefaultLocale();
    } catch (e) {
      logWarning('LocalizationService::initializeAppLanguage: Exception: $e');
      _useDefaultLocale();
    }
  }

  static void _useDefaultLocale() {
    final currentLocale = Get.locale;
    if (currentLocale == null || !_isSupportedLocale(currentLocale)) {
      changeLocale(defaultLocale);
    }
  }

  static bool _useCachedLocale() {
    final cachedLocale = _getCachedLocale();
    log('LocalizationService::_useCachedLocale: Cached locale is $cachedLocale');
    if (cachedLocale != null && _isSupportedLocale(cachedLocale)) {
      changeLocale(cachedLocale);
      return true;
    }
    return false;
  }

  static bool _useServerLocale({
    required String languageCode,
    required OnServerLanguageApplied? onServerLanguageApplied,
  }) {
    final serverLocale = _findSupportedLocale(languageCode);
    log('LocalizationService::_useServerLocale: Server locale is $serverLocale');
    if (serverLocale != null && _isSupportedLocale(serverLocale)) {
      changeLocale(serverLocale);
      onServerLanguageApplied?.call(serverLocale);
      return true;
    }
    return false;
  }

  static bool _isSupportedLocale(Locale locale) {
    return supportedLocales
        .any((supported) => supported.languageCode == locale.languageCode);
  }

  static Locale? _findSupportedLocale(String languageCode) {
    return supportedLocales.firstWhereOrNull(
        (supported) => supported.languageCode == languageCode);
  }

  @override
  Map<String, Map<String, String>> get keys => {};
}
