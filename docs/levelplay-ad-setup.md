# LevelPlay Ad Setup

## iOS adapter completion (2026-11-15)

The iOS build includes InMobi adapter 5.10.0.0 and Liftoff/Vungle adapter 5.17.0.0
alongside ironSource, Unity Ads, Meta and Chartboost, retaining LevelPlay 9.4.0.0.
GDPR vendor consent is forwarded separately for InMobi (GVL 333) and Liftoff
(GVL 667); US opt-out covers both. Official attribution lists were checked and 14
missing valid IDs added, giving 199 unique entries. Malformed nine-character IDs
in InMobi's list were not copied into the app.

### InMobi and Liftoff iOS mappings completed (2026-11-15)

Garden Ninja iOS (`2990d6595`) now has all six networks configured for banner,
interstitial and rewarded. Both new bidders were saved, reopened, and verified
in LevelPlay. Their instances belong to the existing **All Countries** groups.
These are remote dashboard mappings; native adapters already exist in build 7.

| Format | InMobi placement ID | Liftoff placement reference ID |
| --- | --- | --- |
| Banner | `10000882126` | `GARDENNINJA_IOS_BANNER-4809429` |
| Interstitial | `10000882127` | `GARDENNINJA_INTERSTITIAL-9440450` |
| Rewarded | `10000882128` | `GARDENNINJA_IOS_REWARDED-3701667` |

InMobi app key: `10000255809`. Audience bidding is enabled with **Unity LevelPlay**
as the partner for all three placements. The prelaunch app is declared mixed
audience; location access is disabled and political, gambling and alcohol ads
remain blocked. With no public App Store URL, InMobi forces **Global test mode**;
the publisher account still shows **Pending Verification**.

Liftoff iOS app/reporting API ID: `6a8dc801a308f75b0711934f`. The existing unconnected
iOS record was reused and renamed **Garden Ninja iOS**; its original bidding
interstitial was retained and the two missing placements added. Banner refresh
is disabled at Liftoff so LevelPlay owns refresh. The app is in **Test Mode**;
Active is disabled until the public Apple listing can be connected.

Before live serving, connect **Apple app 6834694197**, bundle
`com.corsairlabs.gardenNinja`, finish provider verification, and turn off provider
test modes. Do this only with the new age-gated build distributed; build 7 has
the adapters but lacks the age gate. Meta also requires a public Apple store URL;
Chartboost remains in developer mode before release. Check all three formats on
a registered iPhone; dashboard checkmarks do not demonstrate live fill.

### Mixed-audience startup gate

The owner confirmed that ages 13–15 are included. InMobi's child-privacy setting
covers under 16, so the app now resolves an unselected age range before creating
the game or initializing advertising. Only `under_13`, `13_to_15` or `16_plus`
is stored in a separate local preference; no birthday is collected or uploaded.
Missing, invalid or unreadable preferences cannot default to an ad-eligible age.

