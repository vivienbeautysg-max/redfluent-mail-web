import 'dart:async';

// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmail_ui_user/features/push_notification/domain/state/web_socket_push_state.dart';
import 'package:tmail_ui_user/features/push_notification/presentation/controller/web_socket_controller.dart';
import 'package:tmail_ui_user/features/push_notification/presentation/websocket/push_fallback_poller.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A page whose visibility the test flips; [onActive] counts its live listeners.
class FakePageVisibility implements PageVisibilitySource {
  bool visible = true;
  final _listeners = <MultiStreamController<void>>[];

  int get activeListeners => _listeners.length;

  @override
  bool get isVisible => visible;

  @override
  Stream<void> get onActive => Stream<void>.multi((controller) {
        _listeners.add(controller);
        controller.onCancel = () => _listeners.remove(controller);
      });

  /// The tab became visible or the window gained focus.
  void becomeActive() {
    for (final listener in List.of(_listeners)) {
      listener.addSync(null);
    }
  }
}

class FakeWebSocketSink extends Fake implements WebSocketSink {
  @override
  void add(dynamic data) {}

  @override
  Future<dynamic> close([int? closeCode, String? closeReason]) async {}
}

/// A push socket that is connected and stays open.
class FakeWebSocketChannel extends Fake implements WebSocketChannel {
  final _messages = StreamController<dynamic>.broadcast();

  @override
  Stream<dynamic> get stream => _messages.stream;

  @override
  WebSocketSink get sink => FakeWebSocketSink();
}

