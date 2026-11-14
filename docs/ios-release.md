# Garden Ninja on iOS

The iOS target shares the existing arcade, harvest garden, six garden tiers,
upgrades, demo, audio and local saves with Android. It supports iPhone and iPad
in portrait, starting at iOS 15. The bundle ID is
`com.corsairlabs.gardenNinja` (Apple bundle IDs cannot contain underscores).
Progress stays on each device. On iOS, the optional Game Center button opens
Apple's player authentication and dashboard through GameKit. Earned arcade
records and garden milestones are queued locally and retried after sign-in or
when the app resumes. This does not introduce cloud saves or cross-store purchases.

Apple playback uses AAC/M4A music and PCM/WAV sound effects converted from the
existing Ogg originals, because AVPlayer rejected the Ogg files in the simulator.
Android and other platforms retain their existing assets. The audio asset test
checks that every original has a corresponding Apple file with the right container.

## Release pipelines

There are two store deployment workflows, alongside the pull-request checks:

| Workflow | On main | Manual production operation |
| --- | --- | --- |
| Deploy Android to Google Play | Build/sign and upload to internal testing | Promote a tested internal version code to production |
| Deploy iOS to Apple | Build/sign and upload to App Store Connect/TestFlight | Submit an exact tested version/build for App Review |

Automatic releases use the changed file paths:

| Changed files | Android upload | iOS upload |
| --- | --- | --- |
| `android/**`, Android Fastlane settings/changelogs, Android release workflow | Yes | No |
| `ios/**`, Apple release settings/workflow | No | Yes |
| Shared `lib/**`, `assets/**`, `pubspec.*`, `fastlane/Fastfile`, `Gemfile*` | Yes | Yes |
| Documentation, tests, or store screenshots/listing text alone | No | No |

An iOS-only pull request also skips Android deployment. The lightweight Flutter
analysis/tests still run on pull requests; the native iOS build check runs only
for its relevant paths. A manual **Run workflow** starts only the selected
platform's workflow. A change inside a shared Dart file affects both release
filters, even if the edited code contains a platform condition.

