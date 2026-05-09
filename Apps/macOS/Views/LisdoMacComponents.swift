import LisdoCore
import SwiftUI

enum LisdoMacTheme {
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
    static let ok = LisdoDesign.ColorToken.ok
    static let warn = LisdoDesign.ColorToken.warn
    static let info = LisdoDesign.ColorToken.info
    static let onAccent = LisdoDesign.ColorToken.onAccent
    static let shopping = LisdoDesign.ColorToken.shopping
    static let research = LisdoDesign.ColorToken.research
    static let personal = LisdoDesign.ColorToken.personal
    static let homeErrands = LisdoDesign.ColorToken.homeErrands
}

enum LisdoMacSelection: Hashable {
    case inbox
    case drafts
    case today
    case plan
    case fromIPhone
    case category(String)
}

extension LisdoMacSelection {
    var title: String {
        switch self {
        case .inbox:
            return "Inbox"
        case .drafts:
            return "Drafts"
        case .today:
            return "Today"
        case .plan:
            return "Plan"
        case .fromIPhone:
            return "From iPhone"
        case .category:
            return "Category"
        }
    }
}

struct LisdoMetric: Identifiable {
    var id: String { title }
    var title: String
    var count: Int
    var systemImage: String
}

struct LisdoSectionHeader<Accessory: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var accessory: Accessory

    init(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            titleBlock
                .layoutPriority(1)

            Spacer(minLength: 12)

            accessory
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}

struct LisdoChip: View {
    let title: String
    let systemImage: String?
    var isDark = false

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            }
            Text(title)
                .font(.caption.weight(.medium))
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(isDark ? LisdoMacTheme.onAccent : LisdoMacTheme.ink3)
        .background(isDark ? LisdoMacTheme.ink1 : LisdoMacTheme.surface2, in: Capsule())
    }
}

extension View {
    @ViewBuilder
    func lisdoGlassSurface(cornerRadius: CGFloat, tint: Color? = nil, interactive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            let glass = interactive ? Glass.regular.interactive() : Glass.regular
            if let tint {
                self.glassEffect(glass.tint(tint), in: shape)
            } else {
                self.glassEffect(glass, in: shape)
            }
        } else {
            self
                .background(.regularMaterial, in: shape)
                .overlay {
                    shape.strokeBorder(LisdoMacTheme.divider.opacity(0.72))
                }
        }
    }

    @ViewBuilder
    func lisdoGlassButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }
}

struct LisdoCategoryDot: View {
    let category: Category?

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }

    private var color: Color {
        switch category?.color?.lowercased() {
        case "work":
            return LisdoMacTheme.info
        case "shopping":
            return LisdoMacTheme.shopping
        case "research":
            return LisdoMacTheme.research
        case "personal":
            return LisdoMacTheme.personal
        default:
            return LisdoMacTheme.homeErrands
        }
    }
}

struct LisdoEmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .padding(.horizontal, 24)
        .background(LisdoMacTheme.surface2, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(LisdoMacTheme.divider.opacity(0.72))
        }
    }
}

struct LisdoPlaceholderPanel: View {
    let systemImage: String
    let title: String
    let bodyText: String
    let milestone: String
    var actionTitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(milestone)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(bodyText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle {
                Button(actionTitle) {}
                    .buttonStyle(.bordered)
                    .disabled(true)
                    .help("This entry is intentionally disabled until the planned MVP milestone.")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LisdoMacTheme.surface2, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(LisdoMacTheme.divider.opacity(0.72))
        }
    }
}

enum LisdoCaptureStatusTone {
    case idle
    case processing
    case success
    case warning
    case failure

    var systemImage: String {
        switch self {
        case .idle:
            return "tray"
        case .processing:
            return "hourglass"
        case .success:
            return "checkmark.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .failure:
            return "xmark.circle"
        }
    }

    var foregroundStyle: Color {
        switch self {
        case .idle, .processing:
            return LisdoMacTheme.ink3
        case .success:
            return LisdoMacTheme.ok
        case .warning:
            return LisdoMacTheme.warn
        case .failure:
            return LisdoMacTheme.warn.opacity(0.92)
        }
    }

    var backgroundStyle: Color {
        switch self {
        case .idle, .processing:
            return LisdoMacTheme.surface2
        case .success:
            return LisdoMacTheme.ok.opacity(0.12)
        case .warning:
            return LisdoMacTheme.warn.opacity(0.12)
        case .failure:
            return LisdoMacTheme.warn.opacity(0.16)
        }
    }
}

struct LisdoCaptureStatusBanner: View {
    let title: String
    let message: String
    let tone: LisdoCaptureStatusTone
    var showsProgress = false

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: tone.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tone.foregroundStyle)
                    .frame(width: 18, height: 18)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(tone.backgroundStyle, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(tone.foregroundStyle.opacity(0.16))
        }
    }
}

extension Array where Element == Category {
    func category(id: String?) -> Category? {
        guard let id else { return nil }
        return first { $0.id == id }
    }

    var defaultCategoryId: String {
        first { $0.id == DefaultCategorySeeder.inboxCategoryId }?.id ?? first?.id ?? DefaultCategorySeeder.inboxCategoryId
    }
}

extension Array where Element == Todo {
    func inCategory(_ categoryId: String) -> [Todo] {
        filter { $0.categoryId == categoryId }
    }
}

extension String {
    var lisdoTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
