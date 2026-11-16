import StoreKit
import StoreKitTest
import XCTest

@available(iOS 17.0, *)
@MainActor
final class RunnerTests: XCTestCase {
  private let productID = "garden_ninja_remove_ads"

  private func ownsRemoveAds() async -> Bool {
    for await result in Transaction.currentEntitlements {
      if case .verified(let transaction) = result,
         transaction.productID == productID, transaction.revocationDate == nil {
        return true
      }
    }
    return false
  }

  // SKTestSession can return before StoreKit 2 publishes its entitlement update.
  // Wait for the real verified state, with a bounded failure deadline.
  private func waitForOwnership(_ expected: Bool) async throws -> Bool {
    for _ in 0..<50 {
      if await ownsRemoveAds() == expected { return true }
      try await Task.sleep(for: .milliseconds(200))
    }
    return false
  }

  func testNonConsumablePurchaseRestorationAndRefund() async throws {
    let file = try XCTUnwrap(Bundle(for: Self.self).url(
      forResource: "GardenNinjaPurchases", withExtension: "storekit"))
    let session = try SKTestSession(contentsOf: file)
    session.resetToDefaultState()
    session.clearTransactions()
    session.disableDialogs = true
    defer { session.clearTransactions() }

    let initialOwnership = await ownsRemoveAds()
    XCTAssertFalse(initialOwnership)
    let products = try await Product.products(for: [productID])
    let product = try XCTUnwrap(products.first)
    XCTAssertEqual(product.id, productID)
    XCTAssertEqual(product.type, .nonConsumable)
    XCTAssertEqual(product.price, Decimal(string: "2.99"))

    let transaction = try await session.buyProduct(identifier: productID)
    XCTAssertEqual(transaction.environment, .xcode,
                   "Native fixture purchases must stay in the local Xcode environment")
    guard transaction.environment == .xcode else { return }
    await transaction.finish()
    let paidOwnership = try await waitForOwnership(true)
    XCTAssertTrue(paidOwnership, "Purchase must publish the verified entitlement")
    // Do not open a sandbox account dialog after an already-failed local test.
    guard paidOwnership else { return }

    // AppStore.sync is the same explicit restore operation used by the plugin.
    try await AppStore.sync()
    let restoredOwnership = try await waitForOwnership(true)
    XCTAssertTrue(restoredOwnership, "Restore must retain the verified entitlement")
    XCTAssertEqual(session.allTransactions().count, 1)

    try session.refundTransaction(identifier: UInt(transaction.id))
    let refunded = try await waitForOwnership(false)
    XCTAssertTrue(refunded, "Refund must remove the verified non-consumable entitlement")
  }
}
