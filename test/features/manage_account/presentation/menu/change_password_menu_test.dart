import 'package:core/presentation/resources/image_paths.dart';
import 'package:core/presentation/utils/responsive_utils.dart';
import 'package:core/utils/platform_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:jmap_dart_client/jmap/account_id.dart';
import 'package:jmap_dart_client/jmap/core/id.dart';
import 'package:jmap_dart_client/jmap/quotas/quota.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:tmail_ui_user/features/manage_account/presentation/manage_account_dashboard_controller.dart';
import 'package:tmail_ui_user/features/manage_account/presentation/menu/manage_account_menu_controller.dart';
import 'package:tmail_ui_user/features/manage_account/presentation/menu/manage_account_menu_view.dart';
import 'package:tmail_ui_user/features/manage_account/presentation/menu/settings/settings_controller.dart';
import 'package:tmail_ui_user/features/manage_account/presentation/menu/settings/settings_first_level_view.dart';
import 'package:tmail_ui_user/features/manage_account/presentation/model/account_menu_item.dart';
import 'package:tmail_ui_user/main/localizations/app_localizations_delegate.dart';
import 'package:tmail_ui_user/main/localizations/localization_service.dart';
import 'package:tmail_ui_user/main/utils/app_config.dart';
import 'package:tmail_ui_user/main/utils/twake_app_manager.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/link.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'change_password_menu_test.mocks.dart';

/// Records what url_launcher would open instead of opening it.
class RecordingUrlLauncher extends UrlLauncherPlatform {
  final launches = <({String url, String? windowName})>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launches.add((url: url, windowName: options.webOnlyWindowName));
    return true;
  }
}

