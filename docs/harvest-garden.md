# Harvest garden

The implementation follows the approved [harvest mockup](mockups/garden_mockup_k_harvest_mastery.png): a mature isometric stone courtyard, olive HUD, amber swipe trails, one market order and two illustrated upgrade choices. The user's subsequent request adds six garden tiers and a repeatable upgrade-and-begin-again progression.

## Playing

Plant chooses a crop for each bed. The plant picker includes a live courtyard map, an immediate `BED N SELECTED` label, and a bright selected plot, so all four starting beds and both terrace beds remain identifiable even when the picker covers the courtyard. Grouping a crop makes it easier to trace long matching chains. Strawberries and tomatoes begin unlocked. Greenhouse levels add blueberries, pumpkins, eggplants and golden peppers. Four beds are available initially and the terrace adds two.

Start harvest begins a 60-second challenge. Drag through matching ripe plants, then release. Each selected plant counts once. Green fruit or a different crop stops further selection for that gesture; the valid prefix is still gathered on release. Cancellation or pausing discards the uncommitted gesture. Plants remain rooted and regrow in seconds. Taps and semantic accessibility actions collect individual plants. Crop touch areas are larger than their artwork, and a looping Demo panel animates the exact connect-and-release gesture before the player starts.

Orders only request crops actually planted. Completed orders pay automatically and save immediately. The next order rotates between planted crop types when the current order has no overflow. Improved beds yield two crops per target. A round can finish early through Pause → Finish harvest; completed earnings remain. App backgrounding or a forced update pauses the challenge, with explicit resume.

The home garden is untimed. Replays replenish the crop board without energy or waiting. Progress is a design loop rather than a measured retention claim; reward and pacing values should be tuned through playtesting.

## Garden tiers

| Tier | Garden | Order quantity | Base order coins | Each landmark upgrade | Each bed improvement | Advance cost |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Stone Courtyard | 12 | 180 | 900 | 120 | 400 |
| 2 | Sunlit Orchard | 14 | 220 | 1,250 | 180 | 600 |
| 3 | Autumn Retreat | 16 | 260 | 1,600 | 240 | 800 |
| 4 | Walled Conservatory | 18 | 300 | 1,950 | 300 | 1,000 |
| 5 | Mountain Garden | 20 | 340 | 2,300 | 360 | 1,200 |
| 6 | Grand Estate | 22 | 380 | 2,650 | 420 | Final tier |

Advancement requires greenhouse and terrace levels matching the current tier, the four main beds improved to level 2, and `tier + 2` completed orders. The progression sheet links directly to unfinished work. The final estate remains playable after completion.

On advancing, bed improvements return to level 1, planting is reset with the newest unlocked crop, and the tier order count starts over. Coins, both landmarks, the terrace's extra beds, unlocked crops and lifetime records persist. Each greenhouse and terrace level uses a visibly different building design. Higher greenhouse levels unlock new crops and improve rare-crop rewards; terrace levels shorten regrowth. New tiers change lighting, order targets and target arrangements in the same courtyard.

## Code and save compatibility

- `lib/src/garden/harvest_model.dart`: persistent ownership and pure round rules.
- `lib/src/garden/harvest_art.dart`: generated environment, sprite composition and shared rendering/hit-test coordinates.
- `lib/src/garden/harvest_garden.dart`: gestures, HUD, planting, upgrade, pause and progression screens.
- `lib/src/app.dart`: entry from the existing Garden menu, shared wallet, music, update gating and persistence.

The existing `garden_ninja_garden_v4` preference now includes `harvestMastery` and payload version 8. Its existing `seeds` balance is retained as the shared coin wallet. Legacy plots and other fields remain in the payload. Missing/new harvest data starts at tier 1; malformed harvest values are bounded. No old plot data is deleted. New players start with 840 coins, matching the mockup.

The previous garden renderer and data helpers are retained for compatibility, but the Garden entry uses the new screen and does not tick old weeds, care tasks or daily rewards. Old bloom, gift and neglect notifications are cancelled.

## Artwork and validation

The courtyard, six-crop atlas and twelve-building evolution atlas were created with built-in imagegen. The renderer composites each atlas's flat magenta key once at load time into premultiplied transparency. The source assets stay in the repository. The original approved mockup remains in `docs/mockups`, and the exact artwork prompts are in [harvest-art-prompts.md](harvest-art-prompts.md).

Validation includes 35 passing tests covering rewards, regrowth, invalid targets, pause/expiry, purchases, crop unlocks, save restoration and all six tier transitions; real swipes, the animated demo, direct building taps, visible selection of all six beds, planting, upgrade UI, small screens and legacy-wallet compatibility; clean Flutter analysis; a release web build; and a debug Android APK build.

To capture rendered screens locally on Windows with system Arial:

```sh
flutter test --dart-define=GARDEN_CAPTURE=true test/harvest_garden_test.dart
```

Screens are written to the ignored `build/harvest-preview/` directory. These are rendered Flutter screens, not generated mockups.