The Apple app record is **Garden Ninja: Harvest & Slice**, app ID
`6834694197`, on team `5MST9WC27Z`:
[App Store Connect](https://appstoreconnect.apple.com/apps/6834694197/distribution).

The Apple workflow uses a macOS/Xcode runner. It fetches signing assets with
the official Flutter-documented Codemagic CLI tools, signs a real IPA, checks
the signing team, saves the IPA/dSYMs and uploads through Fastlane/Transporter.
The API key avoids interactive Apple ID/2FA sessions on CI. An upload is not an
App Store publication: Apple processes it for TestFlight first. External beta
testing can require Beta App Review and export-compliance information.

### GitHub configuration

Set these repository **variables**:

| Name | Value |
| --- | --- |
| `APP_STORE_ID` | `6834694197` |
| `APPLE_TEAM_ID` | `5MST9WC27Z` |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID from Apple Integrations |
| `APP_STORE_CONNECT_KEY_ID` | ID of the CI API key |
| `IOS_RELEASE_ENABLED` | `true` after the first signed upload succeeds |

Store these as encrypted repository **secrets**:

| Name | Content |
| --- | --- |
| `APP_STORE_CONNECT_PRIVATE_KEY` | Complete downloaded App Store Connect `.p8` PEM key |
| `IOS_DISTRIBUTION_PRIVATE_KEY` | Reusable RSA PEM private key for the Apple Distribution certificate |

The signing key is persistent: CI reuses the matching Apple certificate and
profile rather than creating a new distribution identity on every build.
Existing distribution private keys can be reused. Apple limits active signing
certificates, so other apps on the same team should share an appropriate
existing distribution identity when its private key is available.

Signing credentials stay in environment variables or the temporary runner
keychain. The uploaded artifacts contain the signed app, public release
configuration and debugging symbols, never the `.p8`, RSA key or `.p12`.
Credentials are not exposed to pull-request workflows.

### Upload and submit

1. Merge game changes into main. Once enabled, each relevant main change is
   signed and sent to TestFlight automatically. Apple build numbers are chosen
   from the latest uploaded build for that version; release jobs run serially.
2. For the first upload, use **Actions → Deploy iOS to Apple → Run workflow**,
   branch **main**, operation **upload_testflight**. Leave the version blank to
   read it from `pubspec.yaml`. A missing configuration fails with field names
   instead of silently producing an unsigned release.
3. Confirm processing in App Store Connect and test the selected build on a
   real device. Complete the store listing, screenshots, privacy disclosures,
   age rating, review details and export compliance in the Apple portal.
4. Run the same workflow with **submit_for_review**, entering the exact tested
   version (for example `1.1.7`) and Apple build number. This submits that
   existing build without rebuilding it. Release remains manual after Apple's
   approval; CI does not publish a new version automatically.

To reproduce an upload from a configured Mac, run the commands in
`.github/workflows/deploy-app-store.yml`. The non-secret input validation is
covered by `python3 -m unittest discover -s tooling/tests -p test_ios_release_config.py`.

## Build and play without an Apple Developer membership

On a Mac with Xcode 26 or later, CocoaPods and Flutter 3.44.2:

```sh
flutter pub get
open -a Simulator
flutter run
```

Open `ios/Runner.xcworkspace` to use Xcode. The project uses CocoaPods for
LevelPlay and the native network adapters. Swift Package Manager is disabled
for this project to avoid duplicate plug-in integration.

The **iOS build** GitHub Actions workflow compiles a release for real devices
without signing, compiles and launches the simulator app, and saves the two
`.app` bundles, resolved `Podfile.lock`, and a launch screenshot as an artifact.
It runs for relevant pull requests and can be started manually from Actions.
On a Mac, extract `garden-ninja-ios-simulator.tar.gz` and install it with:

```sh
xcrun simctl install booted Runner.app
xcrun simctl launch booted com.corsairlabs.gardenNinja
```

An unsigned device `.app` is a build check, not an installable IPA. Windows
cannot run the Apple simulator. An iPhone needs signing; Xcode supports personal
development signing, while TestFlight/App Store distribution needs an enrolled
Apple Developer account.

## iOS ads

iOS credentials intentionally have no Android fallback. The separate iOS
inventory below was configured on 2026-11-14 and its four values are saved as
GitHub repository variables for the Apple release workflow:

| Setting | Value |
| --- | --- |
| LevelPlay app key | `2990d6595` |
| Banner | `GardenNinja_iOS_Banner` / `8axgv1vdwdx8ocve` |
| Interstitial | `GardenNinja_iOS_Interstitial` / `3lbhtym58gw2nanc` |
| Rewarded | `GardenNinja_iOS_Rewarded` / `mu8oi34r9sk9mr7l` |

ironSource and Unity Ads bidding have all three formats configured. Unity's
iOS game ID is `800438618`, with `BP_Banner_iOS`, `BP_Interstitial_iOS` and
`BP_Rewarded_iOS` placements. Meta's separate iOS placements are saved in
LevelPlay, but Meta reports **Missing app URL** until this iOS app is public:

- Banner: `28274733552202027_28342511198757595`
- Interstitial: `28274733552202027_28342553838753331`
- Rewarded: `28274733552202027_28342600555415326`

The Podfile includes LevelPlay SDK 9.4.0 through Flutter, Meta adapter 5.4.0.0
(FAN 6.22.0), Chartboost adapter 5.10.0.0, and Unity Ads adapter 5.9.0.0
(Unity Ads 4.19.0). Their native integration is separate from network approval
and actual fill. Without an iOS key, ads and consent prompts stay off.

Create a separate **iOS app** in LevelPlay, separate iOS network apps/placements,
and supply these build definitions when the iOS inventory is ready:

```sh
flutter build ios --release --no-codesign \
  --dart-define=LEVELPLAY_IOS_APP_KEY=YOUR_IOS_APP_KEY \
  --dart-define=LEVELPLAY_IOS_BANNER_AD_UNIT_ID=YOUR_IOS_BANNER_ID \
  --dart-define=LEVELPLAY_IOS_INTERSTITIAL_AD_UNIT_ID=YOUR_IOS_INTERSTITIAL_ID \
  --dart-define=LEVELPLAY_IOS_REWARDED_AD_UNIT_ID=YOUR_IOS_REWARDED_ID
```

The existing optional rewarded videos and interstitial policy (after three
completed wins/losses, at a natural break) are shared. Live delivery must be
verified on a signed device using `--dart-define=LEVELPLAY_TEST_SUITE=true` in
a separate test build; leave this flag off for release. Additional networks
enabled on Android need their own iOS adapters and dashboard setup.

Before SDK initialization, the native bridge waits for an active app and
InMobi CMP 2.4.2 to resolve the published iOS property's GDPR/US choices.
The home menu's **Ad privacy** control reopens those choices. Ad views and
preloaded videos are cleared while choices change. CMP failures leave ads off
and gameplay available. ATT is requested only when consent permits tracking;
declining ATT still permits gameplay and nontracking requests. Meta's tracking
flag follows ATT on older iOS versions; FAN reads ATT directly on iOS 17+.

The CMP property is `com.corsairlabs.gardenNinja` (ID `1150067`), published
under the existing account. It uses the default consent text, worldwide
coverage, GDPR/US regulation settings and no Consent or Pay. No paid
subscription was created. InMobi currently labels the account's properties
with its existing Premium Free Trial. Custom premium options were not added.
Native consent forwards IAB vendor IDs 1549 (Unity) and 1601 (Chartboost),
checked against the IAB GVL on 2026-11-14. Meta receives no invented GDPR
consent grant; it is disabled for personalization where this property has no
matching non-IAB vendor consent. US opt-outs are forwarded to LevelPlay.

Info.plist contains 185 unique SKAdNetwork IDs from the official
[Unity list](https://skan.mz.unity3d.com/v3/partner/skadnetworks.plist.json) and
[Chartboost list](https://a3.chartboost.com/skadnetworkids.json), fetched on
2026-11-14, including ironSource and Meta IDs. Apple's proposed privacy answers
are recorded in `docs/ios-app-privacy.md`; their publication requires approval.
Test all three ad formats and privacy-choice changes on a signed iPhone.

## When an Apple account is ready

1. Register the bundle ID and create Garden Ninja in App Store Connect.
2. Select the development team and signing profile in Xcode. No team or signing
   secrets are committed here.
3. Pass the numeric App Store ID with `--dart-define=APP_STORE_ID=1234567890`.
   Until then, the manual Rate App button is hidden on iOS. Native automatic
   review requests use StoreKit; Apple decides whether to display them.
4. Complete screenshots, age rating, support/privacy URLs, privacy disclosures
   and export-compliance answers for the actual release configuration.
5. Run `flutter build ipa --release --build-number=NEXT_BUILD_NUMBER` with the
   same iOS ad definitions, if enabled, and upload with Xcode Organizer or
   Transporter. Test both games, saves, audio, interruptions, safe areas and
   ad callbacks on a real iPhone/iPad before requesting App Store review.

References: [Flutter iOS deployment](https://docs.flutter.dev/deployment/ios),
[LevelPlay Flutter mediation](https://docs.unity.com/en-us/grow/levelplay/sdk/flutter/mediation-networks),
[Unity's SKAdNetwork list](https://docs.unity.com/en-us/grow/levelplay/sdk/ios/skadnetwork-id-manager),
[Apple review guidance](https://developer.apple.com/documentation/StoreKit/requesting-app-store-reviews).
