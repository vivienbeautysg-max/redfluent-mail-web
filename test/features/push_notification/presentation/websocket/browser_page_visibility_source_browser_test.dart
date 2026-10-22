@TestOn('chrome')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:tmail_ui_user/features/push_notification/presentation/websocket/push_fallback_poller.dart';
// ignore: depend_on_referenced_packages
import 'package:web/web.dart' as web;

/// Redfluent Mail v0.39.3-rf10: BrowserPageVisibilitySource and PushFallbackPoller on the browser's real
/// `document` and `window` (run with `flutter test --platform chrome`).

/// A headless test tab is always 'visible'; the page's own getter is replaced for the test.
void _setVisibilityState(String state) {
  globalContext.callMethod<JSAny?>(
    'eval'.toJS,
    "Object.defineProperty(document, 'visibilityState', "
            "{configurable: true, get: function () { return '$state'; }});"
        .toJS,
  );
}

void _restoreVisibilityState() {
  globalContext.callMethod<JSAny?>(
    'eval'.toJS,
    "delete document.visibilityState;".toJS,
  );
}

void _fireVisibilityChange() =>
    web.document.dispatchEvent(web.Event('visibilitychange'));

void _fireFocus() => web.window.dispatchEvent(web.Event('focus'));

void main() {
  tearDown(_restoreVisibilityState);

  group('BrowserPageVisibilitySource', () {
    const source = BrowserPageVisibilitySource();

    test('isVisible follows document.visibilityState', () {
      _setVisibilityState('visible');
      expect(source.isVisible, isTrue);
      _setVisibilityState('hidden');
      expect(source.isVisible, isFalse);
    });

    test('onActive fires for a visibilitychange and for a window focus', () async {
      var events = 0;
      final subscription = source.onActive.listen((_) => events++);

      _fireVisibilityChange();
      _fireFocus();
      await Future<void>.delayed(Duration.zero);
      expect(events, 2);

      await subscription.cancel();
      _fireFocus();
      await Future<void>.delayed(Duration.zero);
      expect(events, 2, reason: 'nothing after cancel');
    });
  });

  group('PushFallbackPoller on the real page', () {
    late int refreshes;
    late PushFallbackPoller poller;
    var pushActive = false;

    setUp(() {
      refreshes = 0;
      pushActive = false;
      poller = PushFallbackPoller(
        isPushActive: () => pushActive,
        refresh: () => refreshes++,
        visibility: const BrowserPageVisibilitySource(),
      );
    });

    tearDown(() => poller.stop());

    test('a focus event of the visible tab refreshes once, a second one within 5 s does not', () async {
      _setVisibilityState('visible');
      poller.start();

      _fireFocus();
      _fireVisibilityChange();
      await Future<void>.delayed(Duration.zero);

      expect(refreshes, 1);
    });

    test('nothing while the tab is hidden, nothing while push is active', () async {
      _setVisibilityState('hidden');
      poller.start();
      _fireVisibilityChange();
      _fireFocus();
      await Future<void>.delayed(Duration.zero);
      expect(refreshes, 0);

      _setVisibilityState('visible');
      pushActive = true;
      _fireFocus();
      await Future<void>.delayed(Duration.zero);
      expect(refreshes, 0);
    });

    test('after stop the page events no longer reach refresh', () async {
      _setVisibilityState('visible');
      poller.start();
      poller.stop();

      _fireFocus();
      await Future<void>.delayed(Duration.zero);

      expect(refreshes, 0);
    });
  });
}
