import 'package:flutter_test/flutter_test.dart';
import 'package:garden_ninja/src/ads/ad_placement_config.dart';

void main() {
  test('shop rewarded placement grants 300 points', () {
    expect(RewardedAdPlacement.shop.levelPlayName, 'shop_bonus_300');
    expect(RewardedAdPlacement.shop.pointReward, 300);
    expect(RewardedAdPlacement.shop.energyReward, 0);
  });

  test('level complete rewarded placement grants points and energy', () {
    expect(
      RewardedAdPlacement.levelComplete.levelPlayName,
      'level_complete_bonus_150_energy',
    );
    expect(RewardedAdPlacement.levelComplete.pointReward, 150);
    expect(RewardedAdPlacement.levelComplete.energyReward, 1);
  });
}
