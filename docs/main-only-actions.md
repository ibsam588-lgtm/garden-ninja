# Main-Only GitHub Actions

All workflow jobs require `github.ref == refs/heads/main`. Push triggers target only `main`; pull-request and tag triggers are removed. Manual runs selected on another branch skip every job. Checkouts use the triggering main commit SHA, not a PR head or a mutable branch.

Mobile Release runs on a push to main. It reads the PR associated with that exact merged commit. Exactly one `release:ios` or `release:android` label selects one platform; no label skips mobile builds and both labels fail before any native build. An explicit main-branch dispatch retains the workflow's existing platform/upload options. Store submission and production promotion remain explicit operations.

This policy does not certify native builds, consent, ads or purchases. Follow the app's release-readiness checks before uploading or publishing. Screenshot workflows are not run by this change.

To upload locally captured Play listing media, dispatch Mobile Release on `main` with platform `android`, operation `upload_store_media` and the public trailer’s 11-character `youtube_id`. The job uses the existing Play service account to verify phone and tablet screenshot hashes in each listing and update the trailer in one edit. Upload foldable screenshots in Play Console and check Publishing overview for review status.
