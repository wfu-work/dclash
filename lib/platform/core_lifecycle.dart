import 'dart:async';

/// Requests replace intent immediately; one reconciler owns all transitions.
class CoreLifecycle {
  CoreLifecycle({required this.apply, this.cancelStart});
  final Future<void> Function(bool running, int revision) apply;
  final void Function()? cancelStart;
  bool desired = false;
  int revision = 0;
  int appliedRevision = 0;
  Future<void>? _operation;
  bool _closed = false;

  Future<void> request(bool running) {
    if (_closed) return Future.error(StateError('Core lifecycle is closed'));
    desired = running;
    revision++;
    if (!running) cancelStart?.call();
    return _operation ??= _reconcile().whenComplete(() => _operation = null);
  }

  Future<void> _reconcile() async {
    Object? failure;
    StackTrace? stack;
    while (appliedRevision != revision) {
      final current = revision;
      final wanted = desired;
      try {
        await apply(wanted, current);
        failure = null;
      } catch (error, trace) {
        if (current == revision) {
          failure = error;
          stack = trace;
        }
      }
      appliedRevision = current;
    }
    if (failure != null) Error.throwWithStackTrace(failure, stack!);
  }

  Future<void> close() async {
    if (_closed) return;
    await request(false);
    _closed = true;
  }
}
