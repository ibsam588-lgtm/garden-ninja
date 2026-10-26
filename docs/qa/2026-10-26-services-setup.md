# Garden Ninja services setup — 2026-10-26

## Verified changes

- Ten machine-translated store locales applied and submitted: ar, de-DE,
  es-ES, es-419, fr-FR, hi-IN, id, ja-JP, ko-KR, pt-BR. Titles and short
  descriptions were reviewed and shortened to Play limits while preserving
  the Garden Ninja brand. The ten translations and existing English trailer
  correction are confirmed under **Changes in review**.
- Free translation order `e558d3dd1v2` completed at USD 0.00. No products were
  available in the translation selector; no purchase products were created.
- Automatic Android app-string translations enabled for nine languages:
  es, fr, de, pt, hi, ar, ja, ko, id. Google's feature processes Android
  `strings.xml` in future/draft bundles. It does not translate hardcoded
  Flutter widget text; the game UI still needs Flutter localization.
- Play listing developer website published as `https://corsairlabs.com`.
  The domain already serves `/app-ads.txt` with the Chartboost DIRECT seller
  `6add881f0d06fc6d18ce7378`. Dashboard verification and store propagation
  remain separate checks.
- Dedicated Cloud project `garden-ninja-512822` created and linked to Play
  Games Services project `1081711751724`. OAuth branding created with the
  approved Google API Services User Data Policy acceptance.
- Android OAuth client created for package `com.gardenninja.garden_ninja`
  and the signing fingerprint supplied by Play Console:
  `A8:34:F0:92:8A:96:57:C9:B2:47:B4:CB:A5:A6:C8:D9:04:8E:42:A3`.
  Credential saved in Play Games Services. Casual category, matching game
  name, description, store icon, and feature graphic saved. The publication
  page reports **Ready to publish**.
- Play Games SDK v2 `22.1.0` and its manifest application ID are included in
  Android. Cloud saves, recall tokens, achievements, and leaderboards are not
  enabled by this baseline sign-in integration.
- Chartboost LevelPlay adapter `5.11.0` and its repository added. Chartboost
  COPPA metadata is applied before LevelPlay initialization.
- Automatic interstitial cadence changed to every three completed rounds,
  including arcade wins/losses and Harvest Garden. Quit/exit ads removed.

## Pending account actions

- Chartboost app creation requires the user's COPPA acknowledgment approval.
  Next: add Garden Ninja, create bidding locations for all three formats,
  connect credentials to LevelPlay, and scan app-ads.txt. The LevelPlay tab
  also became unresponsive during browser inspection; network activation has
  not been verified.
- OAuth remains in Testing pending explicit approval to publish to all
  players. Play Games project publication remains pending that decision.
- A new signed app bundle must reach the desired Play track before the new
  SDKs and cadence affect installed users. Local compilation is not a live
  ad-serving or Play Games device test.
- Updated public privacy pages are prepared in Corsair Labs
  [PR 23](https://github.com/ibsam588-lgtm/corsairlabs/pull/23). Automatic
  approval review requires explicit authorization before merging that PR.

## Local validation

- `flutter analyze`: no issues.
- `flutter test`: all 48 tests passed, including three-round cadence,
  unavailable inventory, and one completion callback per Harvest round.
- Android debug APK built successfully with the real LevelPlay app/ad-unit
  identifiers and test suite disabled. Used workspace-isolated
  `GRADLE_USER_HOME=build/gradle-garden-setup` because the shared Gradle cache
  journal was corrupt. No shared cache was deleted.

## Implementation references

- [Chartboost LevelPlay integration](https://docs.unity.com/en-us/grow/levelplay/sdk/android/networks/guides/chartboost)
- [Play Games Android integration](https://developer.android.com/games/pgs/android/android-signin)
- [Play Games SDK data disclosures](https://developer.android.com/games/pgs/data-collection)
- [Play translation behavior](https://support.google.com/googleplay/android-developer/answer/9844778?hl=en)
