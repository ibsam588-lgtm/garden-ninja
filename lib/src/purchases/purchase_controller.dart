import 'dart:async';

import 'package:flutter/foundation.dart';

const removeAdsProductId = 'garden_ninja_remove_ads';

class StoreProduct {
  const StoreProduct({required this.id, required this.price});
  final String id;
  final String price;
}

enum StoreUpdate { pending, owned, cancelled, failed }

enum StoreOwnership { unowned, pending, owned }

abstract class PurchaseGateway {
  bool get supported;
  Stream<StoreUpdate> get updates;
  Future<bool> cachedOwnership();
  Future<StoreProduct?> loadProduct();
  Future<StoreOwnership> queryOwnership();
  Future<void> buy();
  Future<StoreOwnership> restore();
  Future<void> dispose();
}

/// Entitlement comes from the store gateway, never the game's editable save.
class PurchaseController extends ChangeNotifier {
  PurchaseController(this.gateway);

  final PurchaseGateway gateway;
  StreamSubscription<StoreUpdate>? _subscription;
  Future<void>? _initialization;
  Future<void>? _refresh;
  Timer? _purchaseTimeout;
  bool _disposed = false;
  int _ownershipRevision = 0;
  bool checking = true;
  bool busy = false;
  bool pending = false;
  bool ownsRemoveAds = false;
  StoreProduct? product;
  String? message;

  bool get supported => gateway.supported;
  bool get automaticAdsSuppressed => checking || busy || ownsRemoveAds;
  bool get canBuy =>
      product != null && !checking && !busy && !pending && !ownsRemoveAds;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    if (!supported) {
      checking = false;
      _notify();
      return;
    }
    _subscription = gateway.updates.listen(
      _onUpdate,
      onError: (Object _) {
        busy = false;
        message = 'The store could not finish this request. Please try again.';
        _notify();
      },
    );
    try {
      try {
        ownsRemoveAds = await gateway.cachedOwnership().timeout(
          const Duration(seconds: 15),
        );
      } catch (_) {
        // Cache errors must not prevent an authoritative store lookup.
      }
      if (_disposed) return;
      _notify();
      final revision = _ownershipRevision;
      try {
        final ownership = await gateway.queryOwnership().timeout(
          const Duration(seconds: 15),
        );
        if (_disposed) return;
        if (revision == _ownershipRevision) _applyOwnership(ownership);
      } catch (_) {
        // Preserve only previously verified ownership while offline.
        message = 'The store is unavailable. Please try again later.';
      }
      if (_disposed) return;
      product = await gateway.loadProduct().timeout(
        const Duration(seconds: 15),
      );
      if (product == null && !ownsRemoveAds) {
        message =
            'Purchases are unavailable right now. Please try again later.';
      }
    } catch (_) {
      // Keep only a cryptographically verified cached entitlement when offline.
      message =
          'The store is unavailable. Existing verified purchases stay restored.';
    } finally {
      checking = false;
      _notify();
    }
  }

  void _onUpdate(StoreUpdate update) {
    if (_disposed) return;
    _ownershipRevision++;
    _purchaseTimeout?.cancel();
    busy = false;
    pending = update == StoreUpdate.pending;
    switch (update) {
      case StoreUpdate.owned:
        ownsRemoveAds = true;
        message = 'Ads removed. Enjoy your garden!';
      case StoreUpdate.pending:
        message =
            'Payment is pending. Ads will be removed after the store confirms it.';
      case StoreUpdate.cancelled:
        message = 'Purchase cancelled.';
      case StoreUpdate.failed:
        message =
            'Your purchase could not be verified. Please use Restore Purchases or try again.';
    }
    _notify();
    if (update == StoreUpdate.failed && ownsRemoveAds) {
      unawaited(refresh());
    }
  }

  Future<void> buy() async {
    if (_disposed || !canBuy) return;
    busy = true;
    message = null;
    _purchaseTimeout = Timer(const Duration(seconds: 90), () {
      busy = false;
      pending = true;
      message =
          'The store is still confirming your request. Use Restore Purchases to check it.';
      _notify();
    });
    _notify();
    try {
      await gateway.buy();
      // Android returns after opening Play's sheet. Its purchase stream decides
      // owned/cancelled/pending; launching a sheet never grants the product.
    } catch (_) {
      _purchaseTimeout?.cancel();
      busy = false;
      message = 'The purchase could not start. Please try again.';
      _notify();
    }
  }

  Future<void> restore() async {
    if (_disposed || !supported || busy || checking) return;
    busy = true;
    message = null;
    _notify();
    try {
      final revision = _ownershipRevision;
      final ownership = await gateway.restore().timeout(
        const Duration(seconds: 45),
      );
      if (_disposed) return;
      if (revision == _ownershipRevision) _applyOwnership(ownership);
      message = ownsRemoveAds
          ? 'Purchase restored. Automatic ads are removed.'
          : pending
          ? 'Payment is still pending confirmation from the store.'
          : 'No Remove Ads purchase was found on this store account.';
      if (!ownsRemoveAds) {
        product ??= await gateway.loadProduct().timeout(
          const Duration(seconds: 15),
        );
      }
    } catch (_) {
      message = 'Restore could not reach the store. Please try again.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> refresh() =>
      _refresh ??= _refreshOwnership().whenComplete(() => _refresh = null);

  Future<void> _refreshOwnership() async {
    if (_disposed || !supported || checking || busy) return;
    try {
      // A successful empty result revokes a refunded/account-switched purchase.
      final revision = _ownershipRevision;
      final ownership = await gateway.queryOwnership().timeout(
        const Duration(seconds: 15),
      );
      if (_disposed) return;
      if (revision == _ownershipRevision) _applyOwnership(ownership);
      _notify();
      if (!ownsRemoveAds) {
        product ??= await gateway.loadProduct().timeout(
          const Duration(seconds: 15),
        );
      }
      _notify();
    } catch (_) {
      // Temporary network failure is not evidence that a paid entitlement ended.
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _applyOwnership(StoreOwnership ownership) {
    ownsRemoveAds = ownership == StoreOwnership.owned;
    pending = ownership == StoreOwnership.pending;
    if (ownsRemoveAds && message?.startsWith('Payment') == true) {
      message = 'Ads removed. Enjoy your garden!';
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _purchaseTimeout?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(gateway.dispose());
    super.dispose();
  }
}
