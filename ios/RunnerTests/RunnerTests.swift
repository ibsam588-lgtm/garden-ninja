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
    await transaction.finish()
    let paidOwnership = await ownsRemoveAds()
    XCTAssertTrue(paidOwnership)

    // AppStore.sync is the same explicit restore operation used by the plugin.
    try await AppStore.sync()
    let restoredOwnership = await ownsRemoveAds()
    XCTAssertTrue(restoredOwnership)
    XCTAssertEqual(session.allTransactions().count, 1)

    try session.refundTransaction(identifier: Int(transaction.id))
    var refunded = false
    for _ in 0..<30 {
      if !(await ownsRemoveAds()) { refunded = true; break }
      try await Task.sleep(for: .milliseconds(200))
    }
    XCTAssertTrue(refunded, "Refund must remove the verified non-consumable entitlement")
  }
}
