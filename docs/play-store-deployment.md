# Google Play Deployment

This repo deploys Android builds from GitHub Actions after changes are merged to `main`. The workflow runs analysis and tests on every merge. It uploads to the Google Play internal testing track only after all required secrets are configured.

## GitHub Secrets

Add these repository secrets in GitHub:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
- `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`

Do not commit keystores, key properties, service account JSON, or copied secret values to the public repository.

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

The workflow deploys to `internal` by default. Change `PLAY_TRACK` in `.github/workflows/deploy-google-play.yml` to `production` only after the listing, app-content forms, testing requirements, and review process are complete.
