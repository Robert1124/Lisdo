import XCTest
@testable import LisdoCore

final class EntitlementTests: XCTestCase {
    func testFeatureGatesMatchPlanTiers() {
        let free = LisdoEntitlementSnapshot(tier: .free)
        XCTAssertTrue(free.isFeatureEnabled(.byokAndCLI))
        XCTAssertFalse(free.isFeatureEnabled(.lisdoManagedDrafts))
        XCTAssertFalse(free.isFeatureEnabled(.iCloudSync))
        XCTAssertFalse(free.isFeatureEnabled(.realtimeVoice))
        XCTAssertEqual(free.quotaBalance.monthlyNonRolloverUnits, 0)

        let starterTrial = LisdoEntitlementSnapshot(tier: .starterTrial)
        XCTAssertTrue(starterTrial.isFeatureEnabled(.lisdoManagedDrafts))
        XCTAssertFalse(starterTrial.isFeatureEnabled(.iCloudSync))
        XCTAssertTrue(starterTrial.isFeatureEnabled(.realtimeVoice))
        XCTAssertEqual(starterTrial.quotaBalance.monthlyNonRolloverUnits, 1_500)

        let monthlyBasic = LisdoEntitlementSnapshot(tier: .monthlyBasic)
        XCTAssertTrue(monthlyBasic.isFeatureEnabled(.iCloudSync))
        XCTAssertTrue(monthlyBasic.isFeatureEnabled(.lisdoManagedDrafts))
        XCTAssertFalse(monthlyBasic.isFeatureEnabled(.realtimeVoice))
        XCTAssertEqual(monthlyBasic.quotaBalance.monthlyNonRolloverUnits, 3_000)

        let monthlyPlus = LisdoEntitlementSnapshot(tier: .monthlyPlus)
        XCTAssertTrue(monthlyPlus.isFeatureEnabled(.iCloudSync))
        XCTAssertTrue(monthlyPlus.isFeatureEnabled(.lisdoManagedDrafts))
        XCTAssertFalse(monthlyPlus.isFeatureEnabled(.realtimeVoice))
        XCTAssertEqual(monthlyPlus.quotaBalance.monthlyNonRolloverUnits, 12_000)

        let monthlyMax = LisdoEntitlementSnapshot(tier: .monthlyMax)
        XCTAssertTrue(monthlyMax.isFeatureEnabled(.iCloudSync))
        XCTAssertTrue(monthlyMax.isFeatureEnabled(.lisdoManagedDrafts))
        XCTAssertTrue(monthlyMax.isFeatureEnabled(.realtimeVoice))
        XCTAssertEqual(monthlyMax.quotaBalance.monthlyNonRolloverUnits, 50_000)
    }

    func testDefaultQuotaBalancesUseManagedCostUnits() {
        XCTAssertEqual(LisdoEntitlementSnapshot.defaultMonthlyNonRolloverUnits(for: .free), 0)
        XCTAssertEqual(LisdoEntitlementSnapshot.defaultMonthlyNonRolloverUnits(for: .starterTrial), 1_500)
        XCTAssertEqual(LisdoEntitlementSnapshot.defaultMonthlyNonRolloverUnits(for: .monthlyBasic), 3_000)
        XCTAssertEqual(LisdoEntitlementSnapshot.defaultMonthlyNonRolloverUnits(for: .monthlyPlus), 12_000)
        XCTAssertEqual(LisdoEntitlementSnapshot.defaultMonthlyNonRolloverUnits(for: .monthlyMax), 50_000)
    }

