# Proposed iOS App Privacy declaration

App: Garden Ninja: Harvest & Slice (`com.corsairlabs.gardenNinja`).
Prepared 2026-11-14 for Game Center and LevelPlay with ironSource, Unity Ads,
Meta Audience Network and Chartboost. Publication awaits explicit approval.

Answer **Yes, we collect data from this app**, including third-party SDK data.
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
included because Unity's SDK disclosure lists it, not because this build adds
in-app purchases or collects payment credentials.

Sources checked:

- [ironSource Apple questionnaire](https://docs.unity.com/en-us/grow/is-ads/legal-resources/apple-privacy-questionnaire)
- [Unity Ads Apple privacy survey](https://docs.unity.com/en-us/grow/ads/privacy/apple-privacy-survey)
- [Chartboost privacy manifest](https://docs.chartboost.com/en/monetization/integrate/ios/privacy-manifest/)
- Meta FAN 6.22.0's bundled `PrivacyInfo.xcprivacy`, inspected from its official
  CocoaPods distribution at `https://developers.facebook.com/resources/FBAudienceNetwork-6.22.0.zip`.
  It declares linked tracking for Device ID/Advertising Data and unlinked
  analytics for Crash Data/Other Diagnostic Data.
