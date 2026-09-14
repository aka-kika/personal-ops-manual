import Foundation

enum CategoryIcons {
    private static let map: [String: String] = [
        "Agents": "cpu",
        "APIs": "powerplug",
        "Automations": "bolt",
        "Backups": "clock.arrow.circlepath",
        "Deployments": "paperplane",
        "Domains": "globe",
        "Hooks": "link",
        "Machines": "laptopcomputer",
        "Maintenance": "wrench",
        "Manual": "info.circle",
        "MCP (mine)": "server.rack",
        "MCP (third-party)": "square.stack.3d.up",
        "Recovery": "lifepreserver",
        "Releases": "shippingbox",
        "Self-hosted": "internaldrive",
        "Services": "waveform.path.ecg",
        "Skills": "sparkles",
    ]

    static func symbol(for category: String) -> String { map[category] ?? "folder" }
}