    func testCostUnitConsumptionUsesMonthlyBeforeTopUpWithoutMutatingSnapshot() {
        let startingBalance = LisdoQuotaBalance(monthlyNonRolloverUnits: 3_000, topUpRolloverUnits: 1_500)
        let snapshot = LisdoEntitlementSnapshot(tier: .monthlyBasic, quotaBalance: startingBalance)

        let result = snapshot.consumingManagedCostUnits(3_750)

        XCTAssertTrue(result.isAllowed)
        XCTAssertEqual(result.consumedMonthlyNonRolloverUnits, 3_000)
        XCTAssertEqual(result.consumedTopUpRolloverUnits, 750)
        XCTAssertEqual(result.remainingBalance.monthlyNonRolloverUnits, 0)
        XCTAssertEqual(result.remainingBalance.topUpRolloverUnits, 750)
        XCTAssertEqual(result.insufficientUnits, 0)
        XCTAssertEqual(snapshot.quotaBalance, startingBalance)
    }

    func testInsufficientQuotaDoesNotPartiallyConsume() {
        let startingBalance = LisdoQuotaBalance(monthlyNonRolloverUnits: 1, topUpRolloverUnits: 2)
        let snapshot = LisdoEntitlementSnapshot(tier: .monthlyPlus, quotaBalance: startingBalance)

        let result = snapshot.consumingDraftUnits(4)

        XCTAssertFalse(result.isAllowed)
        XCTAssertEqual(result.consumedMonthlyNonRolloverUnits, 0)
        XCTAssertEqual(result.consumedTopUpRolloverUnits, 0)
        XCTAssertEqual(result.remainingBalance, startingBalance)
        XCTAssertEqual(result.insufficientUnits, 1)
        XCTAssertEqual(snapshot.quotaBalance, startingBalance)
    }

    func testTopUpQuotaIsOnlyUsableForPaidMonthlyPlans() {
        let trialSnapshot = LisdoEntitlementSnapshot(
            tier: .starterTrial,
            quotaBalance: LisdoQuotaBalance(monthlyNonRolloverUnits: 0, topUpRolloverUnits: 10)
        )
        let trialResult = trialSnapshot.consumingDraftUnits(1)
        XCTAssertFalse(trialResult.isAllowed)
        XCTAssertEqual(trialResult.consumedTopUpRolloverUnits, 0)
        XCTAssertEqual(trialResult.remainingBalance.topUpRolloverUnits, 10)
        XCTAssertEqual(trialResult.insufficientUnits, 1)

        let paidSnapshot = LisdoEntitlementSnapshot(
            tier: .monthlyMax,
            quotaBalance: LisdoQuotaBalance(monthlyNonRolloverUnits: 0, topUpRolloverUnits: 2)
        )
        let paidResult = paidSnapshot.consumingDraftUnits(2)
        XCTAssertTrue(paidResult.isAllowed)
        XCTAssertEqual(paidResult.consumedTopUpRolloverUnits, 2)
        XCTAssertEqual(paidResult.remainingBalance.topUpRolloverUnits, 0)
    }

    func testPlansWithoutLisdoManagedDraftsCannotConsumeManagedQuota() {
        let startingBalance = LisdoQuotaBalance(monthlyNonRolloverUnits: 5, topUpRolloverUnits: 5)
        let snapshot = LisdoEntitlementSnapshot(tier: .free, quotaBalance: startingBalance)

        let result = snapshot.consumingDraftUnits(1)

        XCTAssertFalse(result.isAllowed)
        XCTAssertEqual(result.consumedMonthlyNonRolloverUnits, 0)
        XCTAssertEqual(result.consumedTopUpRolloverUnits, 0)
        XCTAssertEqual(result.remainingBalance, startingBalance)
        XCTAssertEqual(result.insufficientUnits, 1)
    }

    func testNonPositiveQuotaRequestsAreRejectedWithoutChangingBalance() {
        let startingBalance = LisdoQuotaBalance(monthlyNonRolloverUnits: 5, topUpRolloverUnits: 5)
        let snapshot = LisdoEntitlementSnapshot(tier: .monthlyBasic, quotaBalance: startingBalance)

        let result = snapshot.consumingDraftUnits(0)

        XCTAssertFalse(result.isAllowed)
        XCTAssertEqual(result.remainingBalance, startingBalance)
        XCTAssertEqual(result.insufficientUnits, 0)
    }

