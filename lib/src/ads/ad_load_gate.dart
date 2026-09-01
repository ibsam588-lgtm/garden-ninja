import 'dart:async';

class AdLoadGate {
  AdLoadGate({this.timeout = const Duration(seconds: 25)});

  final Duration timeout;
  Completer<bool>? _pending;
  Timer? _timeoutTimer;
  bool _ready = false;

  bool get isReady => _ready;
  bool get isLoading => _pending != null;

  Future<bool> load(Future<void> Function() requestLoad) {
    if (_ready) {
      return Future<bool>.value(true);
    }

    final Completer<bool>? pending = _pending;
    if (pending != null) {
      return pending.future;
    }

    final Completer<bool> completer = Completer<bool>();
    _pending = completer;
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(timeout, markFailed);
    unawaited(
      Future<void>.sync(requestLoad).catchError((Object _) {
        markFailed();
      }),
    );
    return completer.future;
  }

  void markLoaded() {
    _ready = true;
    _completePending(true);
  }

  void markFailed() {
    _ready = false;
    _completePending(false);
  }

  void consume() {
    _ready = false;
  }

  void dispose() {
    markFailed();
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }

  void _completePending(bool loaded) {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    final Completer<bool>? completer = _pending;
    _pending = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(loaded);
    }
  }
}
