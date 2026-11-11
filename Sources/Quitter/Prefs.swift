import AppKit
import Carbon
import QuitterCore

enum K {
    static let playSounds = "playSounds"
    static let showBackground = "showBackgroundApps"
    static let groupBackground = "groupBackgroundApps"
    static let includeFinder = "includeFinderInList"
    static let includeTrash = "includeTrashInList"
    static let skipMusic = "skipAutoclosingMusicApps"
    static let deselect = "deselectApps"
    static let autoQuit = "quitInactiveApps"
    static let autoQuitAmount = "quitInactiveAmount"
    static let autoQuitUnit = "quitInactiveUnit"
    static let disableTips = "disableTips"
    static let forceDefault = "forceQuitByDefault"
    static let sort = "menuAppsSort"
    static let welcomed = "welcomeWasPresented"
    static let bgWarned = "backgroundWarningShown"
    static let toggled = "toggledApps"
    static let policies = "policyApps"
    static let shortcutActivate = "shortcutActivate"
    static let shortcutQuit = "shortcutQuit"
    static let shortcutForceQuit = "shortcutForceQuit"
}

func registerDefaults() {
    UserDefaults.standard.register(defaults: [
        K.playSounds: true, K.skipMusic: true, K.autoQuitAmount: 30,
        K.autoQuitUnit: TimeUnit.minute.rawValue, K.sort: SortOrder.alphaASC.rawValue,
    ])
}

/// Stored as "keyCode|modifierFlags|display" so @AppStorage can hold it directly.
struct Shortcut: RawRepresentable, Equatable {
    let keyCode: UInt16
    let modifiers: UInt
    let display: String

    var rawValue: String { "\(keyCode)|\(modifiers)|\(display)" }

    var carbonModifiers: UInt32 {
        let f = NSEvent.ModifierFlags(rawValue: modifiers)
        return (f.contains(.command) ? UInt32(cmdKey) : 0) | (f.contains(.option) ? UInt32(optionKey) : 0)
            | (f.contains(.control) ? UInt32(controlKey) : 0) | (f.contains(.shift) ? UInt32(shiftKey) : 0)
    }

    static func symbols(_ f: NSEvent.ModifierFlags) -> String {
        (f.contains(.control) ? "⌃" : "") + (f.contains(.option) ? "⌥" : "")
            + (f.contains(.shift) ? "⇧" : "") + (f.contains(.command) ? "⌘" : "")
    }
}

// In an extension so the struct keeps its memberwise init.
extension Shortcut {
    init?(rawValue: String) {
        let p = rawValue.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard p.count == 3, let k = UInt16(p[0]), let m = UInt(p[1]) else { return nil }
        self.init(keyCode: k, modifiers: m, display: String(p[2]))
    }
}
