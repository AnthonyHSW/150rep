import SwiftUI

struct AppColors {
    static let brandBlue = Color(red: 0.188, green: 0.365, blue: 0.718) // #305DB7
    static let brandBlueDark = Color(red: 0.565, green: 0.702, blue: 0.976) // #90B3F9

    static let pageBackground = Color(UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.118, green: 0.118, blue: 0.118, alpha: 1) // #1E1E1E
            : UIColor(red: 0.961, green: 0.976, blue: 0.988, alpha: 1) // #F5F6FC
    })

    static let contentSurface = Color(UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(red: 0.165, green: 0.165, blue: 0.165, alpha: 1) // #2A2A2A
            : UIColor.white
    })

    // Crowding colors
    static let quiet = Color(red: 0.188, green: 0.365, blue: 0.718) // Blue
    static let moderate = Color(red: 0.2, green: 0.6, blue: 0.7) // Teal
    static let busy = Color(red: 1, green: 0.6, blue: 0.2) // Orange
    static let packed = Color(red: 1, green: 0.3, blue: 0.3) // Red

    static func crowdingColor(for level: Int) -> Color {
        switch level {
        case 1...3:
            return quiet
        case 4...6:
            return moderate
        case 7...8:
            return busy
        default:
            return packed
        }
    }

    static func crowdingLabel(for level: Int) -> String {
        switch level {
        case 1...3:
            return "Quiet"
        case 4...6:
            return "Moderate"
        case 7...8:
            return "Busy"
        default:
            return "Packed"
        }
    }
}
