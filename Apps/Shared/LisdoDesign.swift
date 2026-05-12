import SwiftUI

public enum LisdoDesign {
    public enum ColorToken {
        public static let surface = Color(hex: 0xFFFFFF)
        public static let surface2 = Color(hex: 0xFAFAFA)
        public static let surface3 = Color(hex: 0xF2F2F2)
        public static let divider = Color(hex: 0xE5E5E5)
        public static let ink1 = Color(hex: 0x111111)
        public static let ink2 = Color(hex: 0x2C2C2E)
        public static let ink3 = Color(hex: 0x6E6E73)
        public static let ink4 = Color(hex: 0xA1A1A6)
        public static let ink5 = Color(hex: 0xC7C7CC)
        public static let ink7 = Color(hex: 0xEFEFEF)
        public static let onAccent = Color(hex: 0xFFFFFF)
        public static let ok = Color(hex: 0x4A4A4D)
        public static let warn = Color(hex: 0x5C5C60)
        public static let info = Color(hex: 0x6E6E73)
        public static let shopping = Color(hex: 0x6E6E73)
        public static let research = Color(hex: 0x6E6E73)
        public static let personal = Color(hex: 0x6E6E73)
        public static let homeErrands = Color(hex: 0x6E6E73)
    }

    public enum Radius {
        public static let xs: CGFloat = 6
        public static let sm: CGFloat = 10
        public static let md: CGFloat = 14
        public static let lg: CGFloat = 20
        public static let xl: CGFloat = 28
    }

    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
    }
}

public extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}
