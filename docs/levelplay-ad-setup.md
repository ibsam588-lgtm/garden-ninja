# LevelPlay Ad Setup

Garden Ninja is wired for Unity LevelPlay mediation in Android release builds.
If the LevelPlay app key or ad unit IDs are missing, ads stay disabled so local,
CI, and screenshot builds remain safe.

## Dashboard Setup

Create the Android app in Unity/LevelPlay with the real Google Play URL once
the public Play listing is reachable:

```text
https://play.google.com/store/apps/details?id=com.gardenninja.garden_ninja
```

Current dashboard status as of 2026-08-25:

```text
LevelPlay app: Garden Ninja
LevelPlay app key: 27c8fbcdd
Store status: Not live yet

Banner: GardenNinja_Banner / 8bl8nkh06x468qo8
Interstitial: GardenNinja_Interstitial / g7vbv6lc2vw8swyn
Rewarded: GardenNinja_Rewarded / 6np38xk16zk980ef
```

The real Play URL was rejected by LevelPlay while the app was not publicly
reachable, so the app was created as `Not live yet`. Update the app to the real
Play URL after Google Play exposes the listing publicly.

Connect and activate these networks for all three formats:

```text
Unity Ads
Liftoff/Vungle
InMobi
ironSource/iSX
```

For every network, add an instance for Banner, Interstitial, and Rewarded.
Enable in-app bidding where the network dashboard supports it.

Current instance status:

```text
ironSource Bidding: active for Banner, Interstitial, Rewarded.
UnityAds: requires Unity Ads Game ID before instances can be added.
Liftoff Monetize: requires Liftoff App ID and Reporting API ID.
InMobi: requires InMobi placement IDs for Banner, Interstitial, Rewarded.
```

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
Unity Ads: app exists and placements are active.
Liftoff/Vungle: app is active, 3 placements are active, in-app bidding is enabled.
InMobi: app/inventory is connected and app-ads.txt is verified.
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

After a successful Play internal upload, CI updates:

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
