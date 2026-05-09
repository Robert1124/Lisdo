import SwiftUI

enum LisdoTheme {
    static let surface = LisdoDesign.ColorToken.surface
    static let surface2 = LisdoDesign.ColorToken.surface2
    static let surface3 = LisdoDesign.ColorToken.surface3
    static let divider = LisdoDesign.ColorToken.divider
    static let ink1 = LisdoDesign.ColorToken.ink1
    static let ink2 = LisdoDesign.ColorToken.ink2
    static let ink3 = LisdoDesign.ColorToken.ink3
    static let ink4 = LisdoDesign.ColorToken.ink4
    static let ink5 = LisdoDesign.ColorToken.ink5
    static let ink7 = LisdoDesign.ColorToken.ink7
    static let onAccent = LisdoDesign.ColorToken.onAccent
    static let ok = LisdoDesign.ColorToken.ok
    static let warn = LisdoDesign.ColorToken.warn
    static let info = LisdoDesign.ColorToken.info
    static let shopping = LisdoDesign.ColorToken.shopping
    static let research = LisdoDesign.ColorToken.research
    static let personal = LisdoDesign.ColorToken.personal
    static let homeErrands = LisdoDesign.ColorToken.homeErrands
}

extension View {
    func lisdoCard(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(LisdoTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(LisdoTheme.divider.opacity(0.8), lineWidth: 1)
            }
            .shadow(color: LisdoTheme.ink1.opacity(0.035), radius: 10, y: 4)
    }

    func lisdoDashedDraft() -> some View {
        self
            .background(LisdoTheme.surface2.opacity(0.76))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                    .foregroundStyle(LisdoTheme.ink1.opacity(0.22))
            }
            .shadow(color: LisdoTheme.ink1.opacity(0.03), radius: 12, y: 6)
    }
}

struct LisdoSectionHeader: View {
    var title: String
    var detail: String?

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(LisdoTheme.ink3)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(LisdoTheme.ink3)
            }
        }
    }
}

struct LisdoDraftChip: View {
    var body: some View {
        Label("Draft", systemImage: "sparkle")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(LisdoTheme.ink2)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(LisdoTheme.ink1.opacity(0.05), in: Capsule())
    }
}

struct LisdoCategoryDot: View {
    var categoryId: String?

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
    }

    private var color: Color {
        switch categoryId {
        case "work", "lisdo.default.work": LisdoTheme.info
        case "shopping", "lisdo.default.shopping": LisdoTheme.shopping
        case "research", "lisdo.default.research": LisdoTheme.research
        case "personal", "lisdo.default.personal": LisdoTheme.personal
        case "home", "lisdo.default.errands": LisdoTheme.homeErrands
        default: LisdoTheme.ink1
        }
    }
}