/// Redfluent Mail v0.39.3-rf2: "Change password" in the settings menus (web only).
@GenerateNiceMocks([MockSpec<ManageAccountDashBoardController>()])
void main() {
  const changePasswordTile = Key('change-password_account_menu_item_tile');
  const signOutTile = Key('sign-out_account_menu_item_tile');

  late MockManageAccountDashBoardController dashboard;
  late RecordingUrlLauncher launcher;
  late UrlLauncherPlatform originalLauncher;

  setUp(() {
    originalLauncher = UrlLauncherPlatform.instance;
    Get.testMode = true;
    PlatformInfo.isTestingForWeb = true;
    dashboard = MockManageAccountDashBoardController();
    // Get.put/Get.reset run the GetX lifecycle; the mock's fakes would throw.
    when(dashboard.onStart).thenReturn(InternalFinalCallback<void>(callback: () {}));
    when(dashboard.onDelete).thenReturn(InternalFinalCallback<void>(callback: () {}));
    final accountId = Rxn<AccountId>();
    when(dashboard.accountId).thenReturn(accountId);
    when(dashboard.octetsQuota).thenReturn(Rxn<Quota>());
    when(dashboard.accountMenuItemSelected).thenReturn(AccountMenuItem.none.obs);
    when(dashboard.ownEmailAddress).thenReturn('alice@example.com'.obs);
    when(dashboard.twakeAppManager).thenReturn(TwakeAppManager());
    // Like the real getters, the capability flags read accountId (an observable,
    // which the Obx wrappers of the settings list require).
    bool afterSignIn(bool supported) => accountId.value != null && supported;
    when(dashboard.isRuleFilterCapabilitySupported).thenAnswer((_) => afterSignIn(false));
    when(dashboard.isServerSettingsCapabilitySupported).thenAnswer((_) => afterSignIn(false));
    when(dashboard.isForwardCapabilitySupported).thenAnswer((_) => afterSignIn(false));
    when(dashboard.isFcmCapabilitySupported).thenAnswer((_) => afterSignIn(false));
    when(dashboard.isVacationCapabilitySupported).thenAnswer((_) => afterSignIn(true));
    when(dashboard.isLanguageSettingDisplayed).thenAnswer((_) => afterSignIn(true));
    Get.put<ManageAccountDashBoardController>(dashboard);
    Get.put<ResponsiveUtils>(ResponsiveUtils());
    Get.put<ImagePaths>(ImagePaths());
    launcher = RecordingUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
  });

  tearDown(() {
    UrlLauncherPlatform.instance = originalLauncher;
    PlatformInfo.isTestingForWeb = false;
    Get.reset();
  });

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    Locale locale = LocalizationService.defaultLocale,
    Size size = const Size(1440, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(GetMaterialApp(
      locale: locale,
      supportedLocales: LocalizationService.supportedLocales,
      localeResolutionCallback: LocalizationService.resolveLocale,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    ));
    dashboard.accountId.value = AccountId(Id('account-id')); // as after sign-in
    await tester.pumpAndSettle();
  }

  void expectSameTabPasswordPage() {
    expect(launcher.launches, hasLength(1));
    final launch = launcher.launches.single;
    expect(launch.url, Uri.base.resolve('/account/password/').toString());
    expect(Uri.parse(launch.url).path, '/account/password/');
    expect(launch.windowName, '_self');
  }

  test('AppConfig.changePasswordUri is /account/password/ on the webmail origin', () {
    for (final page in [
      'https://mail.example.com/',
      'https://mail.example.com/dashboard?context=inbox#top',
      'https://mail.example.com/settings/language-region',
    ]) {
      expect(
        AppConfig.changePasswordUri(Uri.parse(page)).toString(),
        'https://mail.example.com/account/password/',
      );
    }
  });

  group('Manage account side menu:', () {
    testWidgets('web: the entry sits above "Sign out" and opens the page in the same tab', (tester) async {
      Get.put(ManageAccountMenuController());
      await pump(tester, const ManageAccountMenuView());

      expect(
        find.descendant(of: find.byKey(changePasswordTile), matching: find.text('Change password')),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.byKey(changePasswordTile)).dy,
        lessThan(tester.getTopLeft(find.byKey(signOutTile)).dy),
      );

      await tester.tap(find.byKey(changePasswordTile));
      await tester.pump();

      expectSameTabPasswordPage();
    });

    testWidgets('zh-Hans: the entry reads 修改密码', (tester) async {
      Get.put(ManageAccountMenuController());
      await pump(tester, const ManageAccountMenuView(), locale: LocalizationService.simplifiedChineseLocale);

      expect(
        find.descendant(of: find.byKey(changePasswordTile), matching: find.text('修改密码')),
        findsOneWidget,
      );
      expect(find.text('Change password'), findsNothing);
    });

    // flutter_test's default target platform is Android: not web = the mobile app build.
    testWidgets('not on web (mobile apps): no entry', (tester) async {
      PlatformInfo.isTestingForWeb = false;
      expect(PlatformInfo.isMobile, isTrue);
      Get.put(ManageAccountMenuController());
      await pump(tester, const ManageAccountMenuView());

      expect(find.byKey(changePasswordTile), findsNothing);
      expect(find.byKey(signOutTile), findsOneWidget);
    });
  });

  group('Settings list (narrow screens):', () {
    testWidgets('web: the entry sits above "Sign out" and opens the page in the same tab', (tester) async {
      Get.put(SettingsController());
      await pump(tester, const Scaffold(body: SettingsFirstLevelView()), size: const Size(390, 844));

      final entry = find.text('Change password');
      expect(entry, findsOneWidget);
      expect(
        tester.getTopLeft(entry).dy,
        lessThan(tester.getTopLeft(find.text('Sign out')).dy),
      );

      await tester.ensureVisible(entry); // the list scrolls on a phone-sized screen
      await tester.pumpAndSettle();
      await tester.tap(entry);
      await tester.pump();

      expectSameTabPasswordPage();
    });

    testWidgets('not on web (mobile apps): no entry', (tester) async {
      PlatformInfo.isTestingForWeb = false;
      expect(PlatformInfo.isMobile, isTrue);
      Get.put(SettingsController());
      await pump(tester, const Scaffold(body: SettingsFirstLevelView()), size: const Size(390, 844));

      expect(find.text('Change password'), findsNothing);
      expect(find.text('Sign out'), findsOneWidget);
    });
  });
}
