import SwiftUI

enum Sumi {
    static let ink = Color(red: 13 / 255, green: 10 / 255, blue: 10 / 255)
    static let paper = Color.white
    static let softPaper = Color(red: 250 / 255, green: 250 / 255, blue: 250 / 255)
    static let mist = Color(red: 245 / 255, green: 245 / 255, blue: 245 / 255)
    static let rule = Color(red: 224 / 255, green: 224 / 255, blue: 224 / 255)
    static let paleRule = Color(red: 237 / 255, green: 237 / 255, blue: 237 / 255)
    static let muted = Color(red: 84 / 255, green: 85 / 255, blue: 84 / 255)
    static let wash = Color(red: 247 / 255, green: 245 / 255, blue: 244 / 255)
    static let seal = Color(red: 194 / 255, green: 58 / 255, blue: 46 / 255)
    static let sealDeep = Color(red: 143 / 255, green: 33 / 255, blue: 26 / 255)
    static let sealWash = Color(red: 245 / 255, green: 229 / 255, blue: 227 / 255)
    static let okay = Color(red: 47 / 255, green: 58 / 255, blue: 47 / 255)

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }

    static func body(_ size: CGFloat = 14) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }

    static func label(_ size: CGFloat = 10) -> Font {
        .system(size: size, weight: .medium, design: .serif)
    }
}

extension View {
    func sumiLabelTracking() -> some View {
        tracking(1.5)
            .textCase(.uppercase)
    }
}
