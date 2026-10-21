import 'dart:async';
import 'package:dclash_flutter/platform/core_lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'a stop during delayed start wins and transitions remain serial',
    () async {
      final gate = Completer<void>();
      final transitions = <bool>[];
      var active = 0, maxActive = 0, cancellations = 0;
      final lifecycle = CoreLifecycle(
        cancelStart: () => cancellations++,
        apply: (running, revision) async {
          active++;
          if (active > maxActive) maxActive = active;
          transitions.add(running);
          if (running) await gate.future;
          active--;
        },
      );
      final first = lifecycle.request(true);
      final last = lifecycle.request(false);
      gate.complete();
      await Future.wait([first, last]);
      expect(transitions, [true, false]);
      expect(maxActive, 1);
      expect(cancellations, 1);
      expect(lifecycle.desired, false);
    },
  );
  test(
    'start stop start converges to latest intent even after stale failure',
    () async {
      final gate = Completer<void>();
      final transitions = <bool>[];
      final lifecycle = CoreLifecycle(
        apply: (running, revision) async {
          transitions.add(running);
          if (revision == 1) {
            await gate.future;
            throw StateError('superseded start');
          }
        },
      );
      final first = lifecycle.request(true);
      unawaited(lifecycle.request(false));
      final latest = lifecycle.request(true);
      gate.complete();
      await Future.wait([first, latest]);
      expect(transitions, [true, true]);
      expect(lifecycle.desired, true);
    },
  );
  test('current failure reaches caller and next request can recover', () async {
    var fail = true;
    final lifecycle = CoreLifecycle(
      apply: (_, _) async {
        if (fail) throw StateError('missing binary');
      },
    );
    await expectLater(lifecycle.request(true), throwsStateError);
    fail = false;
    await lifecycle.request(false);
    await lifecycle.close();
    await expectLater(lifecycle.request(true), throwsStateError);
  });
}
