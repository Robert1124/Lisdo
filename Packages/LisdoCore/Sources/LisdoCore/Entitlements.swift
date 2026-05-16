import Foundation

public enum LisdoPlanTier: String, Codable, CaseIterable, Sendable {
    case free
    case starterTrial
    case monthlyBasic
    case monthlyPlus
    case monthlyMax
}

public enum LisdoFeature: String, Codable, CaseIterable, Sendable {
    case byokAndCLI
    case lisdoManagedDrafts
    case iCloudSync
    case realtimeVoice
}

public enum LisdoQuotaBucket: String, Codable, CaseIterable, Sendable {
    case monthlyNonRollover
    case topUpRollover
}

public struct LisdoQuotaBalance: Codable, Equatable, Sendable {
    public var monthlyNonRolloverUnits: Int
    public var topUpRolloverUnits: Int

    public init(monthlyNonRolloverUnits: Int, topUpRolloverUnits: Int = 0) {
        self.monthlyNonRolloverUnits = max(0, monthlyNonRolloverUnits)
        self.topUpRolloverUnits = max(0, topUpRolloverUnits)
    }

    public subscript(bucket: LisdoQuotaBucket) -> Int {
        switch bucket {
        case .monthlyNonRollover:
            monthlyNonRolloverUnits
        case .topUpRollover:
            topUpRolloverUnits
        }
    }

    public var totalUnits: Int {
        monthlyNonRolloverUnits + topUpRolloverUnits
    }
}

public struct LisdoQuotaConsumptionResult: Codable, Equatable, Sendable {
    public var requestedUnits: Int
    public var isAllowed: Bool
    public var consumedMonthlyNonRolloverUnits: Int
    public var consumedTopUpRolloverUnits: Int
    public var remainingBalance: LisdoQuotaBalance
    public var insufficientUnits: Int

    public init(
        requestedUnits: Int,
        isAllowed: Bool,
        consumedMonthlyNonRolloverUnits: Int,
        consumedTopUpRolloverUnits: Int,
        remainingBalance: LisdoQuotaBalance,
        insufficientUnits: Int
    ) {
        self.requestedUnits = requestedUnits
        self.isAllowed = isAllowed
        self.consumedMonthlyNonRolloverUnits = consumedMonthlyNonRolloverUnits
        self.consumedTopUpRolloverUnits = consumedTopUpRolloverUnits
        self.remainingBalance = remainingBalance
        self.insufficientUnits = max(0, insufficientUnits)
    }
}

public enum LisdoManagedProviderGateDecision: Equatable, Sendable {
    case allowed
    case requiresSignIn
    case planRequired
    case quotaExhausted
}

public enum LisdoManagedProviderGate {
    public static func decision(
        snapshot: LisdoEntitlementSnapshot,
        hasLisdoAccountSession: Bool,
        requestedDraftUnits: Int = 1
    ) -> LisdoManagedProviderGateDecision {
        guard hasLisdoAccountSession else {
            return .requiresSignIn
        }

        guard snapshot.isFeatureEnabled(.lisdoManagedDrafts) else {
            return .planRequired
        }

        let requestedUnits = max(1, requestedDraftUnits)
        return snapshot.consumingDraftUnits(requestedUnits).isAllowed ? .allowed : .quotaExhausted
    }
}

public struct LisdoEntitlementSnapshot: Codable, Equatable, Sendable {
    public var tier: LisdoPlanTier
    public var quotaBalance: LisdoQuotaBalance

    public init(tier: LisdoPlanTier, quotaBalance: LisdoQuotaBalance? = nil) {
        self.tier = tier
        self.quotaBalance = quotaBalance ?? Self.defaultQuotaBalance(for: tier)
    }

    public var enabledFeatures: Set<LisdoFeature> {
        switch tier {
        case .free:
            return [.byokAndCLI]
        case .starterTrial:
            return [.byokAndCLI, .lisdoManagedDrafts, .realtimeVoice]
        case .monthlyBasic, .monthlyPlus:
            return [.byokAndCLI, .lisdoManagedDrafts, .iCloudSync]
        case .monthlyMax:
            return [.byokAndCLI, .lisdoManagedDrafts, .iCloudSync, .realtimeVoice]
        }
    }

    public var canUseTopUpQuota: Bool {
        switch tier {
        case .monthlyBasic, .monthlyPlus, .monthlyMax:
            return true
        case .free, .starterTrial:
            return false
        }
    }

    public func isFeatureEnabled(_ feature: LisdoFeature) -> Bool {
        enabledFeatures.contains(feature)
    }

    public func consumingManagedCostUnits(_ requestedUnits: Int) -> LisdoQuotaConsumptionResult {
        guard requestedUnits > 0 else {
            return LisdoQuotaConsumptionResult(
                requestedUnits: requestedUnits,
                isAllowed: false,
                consumedMonthlyNonRolloverUnits: 0,
                consumedTopUpRolloverUnits: 0,
                remainingBalance: quotaBalance,
                insufficientUnits: 0
            )
        }

        guard isFeatureEnabled(.lisdoManagedDrafts) else {
            return LisdoQuotaConsumptionResult(
                requestedUnits: requestedUnits,
                isAllowed: false,
                consumedMonthlyNonRolloverUnits: 0,
                consumedTopUpRolloverUnits: 0,
                remainingBalance: quotaBalance,
                insufficientUnits: requestedUnits
            )
        }

        let usableTopUpUnits = canUseTopUpQuota ? quotaBalance.topUpRolloverUnits : 0
        let totalUsableUnits = quotaBalance.monthlyNonRolloverUnits + usableTopUpUnits

        guard totalUsableUnits >= requestedUnits else {
            return LisdoQuotaConsumptionResult(
                requestedUnits: requestedUnits,
                isAllowed: false,
                consumedMonthlyNonRolloverUnits: 0,
                consumedTopUpRolloverUnits: 0,
                remainingBalance: quotaBalance,
                insufficientUnits: requestedUnits - totalUsableUnits
            )
        }

        let monthlyUnits = min(requestedUnits, quotaBalance.monthlyNonRolloverUnits)
        let topUpUnits = requestedUnits - monthlyUnits
        let remainingBalance = LisdoQuotaBalance(
            monthlyNonRolloverUnits: quotaBalance.monthlyNonRolloverUnits - monthlyUnits,
            topUpRolloverUnits: quotaBalance.topUpRolloverUnits - topUpUnits
        )

        return LisdoQuotaConsumptionResult(
            requestedUnits: requestedUnits,
            isAllowed: true,
            consumedMonthlyNonRolloverUnits: monthlyUnits,
            consumedTopUpRolloverUnits: topUpUnits,
            remainingBalance: remainingBalance,
            insufficientUnits: 0
        )
    }

    public func consumingDraftUnits(_ requestedUnits: Int) -> LisdoQuotaConsumptionResult {
        consumingManagedCostUnits(requestedUnits)
    }

    public static func defaultQuotaBalance(for tier: LisdoPlanTier) -> LisdoQuotaBalance {
        LisdoQuotaBalance(monthlyNonRolloverUnits: defaultMonthlyNonRolloverUnits(for: tier))
    }

    public static func defaultMonthlyNonRolloverUnits(for tier: LisdoPlanTier) -> Int {
        switch tier {
        case .free:
            return 0
        case .starterTrial:
            return 1_500
        case .monthlyBasic:
            return 3_000
        case .monthlyPlus:
            return 12_000
        case .monthlyMax:
            return 50_000
        }
    }
}
