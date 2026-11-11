import QuitterCore
import SwiftUI

struct MenuView: View {
    @ObservedObject var m: AppsManager
    let openPrefs: () -> Void
    let close: () -> Void
    @AppStorage(K.sort) private var sort = SortOrder.alphaASC
    @AppStorage(K.groupBackground) private var groupBG = false
    @AppStorage(K.includeFinder) private var includeFinder = false
    @AppStorage(K.includeTrash) private var includeTrash = false
    @AppStorage(K.disableTips) private var disableTips = false
    @State private var search = ""

    private var visible: [AppRow] {
        let rows = sortRows(m.apps, by: sort)
        return search.isEmpty ? rows : rows.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var allIDs: [String] {
        m.apps.map(\.bundleID) + (includeFinder ? [AppsManager.finderID] : []) + (includeTrash ? [AppsManager.trashID] : [])
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            ScrollView { LazyVStack(spacing: 2) { list } }
            Button { m.quitSelected(force: m.forceMode) } label: {
                Text(m.forceMode ? "Force Quit All" : "Quit All").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .tint(m.forceMode ? .red : .accentColor)
            .keyboardShortcut(.defaultAction)
            if !disableTips { TipsView() }
        }
        .padding(12)
        .frame(width: 340, height: 480)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onExitCommand(perform: close)
    }

    private var header: some View {
        HStack {
            Toggle("", isOn: m.selection(allIDs))
                .labelsHidden().help("Select all").accessibilityLabel("Select all")
            TextField("Search", text: $search).textFieldStyle(.roundedBorder)
            Menu {
                Picker("Sort", selection: $sort) { ForEach(SortOrder.allCases) { Text($0.title).tag($0) } }
                    .pickerStyle(.inline)
                Divider()
                Button("Settings…", action: openPrefs)
                Button("Quit Quitter") { NSApp.terminate(nil) }
            } label: { Image(systemName: "gearshape") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Options")
        }
    }

    @ViewBuilder private var list: some View {
        let rows = visible
        ForEach(rows.filter { !$0.isBackground }, content: rowView)
        if includeFinder { SpecialRow(m: m, id: AppsManager.finderID, title: "Finder Windows", symbol: "macwindow.on.rectangle") }
        if includeTrash { SpecialRow(m: m, id: AppsManager.trashID, title: "Empty Trash", symbol: "trash") }
        let background = rows.filter(\.isBackground)
        if !background.isEmpty {
            if groupBG {
                DisclosureGroup("Background apps (\(background.count))") {
                    ForEach(background, content: rowView)
                }
                .padding(.horizontal, 6)
            } else {
                ForEach(background, content: rowView)
            }
        }
    }

    private func rowView(_ row: AppRow) -> AppRowView { AppRowView(m: m, row: row, showMemory: sort.showsMemory) }
}

extension AppsManager {
    func selection(_ ids: [String]) -> Binding<Bool> {
        Binding(get: { ids.allSatisfy(self.selected) }, set: { self.setSelected(ids, $0) })
    }
}

struct AppRowView: View {
    @ObservedObject var m: AppsManager
    let row: AppRow
    let showMemory: Bool
    @State private var hovered = false

    var body: some View {
        let policy = m.policies[row.bundleID] ?? .standard
        HStack(spacing: 8) {
            Toggle("", isOn: m.selection([row.bundleID]))
                .labelsHidden().disabled(policy != .standard).accessibilityLabel("Include \(row.name)")
            Button { m.activate(row) } label: {
                HStack(spacing: 6) {
                    Image(nsImage: NSRunningApplication(processIdentifier: row.id)?.icon ?? NSImage())
                        .resizable().frame(width: 20, height: 20)
                    Text(row.name).lineLimit(1)
                    if policy != .standard {
                        Image(systemName: policy == .always ? "bolt.fill" : "lock.fill")
                            .font(.caption).foregroundStyle(.secondary).help(policy.title)
                    }
                }
            }
            .buttonStyle(.plain).help("Bring \(row.name) to front")
            Spacer()
            Text(showMemory ? ByteCountFormatter.string(fromByteCount: Int64(row.memory), countStyle: .memory)
                : String(format: "%.1f%%", row.cpu))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Menu {
                Button("Quit") { m.quit(row, force: false) }
                Button("Force Quit") { m.quit(row, force: true) }
                Divider()
                Picker("Policy", selection: Binding(get: { policy }, set: { m.setPolicy($0, for: row.bundleID) })) {
                    ForEach(Policy.allCases) { Text($0.title).tag($0) }
                }
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("More options for \(row.name)")
            Button { m.quit(row, force: m.forceMode) } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).opacity(hovered ? 1 : 0).allowsHitTesting(hovered)
                .disabled(policy == .never).accessibilityLabel("Quit \(row.name)")
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(hovered ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovered = $0 }
    }
}

struct SpecialRow: View {
    @ObservedObject var m: AppsManager
    let id: String
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: m.selection([id]))
                .labelsHidden().accessibilityLabel("Include \(title)")
            Image(systemName: symbol).frame(width: 20, height: 20)
            Text(title)
            Spacer()
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
    }
}

struct TipsView: View {
    private static let tips = [
        "Hold ⌥ Option to switch between Quit and Force Quit.",
        "Set an app to “Never quit” from its ••• menu to protect it.",
        "Click an app's name to bring it to the front.",
        "Auto Quit can close apps you haven't touched in a while.",
        "Set global shortcuts in Settings → Shortcuts.",
    ]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 8)) { ctx in
            Text(Self.tips[Int(ctx.date.timeIntervalSinceReferenceDate / 8) % Self.tips.count])
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
        }
    }
}
