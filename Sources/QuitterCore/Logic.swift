import Foundation

public enum SortOrder: String, CaseIterable, Identifiable {
    case alphaASC, alphaDESC, cpuDESC, cpuASC, memoryDESC, memoryASC

    public var id: String { rawValue }
    public var showsMemory: Bool { self == .memoryASC || self == .memoryDESC }
    public var title: String {
        switch self {
        case .alphaASC: "A to Z"
        case .alphaDESC: "Z to A"
        case .cpuDESC: "High to Low CPU %"
        case .cpuASC: "Low to High CPU %"
        case .memoryDESC: "High to Low Memory"
        case .memoryASC: "Low to High Memory"
        }
    }
}

/// Per-app rule: `always` is always quit by Quit All, `never` is never quit (manually or automatically).
public enum Policy: String, CaseIterable, Identifiable {
    case standard, always, never

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .standard: "Standard"
        case .always: "Always quit"
        case .never: "Never quit"
        }
    }
}

public enum TimeUnit: String, CaseIterable, Identifiable {
    case minute, hour, day

    public var id: String { rawValue }
    public var seconds: TimeInterval {
        switch self {
        case .minute: 60
        case .hour: 3600
        case .day: 86400
        }
    }
}

public struct AppRow: Identifiable, Equatable {
    public let id: pid_t
    public let bundleID: String
    public let name: String
    public let isBackground: Bool
    public let cpu: Double
    public let memory: UInt64

    public init(id: pid_t, bundleID: String, name: String, isBackground: Bool, cpu: Double, memory: UInt64) {
        self.id = id
        self.bundleID = bundleID
        self.name = name
        self.isBackground = isBackground
        self.cpu = cpu
        self.memory = memory
    }
}

/// Apps skipped by Auto Quit when "Never quit music apps" is on (same list the original ships).
public let musicApps: Set<String> = ["com.apple.Music", "com.spotify.client"]

/// `toggled` holds the IDs whose checkbox differs from the default, so flipping the default flips everyone.
public func isSelected(_ bundleID: String, policy: Policy, toggled: Set<String>, deselectByDefault: Bool) -> Bool {
    switch policy {
    case .always: true
    case .never: false
    case .standard: toggled.contains(bundleID) == deselectByDefault
    }
}

public func toggledAfterSetting(_ ids: [String], selected: Bool, in toggled: Set<String>, deselectByDefault: Bool) -> Set<String> {
    selected == deselectByDefault ? toggled.union(ids) : toggled.subtracting(ids)
}

public func sortRows(_ rows: [AppRow], by order: SortOrder) -> [AppRow] {
    let byName: (AppRow, AppRow) -> Bool = { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    // Ties fall back to name so rows don't jump around between samples.
    func by<V: Comparable>(_ key: @escaping (AppRow) -> V, _ op: @escaping (V, V) -> Bool) -> (AppRow, AppRow) -> Bool {
        { a, b in key(a) == key(b) ? byName(a, b) : op(key(a), key(b)) }
    }
    switch order {
    case .alphaASC: return rows.sorted(by: byName)
    case .alphaDESC: return rows.sorted { byName($1, $0) }
    case .cpuDESC: return rows.sorted(by: by(\.cpu, >))
    case .cpuASC: return rows.sorted(by: by(\.cpu, <))
    case .memoryDESC: return rows.sorted(by: by(\.memory, >))
    case .memoryASC: return rows.sorted(by: by(\.memory, <))
    }
}

public func autoQuitCandidates(
    _ rows: [AppRow], frontmost: pid_t?, lastActive: [pid_t: Date], policies: [String: Policy],
    protected: Set<String>, threshold: TimeInterval, now: Date
) -> [AppRow] {
    guard threshold > 0 else { return [] }
    return rows.filter { row in
        !row.isBackground && row.id != frontmost && policies[row.bundleID] != .never
            && !protected.contains(row.bundleID)
            && now.timeIntervalSince(lastActive[row.id] ?? now) >= threshold
    }
}
