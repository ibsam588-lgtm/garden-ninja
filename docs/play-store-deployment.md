# Google Play Deployment

**Mobile Release** selects Android only when a PR has `release:android` before
merging to the default `main` branch. Its native validation runs in the same
workflow; on merge it signs/uploads that exact commit to internal testing.
Shared files never select a second platform. `release:ios` never builds Android.
No label uploads neither app; both labels fail instead of building both.
See [release routing](ios-release.md#release-pipelines).

Manual operations use Mobile Release with platform **android**. Store uploads and
promotion must run on the actual main/master default branch.
The new caller uses version codes `100000 + GITHUB_RUN_NUMBER`, reserving a range
above the former Android workflow's 100xx series when its run counter restarts.

## GitHub Secrets

Add these repository secrets in GitHub:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
- `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`

Do not commit keystores, key properties, service account JSON, or copied secret values to the public repository.

The Android upload keystore has been generated locally at `android/app/upload-keystore.jks`, with `android/key.properties` pointing to it. Both files are intentionally ignored by Git. The matching Android signing secrets are already configured in GitHub; `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` is also configured for the existing Play Console app.

## Create an Upload Keystore

From a private local folder, create the upload key:

```powershell
keytool -genkeypair -v -keystore upload-keystore.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Copy the base64 value into `ANDROID_KEYSTORE_BASE64`:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("upload-keystore.jks")) | Set-Clipboard
```

Use the same alias and passwords for the related GitHub secrets.

## Play Console Setup

Create the Google Play app before the first deploy:

- App name: `Garden Ninja`
- Package name: `com.gardenninja.garden_ninja`
- Default language: English (United States)
- App type: Game
- Price: Free
- Release track: Internal testing first

In Play Console, enable Play App Signing and upload the first signed app bundle if required by the account. Then create a Google Cloud service account, grant it access to the app in Play Console, and store the service account JSON in `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`.

The workflow deploys to `internal` by default.

To promote a tested internal build to production, dispatch the workflow from
`main`, select platform `android` and operation `promote_production`, and provide its existing `version_code`
after the listing, app-content forms and testing requirements are complete.

Example:

```bash
gh workflow run mobile-release.yml --ref main -f platform=android -f operation=promote_production -f version_code=TESTED_VERSION_CODE
```

## LevelPlay Ads

Garden Ninja release builds read Unity LevelPlay IDs from GitHub repository
variables. See `docs/levelplay-ad-setup.md` for the dashboard setup, required
network checks, test device ID, and `app-ads.txt` notes.
