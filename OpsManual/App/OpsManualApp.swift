import SwiftUI
import AppKit

@main
struct OpsManualApp: App {
    @State private var store: DocumentStore
    @State private var state = AppState()
    @AppStorage(AppSettings.appearanceKey) private var appearanceRaw = AppearancePreference.system.rawValue

    init() {
        // Set the Dock tile from the bundle so a stale system icon cache can never show an old icon.
        if let icon = NSImage(named: "AppIcon") { NSApplication.shared.applicationIconImage = icon }
        _store = State(initialValue: DocumentStore(folder: AppSettings.documentsURL))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store, state: state)
                .preferredColorScheme((AppearancePreference(rawValue: appearanceRaw) ?? .system).colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 720)
        .commands { OpsCommands(state: state, store: store) }

        Settings {
            SettingsView(store: store)
                .preferredColorScheme((AppearancePreference(rawValue: appearanceRaw) ?? .system).colorScheme)
        }
    }
}
