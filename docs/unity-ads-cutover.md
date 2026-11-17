# Unity Ads Cutover

Keep the LevelPlay SDK/plugin. The retiring ironSource Ads/iSX demand network is not the LevelPlay mediation product.

## Dependencies

- Android: `com.unity3d.ads-mediation:unityads-adapter:5.16.0`. It brings Unity Ads SDK 4.22.0 transitively; do not pin a conflicting older SDK.
- iOS CocoaPods: `IronSourceUnityAdsAdapter`, `5.14.0.0`, which depends on UnityAds 4.22.0 and LevelPlay 9.x.
- iOS Swift Package Manager: `LevelPlay-UnityAds-Adapter-Swift-Package` 5.14.0, product `UnityAdsAdapter`. Keep `UnityMediationSDK` linked.
- Include Unity's `4dzt52r2t5.skadnetwork` attribution ID. Preserve IDs used by the other mediated networks.

## Verification Before Cutover

1. Resolve native dependencies and build the actual Android/iOS release candidate. A source check alone does not prove native linking or ad delivery.
2. Verify the matching Unity Game ID, platform, active bidding placements and LevelPlay instances for the formats the app uses.
3. On a test device, open the LevelPlay integration test suite. For bidding line items explicitly select **Test**, not Live, before loading or showing ads.
4. Confirm Unity adapter and SDK versions appear, then load and show banner, interstitial and rewarded test ads where those formats are supported. Verify the reward callback and the app's return from full-screen ads.
5. Verify consent/ATT, app-ads.txt and store/network approval for the intended platform. Do not enable an intentionally disabled iOS monetization flow without its consent work.
6. Release the verified binary and confirm availability before changing demand for existing users.

## Cutover

In the app's LevelPlay ironSource **network** settings, deactivate its banner, interstitial and rewarded instances after the replacement passes the checks above. Do not delete the instances or uninstall the LevelPlay plugin. Leave Unity Ads and every other network enabled.

Re-open the Unity Ads settings after saving. Auto-created bidders may inherit old network format defaults; verify Unity remains active independently. Record app, platform, build, date, test results and the old instance state.

If Unity loading fails after cutover while iSX still serves, restore only the old ironSource instances from the recorded state and investigate. Do not undo SDK retention or change unrelated network credentials.

## Screen Lamp Debug Harness

Screen Lamp includes `tool/unity_ads_smoke.dart`, a separate mobile debug-only entry point. It initializes LevelPlay and opens the vendor integration suite, without starting the normal app's ad session. Supply the matching platform's `LEVELPLAY_APP_KEY`; select Test in the suite before requesting ads. Never upload the harness as a store build.

## References

- [Unity sunset FAQ](https://unity.com/products/ironsource-ads-sunset): iSX stops delivering December 31, 2026; LevelPlay is unaffected.
- [Android Unity Ads integration](https://docs.unity.com/en-us/grow/levelplay/sdk/android/networks/guides/unity-ads)
- [iOS Unity Ads adapter changelog](https://github.com/ironsource-mobile/levelplay-ios-adapters/blob/master/Adapters/UnityAds/CHANGELOG.md)
- [Flutter integration test suite](https://docs.unity.com/en-us/grow/levelplay/sdk/flutter/integration-test-suite)
