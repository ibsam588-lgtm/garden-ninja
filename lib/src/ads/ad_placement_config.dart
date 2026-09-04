enum RewardedAdPlacement { shop, levelComplete }

extension RewardedAdPlacementConfig on RewardedAdPlacement {
  String get levelPlayName => switch (this) {
    RewardedAdPlacement.shop => 'shop_bonus_300',
    RewardedAdPlacement.levelComplete => 'level_complete_bonus_150_energy',
  };

  int get pointReward => switch (this) {
    RewardedAdPlacement.shop => 300,
    RewardedAdPlacement.levelComplete => 150,
  };

  int get energyReward => switch (this) {
    RewardedAdPlacement.shop => 0,
    RewardedAdPlacement.levelComplete => 1,
  };
}
