import Foundation

public enum LisdoStoreProductID: String, CaseIterable, Codable, Sendable {
    case starterTrial = "com.yiwenwu.Lisdo.starterTrial"
    case monthlyBasic = "com.yiwenwu.Lisdo.monthlyBasic"
    case monthlyPlus = "com.yiwenwu.Lisdo.monthlyPlus"
    case monthlyMax = "com.yiwenwu.Lisdo.monthlyMax"
    case topUpUsage = "com.yiwenwu.Lisdo.topUpUsage"

    public var planTier: LisdoPlanTier? {
        switch self {
        case .starterTrial:
            return .starterTrial
        case .monthlyBasic:
            return .monthlyBasic
        case .monthlyPlus:
            return .monthlyPlus
        case .monthlyMax:
            return .monthlyMax
        case .topUpUsage:
            return nil
        }
    }

    public var isTopUp: Bool {
        self == .topUpUsage
    }

    public static func productID(for tier: LisdoPlanTier) -> LisdoStoreProductID? {
        switch tier {
        case .free:
            return nil
        case .starterTrial:
            return .starterTrial
        case .monthlyBasic:
            return .monthlyBasic
        case .monthlyPlus:
            return .monthlyPlus
        case .monthlyMax:
            return .monthlyMax
        }
    }

    public var fallbackDisplayName: String {
        switch self {
        case .starterTrial:
            return "Starter Trial"
        case .monthlyBasic:
            return "Monthly Basic"
        case .monthlyPlus:
            return "Monthly Plus"
        case .monthlyMax:
            return "Monthly Max"
        case .topUpUsage:
            return "Usage Top-Up"
        }
    }
}