Players under 16 play without any ad SDK initialization, ad requests, CMP/ATT
prompts, rewarded videos or Remove Ads offers. This avoids relying on every
mediated network's restricted-request support. For eligible users, LevelPlay
receives `InMobi_AgeRestricted=false` before initialization; the existing consent
flow still determines tracking permission. Age eligibility is not a consent grant.
Store/screenshot builds remain ad-free and bypass the gate. The shared gate
applies to Android and iOS. Eight focused startup/persistence tests and the full
82-test Flutter suite passed (13 optional media captures skipped).
The age gate is included in Apple build 8. Subsequent shared changes select
one store through a PR label: `release:ios` or `release:android`. The single
Mobile Release workflow validates the selected platform and uploads it on merge;
shared paths never infer both builds. Android receives shared safeguards when an
Android-labelled release is merged or a manual Android upload is selected.
See [platform release routing](ios-release.md#release-pipelines).

References: [InMobi children's privacy](https://support.inmobi.com/monetize/privacy/coppa),
[LevelPlay InMobi settings](https://docs.unity.com/en-us/grow/levelplay/sdk/ios/networks/guides/inmobi).

The six-network iOS build compiled, launched in the simulator, uploaded through
GitHub Actions as **1.1.7 (7)** and was processed by Apple as **VALID**. The signed
app contains the native adapters; this does not demonstrate live ad fill.
Provider registrations and mappings were completed after the owner resumed
browser work. No other apps' inventory or payout settings were changed.

The [Remove Ads purchase](in-app-purchases.md) disables banners and automatic
interstitials, including preloaded ads. Rewarded videos remain optional. Startup
restore completes before automatic ads are eligible.

Garden Ninja is wired for Unity LevelPlay mediation in Android release builds.
If the LevelPlay app key or ad unit IDs are missing, ads stay disabled so local,
CI, and screenshot builds remain safe.

## Dashboard Setup

Garden Ninja was created in Unity/LevelPlay while the public Play listing was
not reachable yet. Update the app to the real Play URL after Google Play exposes
the listing publicly:

```text
https://play.google.com/store/apps/details?id=com.gardenninja.garden_ninja
```

Current dashboard status (store connection verified 2026-09-26):

```text
LevelPlay app: Garden Ninja
LevelPlay app key: 27c8fbcdd
Store status: Live

Banner: GardenNinja_Banner / 8bl8nkh06x468qo8
Interstitial: GardenNinja_Interstitial / g7vbv6lc2vw8swyn
Rewarded: GardenNinja_Rewarded / 6np38xk16zk980ef
```

The app is now connected to its public Google Play listing.

Connect and activate these networks for all three formats:

```text
Unity Ads
Liftoff/Vungle
InMobi
ironSource/iSX
Chartboost
```

For every network, add an instance for Banner, Interstitial, and Rewarded.
Enable in-app bidding where the network dashboard supports it.

Current instance status:

```text
ironSource Bidding: active for Banner, Interstitial, Rewarded.
UnityAds: active for Banner, Interstitial, Rewarded.
Liftoff Monetize: active for Banner, Interstitial, Rewarded.
InMobi: blocked. Garden Ninja inventory could not be created while the InMobi
account is pending verification and the inventory create flow resets before
submission.
Chartboost: Android adapter 5.11.0 included. Dashboard credentials and bidding
locations remain pending the Chartboost app registration acknowledgment.
```

Configured network dashboard IDs:

```text
Unity Ads
Game ID: 800362179
Banner placement: Banner_Android
Interstitial placement: Interstitial_Android
Rewarded placement: Rewarded_Android

Liftoff Monetize / Vungle
Android app ID: 6a8dc9ccf5afadb097fee57b
Reporting API ID: 6a8dc9ccf5afadb097fee57b
Banner placement: GARDENNINJA_BANNER-3632752
Interstitial placement: GARDENNINJA_INTERSTITIAL-8383039
Rewarded placement: GARDENNINJA_REWARDED-1686088
```

The separate Liftoff iOS app is now mapped only to Garden Ninja iOS in LevelPlay.
Do not use its iOS placement IDs for Android mediation.

## GitHub Repository Variables

Add these under:

```text
Settings > Secrets and variables > Actions > Variables
```

```text
LEVELPLAY_APP_KEY
LEVELPLAY_BANNER_AD_UNIT_ID
LEVELPLAY_INTERSTITIAL_AD_UNIT_ID
LEVELPLAY_REWARDED_AD_UNIT_ID
LEVELPLAY_CHILD_DIRECTED=false
LEVELPLAY_TEST_SUITE=false
```

CLI form:

```powershell
gh variable set LEVELPLAY_APP_KEY --body "your-levelplay-app-key"
gh variable set LEVELPLAY_BANNER_AD_UNIT_ID --body "your-banner-ad-unit-id"
gh variable set LEVELPLAY_INTERSTITIAL_AD_UNIT_ID --body "your-interstitial-ad-unit-id"
gh variable set LEVELPLAY_REWARDED_AD_UNIT_ID --body "your-rewarded-ad-unit-id"
gh variable set LEVELPLAY_CHILD_DIRECTED --body "false"
gh variable set LEVELPLAY_TEST_SUITE --body "false"
```

The internal-testing workflow passes these into `flutter build appbundle` as
`--dart-define` values. Keep `LEVELPLAY_TEST_SUITE=false` for Play uploads.

Current GitHub repository variables are set to the live LevelPlay app/ad-unit
values above.

## App Ad Flow

The app preloads rewarded and interstitial inventory after LevelPlay finishes
initializing. Banner, rewarded, and interstitial SDK calls use LevelPlay's
configured `Default` placement; the descriptive request names in Dart remain
local diagnostics. Interstitials are opportunistic: a level transition is never
held while an ad loads, and a ready ad is consumed only after the SDK confirms
it is available and uncapped. Rewarded videos can load after the player's tap,
grant the reward only from `onAdRewarded`, and preload their replacement after
closing or failing.

Version 1.1.7 counts completed arcade rounds (wins and losses) and Harvest
Garden rounds together. An interstitial becomes due after three completed
rounds in the current session. Tutorials and quitting do not count, and no ad
is shown on app exit. The counter resets only after an interstitial is shown;
if inventory is unavailable, gameplay continues and the ad remains due at a
later natural break. Rewarded videos remain voluntary.

The Chartboost COPPA metadata is set before SDK initialization using the same
`LEVELPLAY_CHILD_DIRECTED` value as LevelPlay. Keep test-suite mode off for Play
uploads. Including an adapter does not activate a network: Garden Ninja's
Chartboost app credentials and bidding locations must also be saved in LevelPlay.

Garden Ninja's Android build also includes the Meta Audience Network adapter.
In LevelPlay's **Instances** page, select Garden Ninja and confirm the Meta
banner, interstitial, and rewarded instances use this app's Android placement
IDs. The adapter uses the existing LevelPlay ad units and round-break rules.
Meta must have payout onboarding completed and the app approved for live delivery;
an active LevelPlay instance by itself does not prove that Meta can serve ads.
Use the LevelPlay integration test suite to check each format on a test device.

Building with `LEVELPLAY_TEST_SUITE=true` suppresses the normal app ad widgets
and opens the official integration test suite after initialization. On
2026-09-12, the suite identified all three configured ad units, detected
ironSource, Liftoff Monetize, and Unity Ads for rewarded, interstitial, and
banner formats, loaded a Unity Ads rewarded creative, and loaded and displayed
an ironSource test interstitial. Keep the flag `false` for Play builds.

A production-mode Android smoke test on 2026-09-13 used the live app key and
ad-unit IDs with `LEVELPLAY_TEST_SUITE=false`. LevelPlay initialized, loaded and
displayed a Unity Ads banner and interstitial, displayed a Unity Ads rewarded
video, returned to the game, and granted the level-complete reward. The banner
host is fixed to LevelPlay's 320 x 50 slot and the game body ends above that
slot, so the native ad view cannot cover or intercept the game controls.

## Test Device

Use this test device ID in the LevelPlay dashboard test device setup:

```text
5a9fdf25-64d3-4dba-bd10-5ba01df93b1c
```

Current dashboard status: `ibsam588 Android` is already registered with this
ID for Garden Ninja. It is configured for `ironSource Bidding` with all three
ad formats selected.

The ID should remain stable for the same Android profile unless the Android
Advertising ID is reset, the device/profile changes, the device is factory
reset, or ad ID settings are disabled/reset.

## Network Dashboard Checks

Before pushing a production or closed-track ad build, confirm:

```text
Unity Ads: app exists and 3 placements remain active.
Liftoff/Vungle: Android app is active, 3 placements remain active, in-app bidding is enabled.
InMobi: account is verified, app/inventory is connected, and app-ads.txt is verified.
ironSource/iSX: app and instances are active in LevelPlay.
```

## app-ads.txt

Host `app-ads.txt` on the developer website root:

```text
https://corsairlabs.com/app-ads.txt
```

Do not publish placeholder lines. Use the exact seller/account lines provided
by Unity/LevelPlay, Liftoff/Vungle, InMobi, and ironSource/iSX dashboards.
Append them to the existing Corsair Labs `app-ads.txt` entry after each
dashboard provides the live account IDs.

## Forced Update Metadata

After a successful production upload, CI updates:

```text
public/app-version.json
```

For production or closed-track force updates, the workflow writes:

```json
{
  "android": {
    "minimumBuild": 10038,
    "latestBuild": 10038,
    "force": true,
    "updateUrl": "https://play.google.com/store/apps/details?id=com.gardenninja.garden_ninja"
  }
}
```

The build number is `10000 + github.run_number`, which is the same value passed
to Flutter as Android `versionCode`.
