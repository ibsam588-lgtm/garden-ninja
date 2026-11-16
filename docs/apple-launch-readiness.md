# Apple launch readiness — 2026-11-16

App: Garden Ninja: Harvest & Slice, Apple ID 6834694197,
bundle `com.corsairlabs.gardenNinja`.

## Verified and prepared

- Source minimum deployment target is iOS 15. New iOS validation/uploads use
  `xcode-27` and reject older SDKs; signed archive metadata is checked before
  upload. See the latest Mobile Release run for actual compiled/uploaded evidence.
- LevelPlay is the mediation layer. All six providers have separate iOS mappings
  for banner, interstitial and rewarded. Public-listing/verification/test-mode
  restrictions remain provider-side; see `levelplay-ad-setup.md`.
- The public App Store update gate is implemented with compatible-version checks,
  TestFlight exclusion and offline failure handling. Older builds cannot receive
  that code remotely. Android's existing immediate-update flow is retained.
- One Mobile Release workflow selects exactly one platform from a PR label and
  uploads its immutable merged commit. Shared files cannot select both platforms.
- Existing 48 screenshots and three gameplay previews were verified COMPLETE.
  Eight locally rendered Duo screenshots (four per display) have also completed.
  A shared accepted-resolution native gameplay video was added to the Duo group;
  verify final Apple processing before submission. No runner captures store media.
- App Privacy is published, including the approved ad SDK/Game Center disclosures.
  The privacy URL is `https://corsairlabs.com/garden-ninja-privacy-policy`.
- App Review contact and gameplay/IAP notes are now populated. Sign-in is optional
  and the version remains set to manual release after App Review.
- The requested existing Apple team member was added to Garden Ninja Internal;
  invitation state is INVITED. No staff role was created or expanded. This internal
  tester does not need external Beta App Review. Use the exact invited Apple ID
  in TestFlight. Tester emails remain outside this public repository.

## Still required before public launch

- Complete the App Information age-rating questionnaire and Content Rights
  declaration; both currently show Set Up controls. DSA trader status is set.
- Select the tested, processed build for the editable 1.1.7 App Store version.
  It initially had no build attached and remains PREPARE_FOR_SUBMISSION.
- Include the first Remove Ads non-consumable with the initial App Review
  submission. Product `garden_ninja_remove_ads` is READY_TO_SUBMIT, not approved.
- Run signed-device smoke tests: both games, Game Center, audio/resume, ads for
  eligible adults, under-16 ad exclusion, sandbox purchase and restore. Native
  StoreKit simulator tests are not a substitute for real-device/store validation.
- Submit the tested app and initial IAP to App Review. After approval, manually
  release the version; CI uploads to testing and does not publish automatically.
- After the public Apple URL exists, connect it in Meta, Chartboost, InMobi and
  Liftoff, finish provider verification, and disable test/developer modes. Then
  verify real fill without interacting with live ads as a test.

Optional merchandising such as header creative, extra localizations and an
Accessibility Nutrition Label is separate from a completed App Review submission.
This audit does not claim approval of unsubmitted app/IAP content.
