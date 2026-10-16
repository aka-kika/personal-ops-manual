import Foundation

enum CategoryIcons {
    private static let map: [String: String] = [
        "Accounts": "person.crop.circle",
        "Agents": "cpu",
        "APIs": "powerplug",
        "App Store": "bag",
        "Automations": "bolt",
        "CLI tools": "terminal",
        "Deployments": "paperplane",
        "Domains": "globe",
        "GitHub": "arrow.triangle.branch",
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
}
