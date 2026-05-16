import XCTest
@testable import LisdoCore

final class StoreProductTests: XCTestCase {
    func testStoreProductsMapToExpectedPlans() {
        XCTAssertEqual(LisdoStoreProductID.starterTrial.planTier, .starterTrial)
        XCTAssertEqual(LisdoStoreProductID.monthlyBasic.planTier, .monthlyBasic)
        XCTAssertEqual(LisdoStoreProductID.monthlyPlus.planTier, .monthlyPlus)
        XCTAssertEqual(LisdoStoreProductID.monthlyMax.planTier, .monthlyMax)
        XCTAssertNil(LisdoStoreProductID.topUpUsage.planTier)
    }

    func testPaidPlanTiersResolveToPurchaseProducts() {
        XCTAssertNil(LisdoStoreProductID.productID(for: .free))
        XCTAssertEqual(LisdoStoreProductID.productID(for: .starterTrial), .starterTrial)
        XCTAssertEqual(LisdoStoreProductID.productID(for: .monthlyBasic), .monthlyBasic)
        XCTAssertEqual(LisdoStoreProductID.productID(for: .monthlyPlus), .monthlyPlus)
        XCTAssertEqual(LisdoStoreProductID.productID(for: .monthlyMax), .monthlyMax)
    }
}
