import Foundation

public enum CategoryFallbackReason: Equatable, Sendable {
    case acceptedRecommendation
    case missingRecommendation
    case unknownRecommendation
    case lowConfidence
    case fallbackUnavailable
}

public struct CategoryRecommendation: Equatable, Sendable {
    public var categoryId: String
    public var reason: CategoryFallbackReason

    public init(categoryId: String, reason: CategoryFallbackReason) {
        self.categoryId = categoryId
        self.reason = reason
    }
}

public enum CategoryRecommender {
    public static func resolveCategory(
        for draft: ProcessingDraft,
        availableCategories: [Category],
        fallbackCategoryId: String,
        minimumConfidence: Double = 0.4
    ) -> CategoryRecommendation {
        let categoryIds = Set(availableCategories.map(\.id))
        let fallbackId = categoryIds.contains(fallbackCategoryId) ? fallbackCategoryId : (availableCategories.first?.id ?? fallbackCategoryId)

        guard let recommendedId = draft.recommendedCategoryId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !recommendedId.isEmpty
        else {
            return CategoryRecommendation(categoryId: fallbackId, reason: .missingRecommendation)
        }

        guard categoryIds.contains(recommendedId) else {
            return CategoryRecommendation(categoryId: fallbackId, reason: .unknownRecommendation)
        }

        guard let confidence = draft.confidence, confidence >= minimumConfidence else {
            return CategoryRecommendation(categoryId: fallbackId, reason: .lowConfidence)
        }

        return CategoryRecommendation(categoryId: recommendedId, reason: .acceptedRecommendation)
    }
}
