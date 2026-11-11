import QuitterCore
import ServiceManagement
import SwiftUI

struct PrefsView: View {
    @ObservedObject var m: AppsManager

    var body: some View {
        TabView {
            GeneralPrefs(m: m).tabItem { Label("General", systemImage: "gearshape") }
            ShortcutPrefs().tabItem { Label("Shortcuts", systemImage: "keyboard") }
            AboutPrefs().tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(20)
        .frame(width: 480, height: 620)
    }
}

struct GeneralPrefs: View {
    @ObservedObject var m: AppsManager
    @AppStorage(K.playSounds) private var playSounds = true
    @AppStorage(K.showBackground) private var showBG = false
    @AppStorage(K.groupBackground) private var groupBG = false
    @AppStorage(K.includeFinder) private var includeFinder = false
    @AppStorage(K.includeTrash) private var includeTrash = false
    @AppStorage(K.deselect) private var deselect = false
    @AppStorage(K.disableTips) private var disableTips = false
    @AppStorage(K.forceDefault) private var forceDefault = false
    @AppStorage(K.sort) private var sort = SortOrder.alphaASC
    @AppStorage(K.autoQuit) private var autoQuit = false
    @AppStorage(K.autoQuitAmount) private var amount = 30
    @AppStorage(K.autoQuitUnit) private var unit = TimeUnit.minute
    @AppStorage(K.skipMusic) private var skipMusic = true
    @AppStorage(K.bgWarned) private var bgWarned = false
    private static var loginEnabled: Bool { SMAppService.mainApp.status == .enabled }
    @State private var openAtLogin = Self.loginEnabled
    @State private var loginError: String?
    @State private var showBGWarning = false
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                Toggle("Open Quitter at login", isOn: $openAtLogin).onChange(of: openAtLogin) { _, on in setLogin(on) }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                Toggle("Play sounds when quitting", isOn: $playSounds)
                Toggle("Disable quit tips", isOn: $disableTips)
            }
            Section("List") {
                Toggle("View background apps", isOn: $showBG).onChange(of: showBG) { _, on in
                    if on && !bgWarned { bgWarned = true; showBGWarning = true }
                    m.refresh()
                }
                Toggle("Group background apps", isOn: $groupBG).disabled(!showBG)
                Toggle("Include Finder windows in list", isOn: $includeFinder)
                Toggle("Include Empty Trash in list", isOn: $includeTrash)
                Toggle("Deselect apps by default", isOn: $deselect)
                Picker("Sort apps", selection: $sort) { ForEach(SortOrder.allCases) { Text($0.title).tag($0) } }
                Picker("Default action", selection: $forceDefault) {
                    Text("Normal quit").tag(false)
                    Text("Force quit").tag(true)
                }
            }
            Section("Auto Quit") {
                Toggle("Quit inactive apps", isOn: $autoQuit)
                HStack {
                    Stepper("After \(amount)", value: $amount, in: 1...999)
                    Picker("Unit", selection: $unit) { ForEach(TimeUnit.allCases) { Text("\($0.rawValue)s").tag($0) } }
                        .labelsHidden().fixedSize()
                }
                .disabled(!autoQuit)
                Toggle("Never quit music apps", isOn: $skipMusic).disabled(!autoQuit)
            }
            Button("Reset all settings…") { confirmReset = true }
        }
        .formStyle(.grouped)
        .alert("Heads up", isPresented: $showBGWarning) { Button("OK") {} } message: {
            Text("Some background apps relaunch themselves right after being quit. That's up to them, not Quitter.")
        }
        .confirmationDialog("Reset all settings?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { m.reset() }
        }
    }

    private func setLogin(_ on: Bool) {
        guard on != Self.loginEnabled else { return }
        do {
            try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            loginError = nil
        } catch {
            loginError = "Couldn't change the login item: \(error.localizedDescription)"
            openAtLogin = Self.loginEnabled
        }
    }
}

struct ShortcutPrefs: View {
    @AppStorage(K.shortcutActivate) private var activate: Shortcut?
    @AppStorage(K.shortcutQuit) private var quit: Shortcut?
    @AppStorage(K.shortcutForceQuit) private var force: Shortcut?

    var body: some View {
        Form {
            LabeledContent("Open menu") { ShortcutRecorder(shortcut: $activate) }
            LabeledContent("Quit all") { ShortcutRecorder(shortcut: $quit) }
            LabeledContent("Force quit all") { ShortcutRecorder(shortcut: $force) }
            Text("Hold ⌥ Option while the menu is open to toggle between Quit and Force Quit.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

struct AboutPrefs: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: quitterLogo(size: 64)).renderingMode(.template).foregroundStyle(.tint)
            Text("Quitter").font(.title2.bold())
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                .foregroundStyle(.secondary)
            Text("A local, from-scratch take on the QuitAll feature set.").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
    }
}
