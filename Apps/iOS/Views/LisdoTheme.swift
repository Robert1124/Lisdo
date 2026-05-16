import SwiftUI
import UIKit

enum LisdoTheme {
    static let surface = adaptiveColor(light: 0xFFFFFF, dark: 0x111111)
    static let surface2 = adaptiveColor(light: 0xFAFAFA, dark: 0x1C1C1E)
    static let surface3 = adaptiveColor(light: 0xF2F2F2, dark: 0x2C2C2E)
    static let divider = adaptiveColor(light: 0xE5E5E5, dark: 0x3A3A3C)
    static let ink1 = adaptiveColor(light: 0x111111, dark: 0xF5F5F7)
    static let ink2 = adaptiveColor(light: 0x2C2C2E, dark: 0xE5E5EA)
    static let ink3 = adaptiveColor(light: 0x6E6E73, dark: 0xAEAEB2)
    static let ink4 = adaptiveColor(light: 0xA1A1A6, dark: 0x8E8E93)
    static let ink5 = adaptiveColor(light: 0xC7C7CC, dark: 0x636366)
    static let ink7 = adaptiveColor(light: 0xEFEFEF, dark: 0x2C2C2E)
    static let onAccent = adaptiveColor(light: 0xFFFFFF, dark: 0x111111)
    static let ok = adaptiveColor(light: 0x4A4A4D, dark: 0xD1D1D6)
    static let warn = adaptiveColor(light: 0x5C5C60, dark: 0xC7C7CC)
    static let info = adaptiveColor(light: 0x6E6E73, dark: 0xAEAEB2)
    static let shopping = adaptiveColor(light: 0x6E6E73, dark: 0xAEAEB2)
    static let research = adaptiveColor(light: 0x6E6E73, dark: 0xAEAEB2)
    static let personal = adaptiveColor(light: 0x6E6E73, dark: 0xAEAEB2)
    static let homeErrands = adaptiveColor(light: 0x6E6E73, dark: 0xAEAEB2)

    private static func adaptiveColor(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traitCollection in
            UIColor(lisdoHex: traitCollection.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(lisdoHex hex: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
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

struct LisdoTonalButtonStyle: ButtonStyle {
    var isProminent = false
    var height: CGFloat = 44

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(minHeight: height)
            .padding(.horizontal, 14)
            .background(backgroundColor, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(borderColor, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }

    private var foregroundColor: Color {
        if !isEnabled { return LisdoTheme.ink4 }
        return isProminent ? LisdoTheme.onAccent : LisdoTheme.ink1
    }

    private var backgroundColor: Color {
        if !isEnabled { return LisdoTheme.surface3.opacity(0.55) }
        return isProminent ? LisdoTheme.ink1 : LisdoTheme.surface3.opacity(0.72)
    }

    private var borderColor: Color {
        if !isEnabled { return LisdoTheme.divider.opacity(0.5) }
        return isProminent ? LisdoTheme.ink1 : LisdoTheme.divider.opacity(0.8)
    }
}

struct LisdoInlineDeleteButton: View {
    var accessibilityLabel: String = "Delete"
    var action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "minus.circle")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(LisdoTheme.warn)
                .frame(width: 32, height: 32)
                .background(LisdoTheme.surface3.opacity(0.72), in: Circle())
                .overlay {
                    Circle()
                        .stroke(LisdoTheme.divider.opacity(0.75), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct LisdoProviderFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 15))
            .foregroundStyle(LisdoTheme.ink1)
            .tint(LisdoTheme.ink1)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(LisdoTheme.surface2.opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(LisdoTheme.divider.opacity(0.85), lineWidth: 1)
            }
    }
}

struct LisdoSegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    var options: [(value: Value, title: String)]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .foregroundStyle(selection == option.value ? LisdoTheme.ink1 : LisdoTheme.ink3)
                        .background(
                            selection == option.value ? LisdoTheme.surface : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(LisdoTheme.surface3.opacity(0.72), in: Capsule())
        .overlay {
            Capsule()
                .stroke(LisdoTheme.divider.opacity(0.7), lineWidth: 1)
        }
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
