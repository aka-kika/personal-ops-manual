import SwiftUI
import AppKit

struct SettingsView: View {
    @Bindable var store: DocumentStore
    @AppStorage(AppSettings.appearanceKey) private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage(AppSettings.documentsPathKey) private var documentsPath = ""
    @AppStorage(AppSettings.showYAMLKey) private var showYAML = false
    @State private var status = ""

    private var mcpText: String {
        Bundle.main.url(forResource: "mcp-install", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }
    private var firstSetupText: String {
        Bundle.main.url(forResource: "FIRST-SETUP", withExtension: "md", subdirectory: "skill").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }
    private var operatorSkillText: String {
        Bundle.main.url(forResource: "OPERATOR", withExtension: "md", subdirectory: "skill").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }
    private var skillText: String {
        Bundle.main.url(forResource: "SKILL", withExtension: "md", subdirectory: "skill").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }

    var body: some View {
        TabView {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearanceRaw) {
                        ForEach(AppearancePreference.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.radioGroup)
                }
                Section("Documents") {
                    LabeledContent("Folder") {
                        HStack {
                            Text(documentsPath.isEmpty ? AppSettings.defaultDocumentsPath : documentsPath)
                                .font(OpsTheme.excerptFont).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                            Button("Choose…", action: chooseFolder)
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.folder]) }
                        }
                    }
                    if !folderExists {
                        Text("Folder not found").font(OpsTheme.metaFont).foregroundStyle(.secondary)
                    }
                    Text("The folder is the source of truth. Any editor or agent may write Markdown files here; the app reloads on change. Keep it somewhere a notes app can also open it, and keep every page self-contained.")
                        .font(OpsTheme.metaFont).foregroundStyle(.secondary)
                    Toggle("Show the Frontmatter section as raw YAML instead of rows", isOn: $showYAML)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                Section("Read-only server") {
                    Text("Seven tools over the same folder: list_categories, list_documents, search_documents, get_document, get_stale, and the inbox pair report_change and list_reports. Pages are never written through the server; reports append to _inbox/reports.md for the operator.")
                        .font(OpsTheme.metaFont).foregroundStyle(.secondary)
                    Text(mcpText).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    Button("Copy Install Snippet") { copy(mcpText) }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("MCP", systemImage: "server.rack") }

            Form {
                Section("Reader skill") {
                    Text("For every agent that reads the manual through the MCP. It also covers the inbox: when an agent changes something in the setup, it files a report with report_change and the operator applies it.")
                        .font(OpsTheme.metaFont).foregroundStyle(.secondary)
                    HStack {
                        Button("Save SKILL.md…") { saveSkill(text: skillText, name: "SKILL.md") }
                        Button("Copy Skill") { copy(skillText) }
                    }
                }
                Section("Operator skill") {
                    Text("For the one agent allowed to create, edit, and delete pages. Not shared with the fleet; install it only in that agent's skills folder.")
                        .font(OpsTheme.metaFont).foregroundStyle(.secondary)
                    HStack {
                        Button("Save OPERATOR.md…") { saveSkill(text: operatorSkillText, name: "OPERATOR.md") }
                        Button("Copy Operator Skill") { copy(operatorSkillText) }
                    }
                }
                Section("First setup") {
                    Text("How to stand the manual up on a new machine and gather the setup into pages. Hand it to the agent doing the install.")
                        .font(OpsTheme.metaFont).foregroundStyle(.secondary)
                    HStack {
                        Button("Save FIRST-SETUP.md…") { saveSkill(text: firstSetupText, name: "FIRST-SETUP.md") }
                        Button("Copy First Setup") { copy(firstSetupText) }
                    }
                }
                if !status.isEmpty {
                    Section { Text(status).font(OpsTheme.metaFont).foregroundStyle(.secondary) }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Skills", systemImage: "sparkles") }

            AboutHeader()
                .padding(.vertical, 24)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560)
        .onChange(of: documentsPath) { _, value in
            store.setFolder(URL(fileURLWithPath: value.isEmpty ? AppSettings.defaultDocumentsPath : value))
        }
    }

    private var folderExists: Bool {
        var isDirectory: ObjCBool = false
        let path = documentsPath.isEmpty ? AppSettings.defaultDocumentsPath : documentsPath
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = store.folder
        if panel.runModal() == .OK, let url = panel.url { documentsPath = url.path }
    }

    private func saveSkill(text: String, name: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        if panel.runModal() == .OK, let url = panel.url {
            do { try text.write(to: url, atomically: true, encoding: .utf8); status = "Saved to \(url.path)" }
            catch { status = error.localizedDescription }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        status = "Copied"
    }
}


/// The app icon, name, version and the author's links, centred at the top of Settings.
private struct AboutHeader: View {
    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        return "Version \(short)"
    }

    var body: some View {
        VStack(spacing: 10) {
            // Straight from the bundle: NSApp.applicationIconImage goes through the
            // system icon cache, which can still hold an older icon.
            Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                .padding(.top, 6)
            VStack(spacing: 3) {
                Text("Personal Ops Manual").font(.system(size: 17, weight: .semibold))
                Text(version).font(OpsTheme.metaFont).foregroundStyle(.secondary)
                Text("Every machine, service and agent, written down once.")
                    .font(OpsTheme.excerptFont).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            HStack(spacing: 10) {
                AboutLink(title: nil, mark: .asset("brand-x"), url: "https://x.com/akakikaaa")
                AboutLink(title: "akakika", mark: .symbol("globe"), url: "https://akakika.com")
                AboutLink(title: "GitHub", mark: .asset("brand-github"), url: "https://github.com/aka-kika")
            }
            .padding(.top, 6)
            .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AboutLink: View {
    enum Mark { case symbol(String), asset(String) }
    let title: String?
    let mark: Mark
    let url: String
    @State private var hovering = false

    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 6) {
                markView
                if let title { Text(title).font(.system(size: 12, weight: .medium)) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(hovering ? 0.12 : 0.07)))
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var markView: some View {
        switch mark {
        case .symbol(let name):
            Image(systemName: name).font(.system(size: 12, weight: .medium))
        case .asset(let name):
            Image(name).renderingMode(.template).resizable().interpolation(.high)
                .frame(width: 12, height: 12)
        }
    }
}
