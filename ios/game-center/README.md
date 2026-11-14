# Garden Ninja Game Center

Bundle: `com.corsairlabs.gardenNinja`. Tap **Game Center** on the iOS home menu
to connect and open Apple's dashboard. Declining leaves both games playable.
Android does not call the GameKit channel or show this button.

| Leaderboard identifier suffix | Score | Ordering |
| --- | --- | --- |
| `arcade_score` | Best completed arcade round with weeds slashed, excluding tutorials | Highest best score |
| `harvest_orders` | Lifetime completed harvest orders on this device | Highest best total |

| Achievement suffix | Requirement | Points |
| --- | --- | --- |
| `first_slice` | Complete a scoring arcade round with weeds slashed | 10 |
| `score_10000` | Score 10,000 in one arcade round | 20 |
| `first_harvest` | Complete one harvest order | 10 |
| `harvest_100` | Complete 100 harvest orders | 30 |
| `grand_estate` | Reach garden tier 6 | 50 |

Every identifier starts with `com.corsairlabs.gardenNinja.`. Matching resources,
English localizations and all five badges are configured in App Store Connect.
The arcade board is the default. Before a public App Store release, include the
new Game Center components in Apple's review submission.

The app keeps earned device records in `garden_ninja_game_center_v1`. It submits
them only after GameKit authenticates the current player. Failed submissions
remain recoverable after restarting; successes are cached per player for the
session. The native bridge checks the player identity again before accepting a
report. These leaderboards and achievements do not synchronize garden saves.

The Game Center entitlement is enabled in all three Runner configurations and
in the app's Apple bundle-ID capability. The App Store provisioning profile must
include `com.apple.developer.game-center`; regenerate it after changing this
capability. Never revoke a shared distribution certificate to refresh a profile.

`create_badges.py` generates editable SVG sources and 512px RGB PNGs with Pillow.
The PNGs are store metadata and are not included in the game's asset bundle.

Validation: `flutter test test/game_center_service_test.dart test/ios_game_test.dart`.
The macOS iOS build workflow verifies compilation and simulator launch. On an
actual signed iPhone/iPad, test authentication/cancellation, both leaderboards,
achievement completion, offline play/reconnection and background/resume before
requesting a public release. TestFlight uses the Game Center testing environment;
the App Store version requires approved Game Center components.
