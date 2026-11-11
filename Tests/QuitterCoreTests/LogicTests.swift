import Foundation
import Testing
@testable import QuitterCore

private func row(_ id: pid_t, _ name: String, cpu: Double = 0, bg: Bool = false, bundle: String? = nil) -> AppRow {
    AppRow(id: id, bundleID: bundle ?? "b.\(name)", name: name, isBackground: bg, cpu: cpu, memory: 0)
}

@Test("Sorting by name and CPU, ties fall back to name")
func sorting() {
    let rows = [row(1, "beta", cpu: 5), row(2, "Alpha", cpu: 5), row(3, "gamma", cpu: 9)]
    #expect(sortRows(rows, by: .alphaASC).map(\.name) == ["Alpha", "beta", "gamma"])
    #expect(sortRows(rows, by: .alphaDESC).map(\.name) == ["gamma", "beta", "Alpha"])
    #expect(sortRows(rows, by: .cpuDESC).map(\.name) == ["gamma", "Alpha", "beta"])
    #expect(sortRows(rows, by: .cpuASC).map(\.name) == ["Alpha", "beta", "gamma"])
}

@Test("Policies override the checkbox")
func policies() {
    #expect(isSelected("a", policy: .always, toggled: ["a"], deselectByDefault: false))
    #expect(!isSelected("a", policy: .never, toggled: [], deselectByDefault: false))
    #expect(isSelected("a", policy: .standard, toggled: [], deselectByDefault: false))
    #expect(!isSelected("a", policy: .standard, toggled: [], deselectByDefault: true))
}

@Test("Setting selection round-trips under either default", arguments: [false, true], [false, true])
func selectionRoundTrip(deselectByDefault: Bool, want: Bool) {
    let t = toggledAfterSetting(["a"], selected: want, in: [], deselectByDefault: deselectByDefault)
    #expect(isSelected("a", policy: .standard, toggled: t, deselectByDefault: deselectByDefault) == want)
}

@Test("Auto Quit only picks stale, unprotected, foreground-type apps")
func autoQuit() {
    let now = Date()
    let old = now.addingTimeInterval(-3600)
    let rows = [
        row(1, "Old"), row(2, "Front"), row(3, "Fresh"), row(4, "Never"),
        row(5, "Music", bundle: "com.apple.Music"), row(6, "BG", bg: true), row(7, "Unseen"),
    ]
    let last: [pid_t: Date] = [1: old, 2: old, 3: now, 4: old, 5: old, 6: old]
    let got = autoQuitCandidates(rows, frontmost: 2, lastActive: last, policies: ["b.Never": .never],
                                 protected: musicApps, threshold: 600, now: now)
    #expect(got.map(\.name) == ["Old"])
    #expect(autoQuitCandidates(rows, frontmost: nil, lastActive: last, policies: [:],
                               protected: [], threshold: 0, now: now).isEmpty)
}

@Test("Memory sorting, units and display titles")
func memoryUnitsAndTitles() {
    let rows = [AppRow(id: 1, bundleID: "a", name: "A", isBackground: false, cpu: 0, memory: 10),
                AppRow(id: 2, bundleID: "b", name: "B", isBackground: false, cpu: 0, memory: 20)]
    #expect(sortRows(rows, by: .memoryDESC).map(\.name) == ["B", "A"])
    #expect(sortRows(rows, by: .memoryASC).map(\.name) == ["A", "B"])
    #expect(SortOrder.allCases.filter(\.showsMemory) == [.memoryDESC, .memoryASC])
    #expect(Set(SortOrder.allCases.map(\.title)).count == SortOrder.allCases.count)
    #expect(Policy.allCases.map(\.title) == ["Standard", "Always quit", "Never quit"])
    #expect(TimeUnit.allCases.map(\.seconds) == [60, 3600, 86400])
}
