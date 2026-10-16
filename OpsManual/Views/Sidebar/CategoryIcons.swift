import Foundation

enum CategoryIcons {
    enum Icon: Equatable { case symbol(String), asset(String) }

    /// Brand marks from the asset catalog, for categories named after a service.
    private static let assets: [String: String] = [
        "GitHub": "brand-github",
    ]

    private static let map: [String: String] = [
        "Accounts": "person.crop.circle",
        "Agents": "cpu",
        "APIs": "powerplug",
        "App Store": "bag",
        "Automations": "bolt",
        "CLI tools": "terminal",
        "Deployments": "paperplane",
        "Domains": "globe",
        "Hooks": "link",
        "Machines": "laptopcomputer",
        "Maintenance": "wrench",
        "MCP (mine)": "server.rack",
        "MCP (third-party)": "square.stack.3d.up",
        "Recovery": "lifepreserver",
        "Self-hosted": "internaldrive",
        "Services": "waveform.path.ecg",
        "Skills": "sparkles",
    ]

    static func symbol(for category: String) -> String { map[category] ?? "folder" }

    static func icon(for category: String) -> Icon {
        assets[category].map(Icon.asset) ?? .symbol(symbol(for: category))
    }
}
