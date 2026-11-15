# GitHub credentials and release settings

Inventory verified against `ibsam588-lgtm/garden-ninja` on 2026-11-15.
This document records names and purposes. Credential values, private keys,
passwords, service-account JSON and tester email addresses stay out of source.

## Storage locations

Open **Repository Settings > Secrets and variables > Actions**. Eight encrypted
repository secrets and sixteen repository variables are configured. The release
jobs use the `ios-testflight` and `ios-app-store` environments; neither environment
currently defines a separate secret override. Both inherit the repository secrets.
The environments currently have no required-reviewer protection rules.

GitHub returns secret names and update dates, but does not reveal their saved
values. Verification here checked metadata and workflow references, rather than
printing or attempting to retrieve secret values.

## Encrypted repository secrets

| Name | Purpose | Used by |
| --- | --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Encoded Android upload keystore. CI decodes it on the runner to sign an Android App Bundle for Google Play. Base64 is an encoding; GitHub Secrets supplies encryption at rest. | `deploy-google-play.yml` |
| `ANDROID_KEYSTORE_PASSWORD` | Opens that Android upload keystore. | `deploy-google-play.yml` |
| `ANDROID_KEY_ALIAS` | Selects the upload-signing entry inside the keystore. | `deploy-google-play.yml` |
| `ANDROID_KEY_PASSWORD` | Unlocks the selected Android signing key. | `deploy-google-play.yml` |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | Google service-account credential used by Fastlane to authenticate to the Android Publisher API and upload/promote Garden Ninja releases. | `deploy-google-play.yml`, `fastlane/android/Fastfile` |
| `APP_STORE_CONNECT_PRIVATE_KEY` | Complete Apple `.p8` API private key. Authenticates signing-resource lookup, TestFlight upload/distribution, store-media management and explicit App Review submission. Its companion issuer/key IDs are repository variables. The authorized Apple key has App Manager access at account level. | `deploy-app-store.yml`, `testflight-distribution.yml`, `publish-apple-media.yml`, Apple tooling |
| `IOS_DISTRIBUTION_PRIVATE_KEY` | Reusable Apple Distribution signing private key. CI matches it to the existing certificate/profile instead of creating a new identity on every build. Passed to signing tools as `CERTIFICATE_PRIVATE_KEY`. | `deploy-app-store.yml` |
| `IOS_TESTFLIGHT_TESTER_EMAILS` | Comma-separated allowlist of external testers eligible for a first invitation after Apple approves an attached beta build. It does not grant App Store Connect staff access. | `testflight-distribution.yml` |

Apple `.p8` API authentication and the Apple Distribution signing key have
different purposes. Replacing one does not replace the other. Android's upload
key is also separate from the app-signing key managed by Google Play App Signing.

## Repository variables

These are SDK identifiers and release settings, not private signing credentials.

| Name | Purpose |
| --- | --- |
| `APPLE_TEAM_ID` | Selects the enrolled Apple developer team for signing. |
| `APP_STORE_ID` | Identifies Garden Ninja's App Store Connect app and its store/review link. |
| `APP_STORE_CONNECT_ISSUER_ID` | Apple account issuer paired with the API key. |
| `APP_STORE_CONNECT_KEY_ID` | Identifies the `.p8` key. Workflows expose it to Apple tools as `APP_STORE_CONNECT_KEY_IDENTIFIER`. |
| `IOS_RELEASE_ENABLED` | Enables automatic Apple uploads, media publishing and TestFlight follow-up when set to `true`. |
| `IOS_TESTFLIGHT_GROUP_ID` | Selects Garden Ninja's external playtest group. The sync script checks that it belongs to this app. |
| `LEVELPLAY_APP_KEY` | Android LevelPlay application identifier compiled into Android releases. |
| `LEVELPLAY_BANNER_AD_UNIT_ID` | Android banner ad unit. |
| `LEVELPLAY_INTERSTITIAL_AD_UNIT_ID` | Android automatic ad-break unit. |
| `LEVELPLAY_REWARDED_AD_UNIT_ID` | Android optional rewarded-video unit. |
| `LEVELPLAY_IOS_APP_KEY` | Separate iOS LevelPlay application identifier compiled into Apple releases. |
| `LEVELPLAY_IOS_BANNER_AD_UNIT_ID` | iOS banner ad unit. |
| `LEVELPLAY_IOS_INTERSTITIAL_AD_UNIT_ID` | iOS automatic ad-break unit. |
| `LEVELPLAY_IOS_REWARDED_AD_UNIT_ID` | iOS optional rewarded-video unit. |
| `LEVELPLAY_CHILD_DIRECTED` | Owner-supplied child-directed classification forwarded to the mediation/privacy SDKs. |
| `LEVELPLAY_TEST_SUITE` | Controls Android LevelPlay integration-test mode. Production releases use `false`; Apple releases do not enable test-suite mode. |

Native iOS ad-network bidding credentials, account reporting keys, publisher
signatures, payout details and network approvals are managed in the provider and
LevelPlay dashboards. They are not additional GitHub credentials. The app receives
its platform-specific LevelPlay application/ad-unit identifiers at build time.

## Documentation changes do not start builds

Flutter CI ignores `docs/**` and Markdown-only pull requests. Android/iOS build
and deployment workflows already use positive code/platform path filters, so
documentation-only main pushes start neither app builds nor store uploads.
Mixed code/documentation changes still run the checks for the changed code.

Apple media is handled separately: changes under `store-assets/apple/**` run the
media uploader. The hourly TestFlight follow-up can run independently of a push;
its scheduled execution is not a documentation-triggered app build.

Use separate documentation-only commits/PRs to preserve this behavior. Changing
credentials through GitHub settings does not itself create a source-code push.

## Maintenance

Update this inventory when a secret/variable is added, renamed, removed or gains
a new consumer. Update names here, not their values. Use the authorized account
owner to rotate credentials in GitHub and their original provider, then verify
the relevant workflow. Existing store uploads are separate from public release:
Android production promotion and Apple App Review submission select an exact,
tested build through their explicit workflow operations.

See [the release guide](ios-release.md) for platform routing and workflow use.
