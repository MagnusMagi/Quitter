import AppKit
import QuitterCore
import UserNotifications

private let timebase: (numer: UInt64, denom: UInt64) = {
    var t = mach_timebase_info_data_t()
    mach_timebase_info(&t)
    return (UInt64(t.numer), UInt64(t.denom))
}()

/// Running apps, their CPU/RAM, selection state, quitting and Auto Quit.
final class AppsManager: ObservableObject {
    static let finderID = "com.apple.finder"
    static let trashID = "com.apple.trash"

    @Published private(set) var apps: [AppRow] = []
    @Published var optionHeld = false
    @Published private(set) var toggled: Set<String> {
        didSet { defaults.set(Array(toggled), forKey: K.toggled) }
    }
    @Published private(set) var policies: [String: Policy] {
        didSet { defaults.set(policies.mapValues(\.rawValue), forKey: K.policies) }
    }

    private let defaults = UserDefaults.standard
    private var samples: [pid_t: (cpu: UInt64, wall: UInt64)] = [:]
    private var lastActive: [pid_t: Date] = [:]
    private var pendingAutoQuit: [pid_t: DispatchWorkItem] = [:]
    private var sampler: Timer?

    var forceMode: Bool { defaults.bool(forKey: K.forceDefault) != optionHeld }
    private var deselectByDefault: Bool { defaults.bool(forKey: K.deselect) }

    init() {
        toggled = Set(defaults.stringArray(forKey: K.toggled) ?? [])
        policies = (defaults.dictionary(forKey: K.policies) as? [String: String] ?? [:]).compactMapValues(Policy.init)

        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        }
        nc.addObserver(forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let pid = Self.pid(n) else { return }
            self?.lastActive[pid] = Date()
        }
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let pid = Self.pid(n) else { return }
            self?.pendingAutoQuit.removeValue(forKey: pid)?.cancel()
        }
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.checkInactive() }
        refresh()
    }

    private static func pid(_ n: Notification) -> pid_t? {
        (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
    }

    // MARK: Listing

    func refresh() {
        let showBG = defaults.bool(forKey: K.showBackground)
        let me = ProcessInfo.processInfo.processIdentifier
        let now = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
        let sampling = sampler != nil  // CPU/RAM only matter while the panel shows them
        let rows: [AppRow] = NSWorkspace.shared.runningApplications.compactMap { app in
            guard let id = app.bundleIdentifier, app.processIdentifier != me, id != Self.finderID, !app.isTerminated
            else { return nil }
            let background: Bool
            switch app.activationPolicy {
            case .regular: background = false
            case .accessory where showBG && !id.hasPrefix("com.apple."): background = true
            default: return nil
            }
            let s = sampling ? stats(app.processIdentifier, now: now) : (cpu: 0, memory: 0)
            return AppRow(id: app.processIdentifier, bundleID: id, name: app.localizedName ?? id,
                          isBackground: background, cpu: s.cpu, memory: s.memory)
        }
        let alive = Set(rows.map(\.id))
        samples = samples.filter { alive.contains($0.key) }
        lastActive = lastActive.filter { alive.contains($0.key) }
            .merging(rows.map { ($0.id, Date()) }) { old, _ in old }
        if rows != apps { apps = rows }
    }

    private func stats(_ pid: pid_t, now: UInt64) -> (cpu: Double, memory: UInt64) {
        var info = rusage_info_v2()
        let rc = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
        }
        guard rc == 0 else { return (0, 0) }
        let cpuNs = (info.ri_user_time + info.ri_system_time) * timebase.numer / timebase.denom
        let prev = samples[pid]
        samples[pid] = (cpuNs, now)
        guard let prev, now > prev.wall, cpuNs >= prev.cpu else { return (0, info.ri_phys_footprint) }
        return (Double(cpuNs - prev.cpu) / Double(now - prev.wall) * 100, info.ri_phys_footprint)
    }

    func startSampling() {
        sampler = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }

    func stopSampling() {
        sampler?.invalidate()
        sampler = nil
    }

    // MARK: Selection & policy

    func selected(_ id: String) -> Bool {
        isSelected(id, policy: policies[id] ?? .standard, toggled: toggled,
                   deselectByDefault: deselectByDefault)
    }

    func setSelected(_ ids: [String], _ on: Bool) {
        toggled = toggledAfterSetting(ids, selected: on, in: toggled, deselectByDefault: deselectByDefault)
    }

    func setPolicy(_ policy: Policy, for id: String) {
        policies[id] = policy
    }

    func reset() {
        Bundle.main.bundleIdentifier.map(defaults.removePersistentDomain(forName:))
        toggled = []
        policies = [:]
        refresh()
    }

    // MARK: Actions

    func activate(_ row: AppRow) {
        // Re-opening a running app sends the Dock-style reopen event, which un-minimizes its windows.
        guard let url = NSRunningApplication(processIdentifier: row.id)?.bundleURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            if let error { NSLog("Quitter: couldn't activate %@: %@", row.name, error.localizedDescription) }
        }
    }

    /// Returns false when the app is protected by the Never policy or already gone.
    @discardableResult
    func quit(_ row: AppRow, force: Bool) -> Bool {
        guard terminate(row, force: force) else { return false }
        play("Pop")
        return true
    }

    private func terminate(_ row: AppRow, force: Bool) -> Bool {
        guard policies[row.bundleID] != .never, let app = NSRunningApplication(processIdentifier: row.id) else { return false }
        return force ? app.forceTerminate() : app.terminate()
    }

    func quitSelected(force: Bool) {
        for row in apps where selected(row.bundleID) { _ = terminate(row, force: force) }
        if defaults.bool(forKey: K.includeFinder), selected(Self.finderID) {
            runFinder("tell application \"Finder\" to close every window")
        }
        if defaults.bool(forKey: K.includeTrash), selected(Self.trashID) {
            runFinder("tell application \"Finder\"\nignoring application responses\nempty the trash\nend ignoring\nend tell")
        }
        play("Submarine")
        notify(force ? "All selected apps were force quit." : "All selected apps were quit.")
    }

    private func checkInactive() {
        guard defaults.bool(forKey: K.autoQuit) else { return }
        refresh()
        let amount = defaults.integer(forKey: K.autoQuitAmount)
        let unit = TimeUnit(rawValue: defaults.string(forKey: K.autoQuitUnit) ?? "") ?? .minute
        let candidates = autoQuitCandidates(
            apps, frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier, lastActive: lastActive,
            policies: policies, protected: defaults.bool(forKey: K.skipMusic) ? musicApps : [],
            threshold: Double(amount) * unit.seconds, now: Date())
        for row in candidates where pendingAutoQuit[row.id] == nil {
            notify("\(row.name) has been inactive for \(amount) \(unit.rawValue)(s). Auto-quitting in 30 seconds.")
            let work = DispatchWorkItem { [weak self] in
                self?.pendingAutoQuit[row.id] = nil
                // Normal quit, so apps can still ask to save.
                if self?.quit(row, force: false) == true { self?.notify("\(row.name) was quit.") }
            }
            pendingAutoQuit[row.id] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: work)
        }
    }

    // MARK: Helpers

    private func runFinder(_ source: String) {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard let error else { return }
        NSLog("Quitter: Finder script failed: %@", error)
        notify("Finder action failed: \(error[NSAppleScript.errorMessage] as? String ?? "unknown error")")
    }

    private func play(_ sound: String) {
        guard defaults.bool(forKey: K.playSounds) else { return }
        NSSound(named: sound)?.play()
    }

    private func notify(_ body: String) {
        let content = UNMutableNotificationContent()
        content.title = "Quitter"
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
