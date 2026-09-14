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

    /// Where pages live until the user picks a folder in Settings.
    static var defaultDocumentsPath: String {
        NSHomeDirectory() + "/Documents/Personal Ops Manual"
    }

    static var documentsURL: URL {
        let path = UserDefaults.standard.string(forKey: documentsPathKey) ?? ""
        return URL(fileURLWithPath: path.isEmpty ? defaultDocumentsPath : path)
    }
}
