import SwiftUI

/// Keys for `@AppStorage`, spelled once so two views can't drift onto different settings.
enum PreferenceKey {
    static let weightUnit = "weightUnit"
    static let appearance = "appearance"
}

/// The unit weights are shown and entered in.
///
/// Storage stays in kilograms whatever this is set to. `ExerciseSet.weight` carries no unit
/// of its own and every workout recorded so far was written as kilograms, so converting only
/// at the edges keeps one canonical number in the store: switching units relabels existing
/// history rather than reinterpreting it, and a synced row never leaves the server guessing
/// which unit it's in.
enum WeightUnit: String, CaseIterable, Identifiable {
    case kilograms
    case pounds

    var id: String { rawValue }

    /// Spelled out, for the settings picker.
    var name: String {
        switch self {
        case .kilograms: "Kilograms"
        case .pounds: "Pounds"
        }
    }

    /// Short form for column headings and inline values.
    var abbreviation: String {
        switch self {
        case .kilograms: "kg"
        case .pounds: "lbs"
        }
    }

    private static let poundsPerKilogram = 2.2046226218

    /// Stored kilograms into the unit on screen.
    func fromKilograms(_ kilograms: Double) -> Double {
        switch self {
        case .kilograms: kilograms
        case .pounds: kilograms * Self.poundsPerKilogram
        }
    }

    /// A number the user typed back into kilograms for storage.
    func toKilograms(_ value: Double) -> Double {
        switch self {
        case .kilograms: value
        case .pounds: value / Self.poundsPerKilogram
        }
    }

    /// A stored weight as text in this unit: one decimal at most, and none when the value is
    /// whole. Without the rounding, a tidy 60 kg reads as 132.27735730800002 lbs.
    func displayText(fromKilograms kilograms: Double) -> String {
        let rounded = (fromKilograms(kilograms) * 10).rounded() / 10
        return rounded.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(rounded))
            : String(format: "%.1f", rounded)
    }
}

/// Which appearance the app forces, if any.
enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var name: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` hands the choice back to iOS, which is exactly what `preferredColorScheme`
    /// treats as "follow the system" — so "System" needs no special case at the call site.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