    func testManagedProviderGateRequiresSignInBeforePlanOrQuotaChecks() {
        let freeSnapshot = LisdoEntitlementSnapshot(tier: .free)
        XCTAssertEqual(
            LisdoManagedProviderGate.decision(
                snapshot: freeSnapshot,
                hasLisdoAccountSession: false
            ),
            .requiresSignIn
        )

        let exhaustedPaidSnapshot = LisdoEntitlementSnapshot(
            tier: .monthlyBasic,
            quotaBalance: LisdoQuotaBalance(monthlyNonRolloverUnits: 0, topUpRolloverUnits: 0)
        )
        XCTAssertEqual(
            LisdoManagedProviderGate.decision(
                snapshot: exhaustedPaidSnapshot,
                hasLisdoAccountSession: false,
                requestedDraftUnits: 2
            ),
            .requiresSignIn
        )
    }

    func testManagedProviderGateRequiresPlanForSignedInFreeEntitlement() {
        let snapshot = LisdoEntitlementSnapshot(
            tier: .free,
            quotaBalance: LisdoQuotaBalance(monthlyNonRolloverUnits: 10, topUpRolloverUnits: 10)
        )

        XCTAssertEqual(
            LisdoManagedProviderGate.decision(
                snapshot: snapshot,
                hasLisdoAccountSession: true
            ),
            .planRequired
        )
    }

    func testManagedProviderGateReportsQuotaExhaustedForEntitledPlansWithoutUsableUnits() {
        let trialSnapshot = LisdoEntitlementSnapshot(
            tier: .starterTrial,
            quotaBalance: LisdoQuotaBalance(monthlyNonRolloverUnits: 0, topUpRolloverUnits: 10)
        )
        XCTAssertEqual(
            LisdoManagedProviderGate.decision(
                snapshot: trialSnapshot,
                hasLisdoAccountSession: true
            ),
            .quotaExhausted
        )

        let paidSnapshot = LisdoEntitlementSnapshot(
            tier: .monthlyPlus,
            quotaBalance: LisdoQuotaBalance(monthlyNonRolloverUnits: 0, topUpRolloverUnits: 0)
        )
        XCTAssertEqual(
            LisdoManagedProviderGate.decision(
                snapshot: paidSnapshot,
                hasLisdoAccountSession: true
            ),
            .quotaExhausted
        )
    }

    func testManagedProviderGateAllowsEntitledPlansWithEnoughRequestedDraftUnits() {
        let trialSnapshot = LisdoEntitlementSnapshot(
            tier: .starterTrial,
            quotaBalance: LisdoQuotaBalance(monthlyNonRolloverUnits: 1)
        )
        XCTAssertEqual(
            LisdoManagedProviderGate.decision(
                snapshot: trialSnapshot,
                hasLisdoAccountSession: true
            ),
            .allowed
        )

        let paidSnapshot = LisdoEntitlementSnapshot(
            tier: .monthlyBasic,
            quotaBalance: LisdoQuotaBalance(monthlyNonRolloverUnits: 1, topUpRolloverUnits: 1)
        )
        XCTAssertEqual(
            LisdoManagedProviderGate.decision(
                snapshot: paidSnapshot,
                hasLisdoAccountSession: true,
                requestedDraftUnits: 2
            ),
            .allowed
        )
    }

    func testManagedProviderGateComparesRequestedDraftUnitsAgainstUsableQuota() {
        let snapshot = LisdoEntitlementSnapshot(
            tier: .monthlyBasic,
            quotaBalance: LisdoQuotaBalance(monthlyNonRolloverUnits: 1, topUpRolloverUnits: 0)
        )

        XCTAssertEqual(
            LisdoManagedProviderGate.decision(
                snapshot: snapshot,
                hasLisdoAccountSession: true,
                requestedDraftUnits: 2
            ),
            .quotaExhausted
        )
    }
}
