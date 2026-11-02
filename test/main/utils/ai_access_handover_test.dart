import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmap_dart_client/jmap/core/user_name.dart';
import 'package:model/account/authentication_type.dart';
import 'package:model/account/password.dart';
import 'package:tmail_ui_user/features/login/data/local/account_cache_manager.dart';
import 'package:tmail_ui_user/features/login/data/local/token_oidc_cache_manager.dart';
import 'package:tmail_ui_user/features/login/data/network/authentication_client/authentication_client_base.dart';
import 'package:tmail_ui_user/features/login/data/network/interceptors/authorization_interceptors.dart';
import 'package:tmail_ui_user/main/universal_import/html_stub.dart' as html;
import 'package:tmail_ui_user/main/utils/app_config.dart';
import 'package:tmail_ui_user/main/utils/app_utils.dart';
import 'package:tmail_ui_user/main/utils/ios_sharing_manager.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/link.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _FakeAuthenticationClient extends Fake implements AuthenticationClientBase {}

class _FakeTokenOidcCacheManager extends Fake implements TokenOidcCacheManager {}

class _FakeAccountCacheManager extends Fake implements AccountCacheManager {}

class _FakeIOSSharingManager extends Fake implements IOSSharingManager {}

/// Records what url_launcher would open instead of opening it.
class _RecordingUrlLauncher extends UrlLauncherPlatform {
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

/// Redfluent Mail v0.39.3-rf19: "AI access" opens the AI access page already signed in. The webmail hands the
/// page its own Basic header over postMessage (browser part: e2e on the built web app); here the parts that decide
/// what is handed over and when.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const aliceHeader = 'Basic YWxpY2VAZXhhbXBsZS50ZXN0OnRlc3Q='; // alice@example.test:test

  group('AuthorizationInterceptors.basicAuthorizationHeader', () {
    late AuthorizationInterceptors interceptors;

    setUp(() {
      interceptors = AuthorizationInterceptors(
        Dio(),
        _FakeAuthenticationClient(),
        _FakeTokenOidcCacheManager(),
        _FakeAccountCacheManager(),
        _FakeIOSSharingManager(),
      );
    });

    test('is null before signing in', () {
      expect(interceptors.basicAuthorizationHeader, isNull);
    });

    test('is the Basic header of the password sign-in, the one sent with every JMAP request', () {
      interceptors.setBasicAuthorization(UserName('alice@example.test'), Password('test'));
      expect(interceptors.authenticationType, AuthenticationType.basic);
      expect(interceptors.basicAuthorizationHeader, aliceHeader);
      expect(utf8.decode(base64Decode(interceptors.basicAuthorizationHeader!.substring(6))), 'alice@example.test:test');
      final request = RequestOptions(path: 'https://jmap.example.com/jmap');
      interceptors.onRequest(request, RequestInterceptorHandler());
      expect(interceptors.basicAuthorizationHeader, request.headers[HttpHeaders.authorizationHeader]);
    });

    test('keeps a password with a colon and non-ASCII characters whole', () {
      interceptors.setBasicAuthorization(UserName('bob@example.test'), Password('p:ä 1'));
      final header = interceptors.basicAuthorizationHeader!;
      expect(header, startsWith('Basic '));
      expect(utf8.decode(base64Decode(header.substring(6))), 'bob@example.test:p:ä 1');
    });

    test('is null after signing out', () {
      interceptors.setBasicAuthorization(UserName('alice@example.test'), Password('test'));
      interceptors.clear();
      expect(interceptors.basicAuthorizationHeader, isNull);
    });

    test('is null for an OIDC session, even right after a password one', () {
      interceptors.setBasicAuthorization(UserName('alice@example.test'), Password('test'));
      interceptors.setTokenAndAuthorityOidc();
      expect(interceptors.authenticationType, AuthenticationType.oidc);
      expect(interceptors.basicAuthorizationHeader, isNull);
    });
  });

  group('AppUtils.aiAccessHandoverMessage', () {
    test('carries the Basic header and nothing else, as the page expects', () {
      final message = AppUtils.aiAccessHandoverMessage(aliceHeader);
      expect(message, isNotNull);
      expect(jsonDecode(message!), {'type': 'rf-ai-auth', 'authorization': aliceHeader});
      expect(AppUtils.aiAccessAuthType, 'rf-ai-auth');
      expect(AppUtils.aiAccessReadyMessage, 'rf-ai-ready');
    });

    test('is null for anything that is not a Basic header', () {
      final refused = <String?>[
        null,
        '',
        'Basic ',
        'Basic abc',
        'basic YWxpY2VAZXhhbXBsZS50ZXN0OnRlc3Q=',
        'Bearer eyJhbGciOiJSUzI1NiJ9.e30.sig',
        'Basic YWxpY2U6dGVzdA==\r\nX-Other: 1',
        'Basic YWxp Y2U6dGVzdA==',
        ' $aliceHeader',
        'Basic ${'A' * 2049}',
      ];
      for (final value in refused) {
        expect(AppUtils.aiAccessHandoverMessage(value), isNull, reason: '$value');
      }
      expect(AppUtils.aiAccessHandoverMessage('Basic ${'A' * 2048}'), isNotNull);
    });

    test('hands over for a minute at most', () {
      expect(AppUtils.aiAccessHandoverWindow, const Duration(seconds: 60));
    });
  });

  group('openAiAccess outside the browser', () {
    late _RecordingUrlLauncher launcher;
    late UrlLauncherPlatform original;

    setUp(() {
      original = UrlLauncherPlatform.instance;
      launcher = _RecordingUrlLauncher();
      UrlLauncherPlatform.instance = launcher;
      html.window.localStorage.remove(AppUtils.aiAccessEmailKey);
    });

    tearDown(() {
      UrlLauncherPlatform.instance = original;
      html.window.localStorage.remove(AppUtils.aiAccessEmailKey);
    });

    test('with credentials still opens the page once the rf18 way, address prefilled', () async {
      AppUtils.openAiAccess('alice@example.test', aliceHeader);
      await Future<void>.delayed(Duration.zero);
      expect(launcher.launches, [AppConfig.aiAccessUrl()]);
      expect(html.window.localStorage[AppUtils.aiAccessEmailKey], 'alice@example.test');
    });

    test('without credentials opens the page once, as in rf18', () async {
      AppUtils.openAiAccess('alice@example.test');
      await Future<void>.delayed(Duration.zero);
      expect(launcher.launches, [AppConfig.aiAccessUrl()]);
    });
  });
}
