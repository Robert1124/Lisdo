import SwiftUI

public enum LisdoDesign {
    public enum ColorToken {
        public static let surface = Color(hex: 0xF8F5EF)
        public static let surface2 = Color(hex: 0xEFE8DD)
        public static let surface3 = Color(hex: 0xE4DACD)
        public static let divider = Color(hex: 0xD6CBBB)
        public static let ink1 = Color(hex: 0x28251F)
        public static let ink2 = Color(hex: 0x453F36)
        public static let ink3 = Color(hex: 0x71695E)
        public static let ink4 = Color(hex: 0x9A9080)
        public static let ink5 = Color(hex: 0xC4B9A8)
        public static let ink7 = Color(hex: 0xEDE6DC)
        public static let onAccent = Color(hex: 0xFFFDF8)
        public static let ok = Color(hex: 0x637160)
        public static let warn = Color(hex: 0x9A7A58)
        public static let info = Color(hex: 0x6D7880)
        public static let shopping = Color(hex: 0x8A7765)
        public static let research = Color(hex: 0x68735F)
        public static let personal = Color(hex: 0x817286)
        public static let homeErrands = Color(hex: 0x9A9080)
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
