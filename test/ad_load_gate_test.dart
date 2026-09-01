import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_ninja/src/ads/ad_load_gate.dart';

void main() {
  test('load waits for the SDK loaded callback', () async {
    final AdLoadGate gate = AdLoadGate();
    bool completed = false;

    final Future<bool> result = gate.load(() async {});
    unawaited(result.then((_) => completed = true));
    await Future<void>.delayed(Duration.zero);

    expect(completed, isFalse);
    expect(gate.isLoading, isTrue);

    gate.markLoaded();

    expect(await result, isTrue);
    expect(gate.isReady, isTrue);
  });

  test('concurrent video requests share one SDK load', () async {
    final AdLoadGate gate = AdLoadGate();
    int requests = 0;

    final Future<bool> first = gate.load(() async => requests += 1);
    final Future<bool> second = gate.load(() async => requests += 1);
    await Future<void>.delayed(Duration.zero);

    expect(requests, 1);

    gate.markLoaded();

    expect(await first, isTrue);
    expect(await second, isTrue);
  });

  test('failed video loads can be retried', () async {
    final AdLoadGate gate = AdLoadGate();
    int requests = 0;

    final Future<bool> first = gate.load(() async => requests += 1);
    await Future<void>.delayed(Duration.zero);
    gate.markFailed();

    expect(await first, isFalse);
    expect(gate.isReady, isFalse);

    final Future<bool> retry = gate.load(() async => requests += 1);
    await Future<void>.delayed(Duration.zero);
    gate.markLoaded();

    expect(await retry, isTrue);
    expect(requests, 2);
  });

  test('consuming a loaded ad requires the next ad to load again', () async {
    final AdLoadGate gate = AdLoadGate();
    int requests = 0;

    final Future<bool> first = gate.load(() async => requests += 1);
    await Future<void>.delayed(Duration.zero);
    gate.markLoaded();
    expect(await first, isTrue);

    gate.consume();
    final Future<bool> second = gate.load(() async => requests += 1);
    await Future<void>.delayed(Duration.zero);
    gate.markLoaded();

    expect(await second, isTrue);
    expect(requests, 2);
  });
}
