# Garden Ninja persistence and review-flow fixes

Date: 2026-10-07

## Reproduced issues

- The version 8 garden save payload persisted seed balance and garden progress, but omitted the selected avatar, selected music track, music/SFX toggles, and ice-charge balance. Reloading after choosing Female Ninja or switching music off therefore restored the defaults even though wallet progress survived.
- The Frost Vine shop purchase reduced seeds and added an ice charge in memory without queuing a garden save. Ice use also reduced the in-memory balance without persisting it. Water and sun purchases use the same purchase handler.
- The results layer titled every loss “Garden Saved,” including the zero-score, zero-weeds loss case, while still awarding the intentional consolation currency and one star.
- No in-app Play review bridge, usage threshold, review cooldown, or manual Play listing action was present in the checked-in app.
- Android version inputs included pubspec `1.1.5+10037`, a local Flutter `versionCode` override of `99999`, checked-in Play metadata `latestBuild: 10049`, and CI's `10000 + GITHUB_RUN_NUMBER` override. GitHub history showed run 51 generated at most `10051` under the old formula. Authenticated Play Console verification confirmed the uploaded maximum is `10049` and latest uploaded name is `1.1.5`.

## Changes

- Bumped the package version to `1.1.6+10050`; Android Gradle enforces a minimum code of `10050` against lower machine-local overrides. The existing local override `99999` remains above the verified Play maximum. CI keeps its monotonic run-number scheme, floors generated codes at `10050`, and explicitly builds version name `1.1.6`.
- Versioned the garden save payload to 9 and added backward-compatible defaults for avatar, audio preferences, music track, and ice balance. Save writes are serialized. Purchases, ice use, run rewards, and preference changes queue an immediate save. Garden music continues to save the player's previously selected track.
- Changed a loss title to “Run Over,” with a clear retry message; consolation rewards and relaxed progression remain unchanged.
- Added a native Play Core review bridge and a manual Rate App action that opens the package's Play listing (with a web listing fallback). Automatic requests require four successful, meaningful run sessions after onboarding. A later request requires four additional successful sessions and at least 30 days; a longer stored cooldown is retained. Requests are reserved persistently and limited to one per app session. Request-flow completion is treated as an attempt only, never proof that Play displayed a card or received a review.
- Automatic requests wait until the result screen settles and skip when an ad, modal, keyboard, update prompt, tutorial, or other unsafe state is active. Play/API failures safely return without interrupting play.

## Regression coverage

- `test/review_prompt_policy_test.dart`: initial four-session threshold, durable state across policy recreation, repeated success and concurrent request events, four-session plus 30-day retry gate, longer cooldown, unavailable/failed platform requests, and ad/dialog/keyboard/onboarding eligibility.
- `test/widget_test.dart`: legacy save migration, persisted avatar/audio/ice values, buying and using ice across an app restart, clear copy for a zero-score loss with the 45-seed consolation reward intact, and the manual Rate App platform action.
- The existing suite contains ad policy, ad loading/placement, garden harvesting/model, and gameplay/widget regressions.

## Validation record

- Source inspection reproduced the persistence omissions and misleading loss title before edits.
- Flutter tests, analyzer, and Android build: pending execution results. The Android build is being held until the parent task grants a shared Gradle/build slot.
- No release, upload, publish, push, or release workflow was run.
