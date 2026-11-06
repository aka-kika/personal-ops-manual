import SwiftUI

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum AppSettings {
    static let documentsPathKey = "documentsPath"
    static let showYAMLKey = "showYAML"
    static let appearanceKey = "appearance"
    /// Seconds between Drift's own checks; 0 = Manual (DriftInterval).
    static let driftIntervalKey = "driftInterval"
    /// The last Drift check, so the sidebar count is there at launch.
    static let driftResultsKey = "driftResults"

    /// Where pages live until the user picks a folder in Settings.
    static var defaultDocumentsPath: String {
        NSHomeDirectory() + "/Documents/Personal Ops Manual"
    }

    static var documentsURL: URL {
        let path = UserDefaults.standard.string(forKey: documentsPathKey) ?? ""
        return URL(fileURLWithPath: path.isEmpty ? defaultDocumentsPath : path)
    }
}
