import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_ninja/src/purchases/purchase_controller.dart';
import 'package:garden_ninja/src/purchases/remove_ads_panel.dart';

class FakeStore implements PurchaseGateway {
  final events = StreamController<StoreUpdate>.broadcast(sync: true);
  bool cached = false;
  StoreOwnership ownership = StoreOwnership.unowned;
  StoreProduct? product = const StoreProduct(
    id: removeAdsProductId,
    price: '€2,99',
  );
  bool offline = false;
  bool productError = false;
  int buys = 0;
  int queries = 0;
  Completer<StoreOwnership>? delayedQuery;
  Completer<bool>? delayedCache;
  bool closed = false;
  @override
  bool get supported => true;
  @override
  Stream<StoreUpdate> get updates => events.stream;
  @override
  Future<bool> cachedOwnership() async => delayedCache?.future ?? cached;
  @override
  Future<StoreProduct?> loadProduct() async {
    if (productError) throw StateError('Product unavailable');
    return product;
  }

  @override
  Future<StoreOwnership> queryOwnership() async {
    queries++;
    if (offline) throw StateError('Offline');
    return delayedQuery?.future ?? ownership;
  }

  @override
  Future<void> buy() async => buys++;
  @override
  Future<StoreOwnership> restore() => queryOwnership();
  @override
  Future<void> dispose() async {
    closed = true;
    await events.close();
  }
}

void main() {
  late FakeStore store;
  late PurchaseController purchases;
  setUp(() {
    store = FakeStore();
    purchases = PurchaseController(store);
  });
  tearDown(() => purchases.dispose());

  test(
    'startup gates automatic ads until store ownership is checked',
    () async {
      expect(purchases.automaticAdsSuppressed, isTrue);
      await purchases.initialize();
      expect(purchases.automaticAdsSuppressed, isFalse);
      expect(purchases.canBuy, isTrue);
      expect(store.queries, 1);
    },
  );

  test(
    'opening the payment sheet grants nothing and blocks duplicate buys',
    () async {
      await purchases.initialize();
      await purchases.buy();
      await purchases.buy();
      expect(store.buys, 1);
      expect(purchases.ownsRemoveAds, isFalse);
      expect(purchases.automaticAdsSuppressed, isTrue);
      store.events.add(StoreUpdate.cancelled);
      expect(purchases.canBuy, isTrue);
      expect(purchases.automaticAdsSuppressed, isFalse);
    },
  );

  test('pending and failed payments never grant ad removal', () async {
    await purchases.initialize();
    await purchases.buy();
    store.events.add(StoreUpdate.pending);
    expect(purchases.pending, isTrue);
    expect(purchases.canBuy, isFalse);
    expect(purchases.ownsRemoveAds, isFalse);
    expect(purchases.automaticAdsSuppressed, isFalse);
    store.events.add(StoreUpdate.failed);
    expect(purchases.canBuy, isTrue);
    expect(purchases.ownsRemoveAds, isFalse);
  });

  test(
    'verified purchase suppresses automatic ads and cannot be bought again',
    () async {
      await purchases.initialize();
      await purchases.buy();
      store.events.add(StoreUpdate.owned);
      expect(purchases.ownsRemoveAds, isTrue);
      expect(purchases.automaticAdsSuppressed, isTrue);
      await purchases.buy();
      expect(store.buys, 1);
    },
  );

  test(
    'restore works even when the store product listing is unavailable',
    () async {
      store.product = null;
      await purchases.initialize();
      expect(purchases.canBuy, isFalse);
      store.ownership = StoreOwnership.owned;
      store.productError = true;
      await purchases.restore();
      expect(purchases.ownsRemoveAds, isTrue);
      expect(purchases.message, contains('restored'));
    },
  );

  test(
    'refund or account switch revokes ownership on a successful lookup',
    () async {
      store.cached = true;
      store.ownership = StoreOwnership.owned;
      await purchases.initialize();
      store.ownership = StoreOwnership.unowned;
      await purchases.refresh();
      expect(purchases.ownsRemoveAds, isFalse);
      expect(purchases.automaticAdsSuppressed, isFalse);
      await purchases.restore();
      expect(purchases.message, contains('No Remove Ads purchase'));
    },
  );

  test(
    'offline lookup preserves only previously verified cached ownership',
    () async {
      store.cached = true;
      store.offline = true;
      await purchases.initialize();
      expect(purchases.ownsRemoveAds, isTrue);
      await purchases.refresh();
      expect(purchases.ownsRemoveAds, isTrue);
      await purchases.restore();
      expect(purchases.ownsRemoveAds, isTrue);
    },
  );

  test(
    'missing product metadata does not skip authoritative refund checks',
    () async {
      store.cached = true;
      store.productError = true;
      await purchases.initialize();
      expect(store.queries, 1);
      expect(purchases.ownsRemoveAds, isFalse);
      expect(purchases.checking, isFalse);
    },
  );

  test(
    'a stale lookup cannot overwrite a newer verified purchase event',
    () async {
      await purchases.initialize();
      store.delayedQuery = Completer<StoreOwnership>();
      final refresh = purchases.refresh();
      store.events.add(StoreUpdate.owned);
      store.delayedQuery!.complete(StoreOwnership.unowned);
      await refresh;
      expect(purchases.ownsRemoveAds, isTrue);
    },
  );

  test('disposing during initialization does not reopen the store', () async {
    final otherStore = FakeStore()..delayedCache = Completer<bool>();
    final other = PurchaseController(otherStore);
    final initialization = other.initialize();
    other.dispose();
    otherStore.delayedCache!.complete(false);
    await initialization;
    expect(otherStore.closed, isTrue);
    expect(otherStore.queries, 0);
  });

  test('an old cache response cannot undo a verified payment', () async {
    store.delayedCache = Completer<bool>();
    store.offline = true;
    final initialization = purchases.initialize();
    store.events.add(StoreUpdate.owned);
    store.delayedCache!.complete(false);
    await initialization;
    expect(purchases.ownsRemoveAds, isTrue);
  });

  testWidgets(
    'small-phone panel shows localized price, restore and paid state',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await purchases.initialize();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RemoveAdsPanel(purchases: purchases),
            ),
          ),
        ),
      );
      expect(find.text('Remove Ads · €2,99'), findsOneWidget);
      expect(find.text('Restore Purchases'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('buy-remove-ads')));
      await tester.pump();
      store.events.add(StoreUpdate.pending);
      await tester.pump();
      expect(find.text('Payment pending'), findsOneWidget);
      store.events.add(StoreUpdate.owned);
      await tester.pump();
      expect(find.byKey(const ValueKey('remove-ads-owned')), findsOneWidget);
      expect(find.byKey(const ValueKey('buy-remove-ads')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
