import 'package:flutter/material.dart';
import 'purchase_controller.dart';

class RemoveAdsPanel extends StatelessWidget {
  const RemoveAdsPanel({required this.purchases, super.key});
  final PurchaseController purchases;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: purchases,
    builder: (context, _) => Card(
      color: const Color(0xFFF5E9C8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  purchases.ownsRemoveAds
                      ? Icons.verified_rounded
                      : Icons.shield_outlined,
                  color: const Color(0xFF376D2A),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    purchases.ownsRemoveAds
                        ? 'Your garden is ad-free'
                        : 'A calmer garden',
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF23411E),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Remove banners and automatic ad breaks with one purchase. Optional rewarded videos stay available.',
              style: TextStyle(color: Color(0xFF334C2C), height: 1.35),
            ),
            const SizedBox(height: 12),
            if (!purchases.ownsRemoveAds)
              FilledButton.icon(
                key: const ValueKey('buy-remove-ads'),
                onPressed: purchases.canBuy ? purchases.buy : null,
                icon: purchases.busy || purchases.checking
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.spa_outlined),
                label: Text(
                  purchases.pending
                      ? 'Payment pending'
                      : purchases.product == null
                      ? purchases.checking
                            ? 'Connecting to store…'
                            : 'Store unavailable'
                      : 'Remove Ads · ${purchases.product!.price}',
                ),
              ),
            if (purchases.ownsRemoveAds)
              const Text(
                'Banners and automatic ad breaks are removed.',
                key: ValueKey('remove-ads-owned'),
                style: TextStyle(
                  color: Color(0xFF376D2A),
                  fontWeight: FontWeight.w800,
                ),
              ),
            TextButton(
              key: const ValueKey('restore-purchases'),
              onPressed: purchases.busy || purchases.checking
                  ? null
                  : purchases.restore,
              child: const Text('Restore Purchases'),
            ),
            if (purchases.message != null)
              Text(
                purchases.message!,
                key: const ValueKey('purchase-status'),
                style: const TextStyle(color: Color(0xFF334C2C)),
              ),
            const SizedBox(height: 6),
            const Text(
              'One-time purchase. Restores with the same store account.',
              style: TextStyle(fontSize: 12, color: Color(0xFF596A4B)),
            ),
          ],
        ),
      ),
    ),
  );
}
