# Remove Ads purchases

The approved product is **Remove Ads**, a permanent non-consumable with a
**US$2.99** base price. Both stores use `garden_ninja_remove_ads`. The app displays
the store's localized price. This is not a subscription or coin pack.

The home screen and Tools shop include purchase and **Restore Purchases**.
Ownership removes banners and automatic interstitial breaks. Optional rewarded
videos remain available. Restore uses the same Apple or Google account;
ownership does not transfer between stores.

## Verification

Startup restore gates automatic ads. The app checks ownership again on resume.
Pending, cancelled, failed and unverified purchases never grant ad removal.
Successful empty store queries revoke refunded/account-switched ownership;
temporary store failures preserve previously verified offline ownership.

Apple uses StoreKit 2 verified current entitlements, with a transaction-ID match
for new purchase events. Purchase status alone is not trusted. Android verifies
Google's signed JSON using this app's public licensing key, checks app/SKU/state/
token, and acknowledges without consuming the non-consumable. Its cache contains
signed proof, not an editable game-save Boolean. The public verification key is
intentionally shipped in the app; it is not a private API credential.

Verification is on-device. There is no validation backend or real-time purchase
notification receiver. Offline proof can remain usable until a successful store
query detects a refund; a patched client can bypass client-side checks. A server
would be required for stronger fraud prevention and immediate refund handling.
Purchase tokens are not logged or sent to a Corsair Labs purchase server.

## Catalog setup

Apple product `6835186950` belongs to app `6834694197`, bundle
`com.corsairlabs.gardenNinja`. On 2026-11-15 its English metadata, US$2.99 base
price, automatic local equivalents, availability and review screenshot were set.
Apple reported **READY_TO_SUBMIT**, and the screenshot **COMPLETE**. The first
purchase must accompany the app's App Review submission; it is not approved for sale.

Google product `garden_ninja_remove_ads` was confirmed **ACTIVE** on 2026-11-15,
after Android's first billing-enabled build **10064** uploaded to internal testing.
The verified buy option is permanent, single-quantity, legacy-compatible and
available in the US at **US$2.99**, with Google's localized pricing equivalents.
[The read-only catalog verification](https://github.com/ibsam588-lgtm/garden-ninja/actions/runs/43759522586)
succeeded. No customer purchase was performed.

For later inspection, run **Configure approved Remove Ads product** on `main`
with `apply=false`; `apply=true` creates/activates the approved option when needed.
It uses `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`. A normal push never changes prices.
The tool refuses a different app, SKU, price, rental/multi-quantity option or
incompatible billing setup and leaves unrelated products untouched.

## Verified delivery (2026-11-15)

- [PR 74](https://github.com/ibsam588-lgtm/garden-ninja/pull/74) merged after all
  checks passed: 74 Flutter tests, five native Android verification tests,
  Android release, iPhone/iPad release, simulator launch and a native StoreKit
  purchase → finish → restore → refund test with zero failures.
- GitHub uploaded **Android 10064** to Play internal testing and **iOS 1.1.7 (7)**
  to App Store Connect. Apple reported build 7 **VALID**. These are testing
  deliveries; they do not promote Android to production or submit Apple App Review.
- Catalog tooling subsequently passed 25 Python tests. Its corrections and these
  documentation changes do not match native build/upload path filters.
- Signed release inspection confirmed the local `.storekit` test catalog is absent
  from the shipped app. Apple reported the product review screenshot **COMPLETE**.

The remaining acceptance work is real Play sandbox purchase testing and signed
device ad-fill checks. No Android device was attached in this session. Apple's
first IAP still needs its normal App Review submission with a supported app build.

## Verification and acceptance

- Flutter tests cover purchase outcomes, duplicate taps, restore, refunds/account
  switches, offline ownership, stale responses, disposal and a narrow screen.
- Android unit tests check signature tampering, wrong keys/app/SKU, pending and
  incomplete receipts and production public-key encoding.
- iOS CI runs native StoreKit Test purchase → finish → restore → refund. Its
  `.storekit` configuration belongs only to the test target, never the release app.
- Store acceptance requires an internal Play/TestFlight installation with a test
  account. Verify purchase, restart, reinstall/restore, refund, automatic-ad
  removal and optional rewarded video. Unit/simulator tests do not prove live
  store billing availability or live ad fill.

Render the actual purchase sheet for review without a payment:

```sh
flutter test test/store_media/purchase_review_capture_test.dart --dart-define=CAPTURE_PURCHASE_REVIEW=true --dart-define=STORE_SCREENSHOTS=true
```

Output: `build/purchase-review/remove-ads.png`. A test gateway supplies the approved
price; this is a UI capture, not proof of a completed store transaction.
