import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'purchase_controller.dart';

class StorePurchaseGateway implements PurchaseGateway {
  static const _verification = MethodChannel(
    'garden_ninja/purchase_verification',
  );
  static const _cacheKey = 'garden_ninja_verified_play_remove_ads_v1';
  final _updates = StreamController<StoreUpdate>.broadcast();
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  Future<void> _queue = Future<void>.value();
  ProductDetails? _product;
  bool _closed = false;

  bool get _android => !kIsWeb && Platform.isAndroid;
  @override
  bool get supported =>
      !kIsWeb &&
      (Platform.isAndroid || Platform.isIOS) &&
      !const bool.fromEnvironment('STORE_SCREENSHOTS');
  @override
  Stream<StoreUpdate> get updates => _updates.stream;

  void _listen() {
    if (_closed) return;
    _subscription ??= InAppPurchase.instance.purchaseStream.listen((purchases) {
      _queue = _queue
          .then<void>((_) async {
            for (final purchase in purchases) {
              if (_closed || purchase.productID != removeAdsProductId) continue;
              await _process(purchase);
            }
          })
          .catchError((Object _) => _emit(StoreUpdate.failed));
    }, onError: (Object _) => _emit(StoreUpdate.failed));
  }

  void _emit(StoreUpdate value) {
    if (!_closed) _updates.add(value);
  }

  @override
  Future<bool> cachedOwnership() async {
    if (_closed || !supported) return false;
    if (!_android) return _appleOwnership();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return false;
    try {
      final proof = jsonDecode(raw) as Map<String, dynamic>;
      return await _verifyPlay(
        proof['data'] as String,
        proof['signature'] as String,
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<StoreProduct?> loadProduct() async {
    if (_closed || !supported) return null;
    _listen();
    if (!await InAppPurchase.instance.isAvailable()) return null;
    final response = await InAppPurchase.instance.queryProductDetails({
      removeAdsProductId,
    });
    if (response.error != null) throw StateError('Product lookup failed');
    _product = response.productDetails
        .where((p) => p.id == removeAdsProductId)
        .firstOrNull;
    return _product == null
        ? null
        : StoreProduct(id: _product!.id, price: _product!.price);
  }

  Future<bool> _verifyPlay(String data, String signature) async =>
      await _verification.invokeMethod<bool>('verifyGooglePurchase', {
        'data': data,
        'signature': signature,
      }) ??
      false;

  Future<bool> _verify(PurchaseDetails purchase) async {
    if (purchase.productID != removeAdsProductId ||
        (purchase.status != PurchaseStatus.purchased &&
            purchase.status != PurchaseStatus.restored)) {
      return false;
    }
    if (_android) {
      if (purchase is! GooglePlayPurchaseDetails) return false;
      return _verifyPlay(
        purchase.billingClientPurchase.originalJson,
        purchase.billingClientPurchase.signature,
      );
    }
    // The endorsed plugin forwards unverified purchase events too. Never trust
    // PurchaseStatus alone: currentEntitlements filters native .verified only.
    final owned = await SK2Transaction.currentEntitlements();
    return owned.any(
      (t) => t.productId == removeAdsProductId && t.id == purchase.purchaseID,
    );
  }

  Future<bool> _appleOwnership() async =>
      (await SK2Transaction.currentEntitlements()).any(
        (t) => t.productId == removeAdsProductId,
      );

  Future<void> _cache(PurchaseDetails purchase) async {
    if (purchase is! GooglePlayPurchaseDetails) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cacheKey,
      jsonEncode({
        'data': purchase.billingClientPurchase.originalJson,
        'signature': purchase.billingClientPurchase.signature,
      }),
    );
  }

  Future<void> _complete(PurchaseDetails purchase) async {
    if (purchase.pendingCompletePurchase) {
      try {
        await InAppPurchase.instance.completePurchase(purchase);
      } catch (_) {
        // A temporary acknowledgement failure does not invalidate verified
        // ownership. The next ownership query/restore retries completion.
      }
    }
  }

  Future<void> _process(PurchaseDetails purchase) async {
    switch (purchase.status) {
      case PurchaseStatus.pending:
        _emit(StoreUpdate.pending);
      case PurchaseStatus.canceled:
        _emit(StoreUpdate.cancelled);
      case PurchaseStatus.error:
        _emit(StoreUpdate.failed);
      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        if (!await _verify(purchase)) {
          _emit(StoreUpdate.failed);
          return;
        }
        await _cache(purchase);
        _emit(StoreUpdate.owned);
        // Never acknowledge an unverified or pending payment. If acknowledgement
        // fails, querying/restoring the owned purchase retries on the next resume.
        await _complete(purchase);
    }
  }

  @override
  Future<StoreOwnership> queryOwnership() async {
    if (_closed || !supported) return StoreOwnership.unowned;
    _listen();
    if (!_android) {
      return await _appleOwnership()
          ? StoreOwnership.owned
          : StoreOwnership.unowned;
    }
    final response = await InAppPurchase.instance
        .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>()
        .queryPastPurchases();
    if (response.error != null) throw StateError('Ownership lookup failed');
    var owned = false;
    var pending = false;
    for (final purchase in response.pastPurchases) {
      if (purchase.productID != removeAdsProductId) continue;
      pending |= purchase.status == PurchaseStatus.pending;
      if (await _verify(purchase)) {
        owned = true;
        await _cache(purchase);
        await _complete(purchase);
      }
    }
    if (!owned) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
    }
    return owned
        ? StoreOwnership.owned
        : pending
        ? StoreOwnership.pending
        : StoreOwnership.unowned;
  }

  @override
  Future<void> buy() async {
    final product = _product;
    if (product == null ||
        !await InAppPurchase.instance.buyNonConsumable(
          purchaseParam: PurchaseParam(productDetails: product),
        )) {
      throw StateError('Purchase sheet unavailable');
    }
  }

  @override
  Future<StoreOwnership> restore() async {
    _listen();
    await InAppPurchase.instance.restorePurchases();
    await _queue;
    return queryOwnership();
  }

  @override
  Future<void> dispose() async {
    _closed = true;
    await _subscription?.cancel();
    await _queue;
    await _updates.close();
  }
}
