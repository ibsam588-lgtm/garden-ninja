# Published iOS App Privacy declaration

App: Garden Ninja: Harvest & Slice (`com.corsairlabs.gardenNinja`).
Approved by the owner and published in App Store Connect on 2026-11-14 for
Game Center and LevelPlay with ironSource, Unity Ads, Meta Audience Network
and Chartboost. All 13 data types below were configured before publication.

Published answer: **Yes, we collect data from this app**, including third-party SDK data.
The purpose names below are Apple's App Functionality, Analytics, and
Third-Party Advertising. Tracking is subject to the player's ATT authorization;
declaring tracking does not grant permission or override a refusal.

| Data type | Purposes | Linked to user | Used for tracking |
| --- | --- | --- | --- |
| Coarse Location | Third-Party Advertising, Analytics | Yes | No |
| Gameplay Content | App Functionality (Game Center scores/achievements) | Yes | No |
| Customer Support | App Functionality (ad reports) | No | No |
| User ID | App Functionality, Analytics, Third-Party Advertising | Yes | No |
| Device ID | Third-Party Advertising, Analytics, App Functionality | Yes | Yes |
| Purchase History | Third-Party Advertising, Analytics (Unity Ads disclosure) | Yes | No |
| Product Interaction | Third-Party Advertising, Analytics, App Functionality | Yes | No |
| Advertising Data | Third-Party Advertising, Analytics, App Functionality | Yes | Yes |
| Other Usage Data | Third-Party Advertising, Analytics | Yes | No |
| Crash Data | Analytics | No | No |
| Performance Data | App Functionality, Analytics, Third-Party Advertising | Yes | No |
| Other Diagnostic Data | Analytics | No | No |
| Other Data Types | App Functionality, Third-Party Advertising, Analytics | Yes | No |

Other categories are not selected. The game does not request access to precise
location, contacts, photos, microphone recordings, or financial account details.
Device-local garden saves are not uploaded to Game Center. Purchase History is
included because Unity's SDK disclosure lists it. The 2026-11-15 Remove Ads
implementation also verifies ownership locally through StoreKit 2; it does not
collect card/bank credentials or send purchase proof to a Corsair Labs server.
Apple handles the store account and payment. Apple's privacy guidance excludes
processing confined to the device and data collected by Apple itself from the
developer's collection disclosure; third-party ad SDK collection remains covered
by the published declaration above.

The compiled 2026-11-15 release includes InMobiSDK 11.5.0 and VungleAds 7.8.0.
Their bundled privacy manifests were inspected: they provide required-reason API
declarations, rather than a complete inventory of ad data collected by the SDKs.
Manifest presence alone does not replace the declaration or SDK privacy review.
No additional OS privacy permissions were added for these adapters.

Sources checked:

- [ironSource Apple questionnaire](https://docs.unity.com/en-us/grow/is-ads/legal-resources/apple-privacy-questionnaire)
- [Unity Ads Apple privacy survey](https://docs.unity.com/en-us/grow/ads/privacy/apple-privacy-survey)
- [Apple app privacy details and on-device processing](https://developer.apple.com/app-store/app-privacy-details/)
- [Chartboost privacy manifest](https://docs.chartboost.com/en/monetization/integrate/ios/privacy-manifest/)
- Meta FAN 6.22.0's bundled `PrivacyInfo.xcprivacy`, inspected from its official
  CocoaPods distribution at `https://developers.facebook.com/resources/FBAudienceNetwork-6.22.0.zip`.
  It declares linked tracking for Device ID/Advertising Data and unlinked
  analytics for Crash Data/Other Diagnostic Data.