/// Redfluent Mail v0.39.3-rf10: without WebSocket push the web client refreshes by itself.
void main() {
  late FakePageVisibility page;
  late bool pushActive;
  late int refreshes;
  late Object? refreshError;
  late PushFallbackPoller poller;

  setUp(() {
    page = FakePageVisibility();
    pushActive = false;
    refreshes = 0;
    refreshError = null;
    poller = PushFallbackPoller(
      isPushActive: () => pushActive,
      refresh: () {
        refreshes++;
        if (refreshError != null) throw refreshError!;
      },
      visibility: page,
    );
  });

  tearDown(() => poller.stop());

  void runFake(void Function(FakeAsync async) body) => fakeAsync(body);

  group('PushFallbackPoller', () {
    test('polls every 30 s while the tab is visible and push is not active', () {
      runFake((async) {
        poller.start();

        async.elapse(const Duration(seconds: 29));
        expect(refreshes, 0, reason: 'nothing before the first interval');
        async.elapse(const Duration(seconds: 1));
        expect(refreshes, 1);
        async.elapse(const Duration(seconds: 30));
        expect(refreshes, 2);
        async.elapse(const Duration(minutes: 2));
        expect(refreshes, 6);
      });
    });

    test('does not refresh at start: the first poll is one interval later', () {
      runFake((async) {
        poller.start();
        async.flushMicrotasks();
        expect(refreshes, 0);
      });
    });

    test('does nothing while push is active, however long and however often the tab comes back', () {
      runFake((async) {
        pushActive = true;
        poller.start();

        async.elapse(const Duration(minutes: 5));
        page.becomeActive();
        async.elapse(const Duration(seconds: 6));
        page.becomeActive();

        expect(refreshes, 0);
      });
    });

    test('starts polling when the push socket gave up (push turns inactive)', () {
      runFake((async) {
        pushActive = true;
        poller.start();
        async.elapse(const Duration(seconds: 90));
        expect(refreshes, 0);

        pushActive = false;
        async.elapse(const Duration(seconds: 30));
        expect(refreshes, 1);
      });
    });

    test('stops polling again when push connects', () {
      runFake((async) {
        poller.start();
        async.elapse(const Duration(seconds: 30));
        expect(refreshes, 1);

        pushActive = true;
        async.elapse(const Duration(minutes: 3));
        expect(refreshes, 1);
      });
    });

    test('sends nothing while the tab is hidden, then polls again when it is visible', () {
      runFake((async) {
        page.visible = false;
        poller.start();

        async.elapse(const Duration(seconds: 100));
        expect(refreshes, 0, reason: 'three intervals passed while hidden');
        page.becomeActive();
        expect(refreshes, 0, reason: 'a focus or visibility event of a hidden tab is ignored');

        page.visible = true;
        async.elapse(const Duration(seconds: 20));
        expect(refreshes, 1, reason: 'the interval at 120 s');
      });
    });

    test('refreshes at once when the tab becomes active, at most once per 5 s', () {
      runFake((async) {
        poller.start();
        async.elapse(const Duration(seconds: 10));

        page.becomeActive();
        expect(refreshes, 1, reason: 'immediate, no waiting for the interval');

        page.becomeActive();
        async.elapse(const Duration(seconds: 4));
        page.becomeActive();
        expect(refreshes, 1, reason: 'still inside the 5 s gap');

        async.elapse(const Duration(seconds: 1));
        page.becomeActive();
        expect(refreshes, 2, reason: '5 s after the last refresh');
      });
    });

    test('a visibility event and a focus event together make one refresh', () {
      runFake((async) {
        poller.start();
        page.becomeActive(); // visibilitychange
        page.becomeActive(); // focus
        expect(refreshes, 1);
      });
    });

    test('an interval right after an immediate refresh is skipped', () {
      runFake((async) {
        poller.start();
        async.elapse(const Duration(seconds: 27));
        page.becomeActive();
        expect(refreshes, 1);

        async.elapse(const Duration(seconds: 3));
        expect(refreshes, 1, reason: 'the 30 s tick came 3 s after a refresh');
        async.elapse(const Duration(seconds: 30));
        expect(refreshes, 2);
      });
    });

    test('stop cancels the interval, the gap timer and the page listener', () {
      runFake((async) {
        poller.start();
        page.becomeActive();
        expect(async.periodicTimerCount, 1);
        expect(async.nonPeriodicTimerCount, 1, reason: 'the 5 s gap after the refresh');
        expect(page.activeListeners, 1);

        poller.stop();

        expect(poller.isRunning, isFalse);
        expect(async.periodicTimerCount, 0);
        expect(async.nonPeriodicTimerCount, 0);
        expect(page.activeListeners, 0);
        async.elapse(const Duration(minutes: 5));
        page.becomeActive();
        expect(refreshes, 1, reason: 'only the refresh before stop');
      });
    });

    test('start twice keeps one interval timer and one page listener', () {
      runFake((async) {
        poller.start();
        poller.start();

        expect(async.periodicTimerCount, 1);
        expect(page.activeListeners, 1);
        async.elapse(const Duration(seconds: 30));
        expect(refreshes, 1);
      });
    });

    test('stop, then start again (sign out, sign in) leaves one timer and one listener', () {
      runFake((async) {
        poller.start();
        poller.stop();
        poller.stop();
        poller.start();

        expect(async.periodicTimerCount, 1);
        expect(page.activeListeners, 1);
        async.elapse(const Duration(seconds: 30));
        expect(refreshes, 1);
      });
    });

    test('a refresh that throws does not end the polling', () {
      runFake((async) {
        refreshError = StateError('boom');
        poller.start();

        async.elapse(const Duration(seconds: 30));
        async.elapse(const Duration(seconds: 30));

        expect(refreshes, 2);
        expect(poller.isRunning, isTrue);
      });
    });
  });

  group('WebSocketController.isPushActive', () {
    final controller = WebSocketController.instance;

    // handleSuccessViewState reads AppConfig.isWebSocketEchoPingEnabled (env.file)
    setUpAll(() => dotenv.testLoad(fileInput: 'WS_ECHO_PING='));
    tearDown(controller.onClose);

    test('is false until a push socket is connected (capability missing: initialize is never called)', () {
      expect(controller.isPushActive, isFalse);
    });

    test('is true while the socket is connected, false once it closed or the controller is closed', () {
      controller.handleSuccessViewState(WebSocketConnectionSuccess(FakeWebSocketChannel()));
      expect(controller.isPushActive, isTrue);

      // the socket ended: WebSocketController drops it and retries (here there is no interactor to retry with)
      controller.handleFailureViewState(WebSocketConnectionFailed());
      expect(controller.isPushActive, isFalse);

      controller.handleSuccessViewState(WebSocketConnectionSuccess(FakeWebSocketChannel()));
      expect(controller.isPushActive, isTrue);
      controller.onClose(); // sign out
      expect(controller.isPushActive, isFalse);
    });
  });
}
