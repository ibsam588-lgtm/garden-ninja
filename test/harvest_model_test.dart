import 'package:flutter_test/flutter_test.dart';
import 'package:garden_ninja/src/garden/harvest_model.dart';

void main() {
  test('an order pays once on release and picked crops regrow', () {
    final progress = HarvestProgress();
    final round = HarvestRound(progress)..start();
    round.tick(8);
    round.beginGesture();
    for (final crop
        in round.crops.where((c) => c.kind == CropKind.strawberry).take(12)) {
      expect(round.hit(crop.id), isTrue);
      expect(round.hit(crop.id), isFalse);
    }
    expect(progress.coins, 840);
    expect(round.collected, 0);
    final result = round.release();
    expect(result.count, 12);
    expect(result.coins, 180);
    expect(progress.coins, 1020);
    expect(progress.tierOrders, 1);
    expect(round.release().coins, 0);
    expect(round.crops.first.isRipe(round.elapsed), isFalse);
    round.tick(7);
    expect(round.crops.first.isRipe(round.elapsed), isTrue);
  });

  test(
    'unripe and mixed crops stop a chain without taking its valid prefix',
    () {
      final round = HarvestRound(HarvestProgress())..start();
      final ripe = round.crops.firstWhere((c) => c.isRipe(0));
      final green = round.crops.firstWhere((c) => !c.isRipe(0));
      round.beginGesture();
      expect(round.hit(ripe.id), isTrue);
      expect(round.hit(green.id), isFalse);
      expect(round.hit(round.crops.last.id), isFalse);
      expect(round.release().count, 1);
      round.tick(8);
      round.beginGesture();
      expect(round.hit(0), isTrue);
      expect(round.hit(15), isFalse);
      expect(round.release().count, 1);
    },
  );

  test(
    'pause cancels the gesture and freezes time; expiry cannot award a pending chain',
    () {
      final progress = HarvestProgress();
      final round = HarvestRound(progress)..start();
      round.hit(0);
      round.pause();
      round.tick(100);
      expect(round.secondsLeft, 60);
      expect(round.chain, isEmpty);
      expect(round.release().coins, 0);
      round.resume();
      round.tick(59);
      round.beginGesture();
      for (var i = 0; i < 12; i++) {
        round.hit(i);
      }
      round.tick(2);
      expect(round.finished, isTrue);
      expect(round.secondsLeft, 0);
      expect(round.release().coins, 0);
      expect(progress.coins, 840);
    },
  );

  test(
    'crop selection affects orders and greenhouse actually unlocks blueberries',
    () {
      final progress = HarvestProgress(coins: 3000);
      expect(progress.plant(0, CropKind.blueberry), isFalse);
      expect(progress.buyUpgrade(GardenUpgrade.greenhouse), isTrue);
      expect(progress.plant(0, CropKind.blueberry), isTrue);
      expect(progress.plant(4, CropKind.tomato), isFalse);
      expect(progress.buyUpgrade(GardenUpgrade.terrace), isTrue);
      expect(progress.bedCount, 6);
      expect(progress.plant(4, CropKind.tomato), isTrue);
      final round = HarvestRound(progress);
      expect(round.crops.length, 30);
      expect(round.orderKind, CropKind.blueberry);
      expect(round.orderReward, greaterThan(180));
    },
  );

  test(
    'upgraded beds double yield without inflating the gesture chain count',
    () {
      final progress = HarvestProgress(coins: 500);
      expect(progress.improveBed(0), isTrue);
      final round = HarvestRound(progress)..start();
      round.tick(8);
      round.beginGesture();
      round.hit(0);
      expect(round.release().count, 1);
      expect(round.collected, 2);
      expect(round.bestChain, 1);
    },
  );

  test(
    'purchases cannot charge twice, overdraft, or target an unavailable bed',
    () {
      final progress = HarvestProgress(coins: 899);
      expect(progress.buyUpgrade(GardenUpgrade.greenhouse), isFalse);
      expect(progress.coins, 899);
      progress.coins = 900;
      expect(progress.buyUpgrade(GardenUpgrade.greenhouse), isTrue);
      expect(progress.coins, 0);
      expect(progress.buyUpgrade(GardenUpgrade.greenhouse), isFalse);
      expect(progress.improveBed(0), isFalse);
      expect(progress.improveBed(-1), isFalse);
      expect(progress.plant(42, CropKind.tomato), isFalse);
    },
  );

  test(
    'advancing requires every objective and preserves permanent ownership',
    () {
      final progress = HarvestProgress(coins: 10000);
      expect(progress.advanceTier(), isFalse);
      progress.buyUpgrade(GardenUpgrade.greenhouse);
      progress.buyUpgrade(GardenUpgrade.terrace);
      for (var i = 0; i < 4; i++) {
        progress.improveBed(i);
      }
      expect(progress.advanceTier(), isFalse);
      progress.tierOrders = progress.targetOrders;
      progress.totalOrders = 9;
      progress.bestChain = 7;
      final previousCoins = progress.coins;
      expect(progress.tierProgress, 1);
      expect(progress.advanceTier(), isTrue);
      expect(progress.coins, previousCoins - 400);
      expect(progress.tier, 2);
      expect(progress.tierOrders, 0);
      expect(progress.totalOrders, 9);
      expect(progress.bestChain, 7);
      expect(progress.beds, everyElement(1));
      expect(progress.rareCropsUnlocked, isTrue);
      expect(progress.bedCount, 6);
      expect(progress.greenhouse, 1);
      expect(progress.ownsUpgrade(GardenUpgrade.greenhouse), isFalse);
      expect(HarvestRound(progress).orderTarget, 14);
      expect(progress.advanceTier(), isFalse);
    },
  );

  test('all six tiers are completable and the estate has a bounded ending', () {
    final progress = HarvestProgress(coins: 100000);
    for (var tier = 1; tier <= 6; tier++) {
      expect(progress.tier, tier);
      progress.buyUpgrade(GardenUpgrade.greenhouse);
      progress.buyUpgrade(GardenUpgrade.terrace);
      for (var i = 0; i < 4; i++) {
        progress.improveBed(i);
      }
      progress.tierOrders = progress.targetOrders;
      expect(progress.tierComplete, isTrue);
      expect(progress.advanceTier(), tier < 6);
    }
    expect(progress.tierName, 'Grand Estate');
    expect(progress.finalTier, isTrue);
  });

  test('progress roundtrips and malformed saves are bounded', () {
    final progress = HarvestProgress(coins: 5000)
      ..tier = 3
      ..greenhouse = 2
      ..terrace = 2
      ..tierOrders = 4
      ..bestChain = 9;
    progress.plant(0, CropKind.blueberry);
    progress.improveBed(0);
    final restored = HarvestProgress.fromJson(
      progress.toJson(),
      coins: progress.coins,
    );
    expect(restored.toJson(), progress.toJson());
    expect(restored.coins, progress.coins);
    final bad = HarvestProgress.fromJson({
      'tier': 400,
      'greenhouse': -4,
      'beds': [9, 'bad'],
      'crops': ['blueberry', 'alien'],
      'tierOrders': double.nan,
    }, coins: -20);
    expect(bad.tier, 6);
    expect(bad.greenhouse, 0);
    expect(bad.coins, 0);
    expect(bad.beds.first, 2);
    expect(bad.crops.first, CropKind.strawberry);
    expect(bad.tierOrders, 0);
    expect(HarvestProgress.fromJson('broken').tier, 1);
  });
}
