import 'dart:async';

import 'package:core/utils/app_logger.dart';
import 'package:rxdart/rxdart.dart';
import 'package:tmail_ui_user/main/universal_import/html_stub.dart' as html;

/// What [PushFallbackPoller] needs to know about the browser page.
abstract class PageVisibilitySource {
  /// The tab is on screen (`document.visibilityState == 'visible'`).
  bool get isVisible;

  /// The tab became visible again, or the window gained focus.
  Stream<void> get onActive;
}

class BrowserPageVisibilitySource implements PageVisibilitySource {
  const BrowserPageVisibilitySource();

  @override
  bool get isVisible => html.document.visibilityState == 'visible';

  @override
  Stream<void> get onActive => MergeStream<void>([
        html.document.onVisibilityChange,
        html.window.onFocus,
      ]);
}

/// Redfluent Mail (rf10): keeps the web mailbox in sync while WebSocket push is not running.
///
/// Stalwart's JMAP session has no `com:linagora:params:jmap:ws:ticket` capability, so
/// `BaseController.injectWebSocket` never starts the push socket and nothing tells the page about new
/// mail or read/unread changes. While the tab is visible and push is not active this calls [refresh]
/// every [pollInterval], and at once (at most once per [minRefreshGap]) when the tab becomes visible or
/// the window gains focus. It sends nothing while the tab is hidden.
class PushFallbackPoller {
  static const Duration pollInterval = Duration(seconds: 30);
  static const Duration minRefreshGap = Duration(seconds: 5);

  /// True while the push socket is connected: push delivers the changes, so there is nothing to poll.
  final bool Function() isPushActive;

  /// What a push StateChange would trigger.
  final void Function() refresh;

  final PageVisibilitySource visibility;

  PushFallbackPoller({
    required this.isPushActive,
    required this.refresh,
    required this.visibility,
  });

  Timer? _pollTimer;
  Timer? _gapTimer;
  StreamSubscription<void>? _activeSubscription;

  bool get isRunning => _pollTimer != null;

  /// Starts polling; calling it again while running does nothing.
  void start() {
    if (isRunning) return;
    log(
      'PushFallbackPoller::start(): every ${pollInterval.inSeconds} s while the tab is visible and push is not active',
      webConsoleEnabled: true,
    );
    _activeSubscription = visibility.onActive.listen((_) => _refreshIfNeeded());
    _pollTimer = Timer.periodic(pollInterval, (_) => _refreshIfNeeded());
  }

  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _gapTimer?.cancel();
    _gapTimer = null;
    _activeSubscription?.cancel();
    _activeSubscription = null;
  }

  void _refreshIfNeeded() {
    if (!visibility.isVisible || isPushActive() || _gapTimer != null) return;
    _gapTimer = Timer(minRefreshGap, () => _gapTimer = null);
    log('PushFallbackPoller::_refreshIfNeeded(): refreshing, push is not active');
    try {
      refresh();
    } catch (e) {
      logWarning('PushFallbackPoller::_refreshIfNeeded(): $e');
    }
  }
}
