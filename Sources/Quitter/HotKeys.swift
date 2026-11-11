import Carbon
import SwiftUI

/// Global shortcuts via Carbon's RegisterEventHotKey (no Accessibility permission needed).
final class HotKeys {
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var current: [UInt32: Shortcut] = [:]
    private var handlers: [UInt32: () -> Void] = [:]

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, ctx in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            guard let ctx else { return noErr }
            let me = Unmanaged<HotKeys>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { me.handlers[hk.id]?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    func set(_ id: UInt32, _ shortcut: Shortcut?, _ handler: @escaping () -> Void) {
        handlers[id] = handler
        guard current[id] != shortcut else { return }
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        current[id] = shortcut
        guard let shortcut else { return }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers,
                                         EventHotKeyID(signature: OSType(0x5154_4C52), id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { refs[id] = ref } else { NSLog("Quitter: shortcut %@ unavailable (%d)", shortcut.display, status) }
    }
}

struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Button(monitor != nil ? "Type shortcut… (Esc cancels)" : (shortcut?.display ?? "Record Shortcut")) {
                monitor == nil ? start() : stop()
            }
            if shortcut != nil {
                Button { shortcut = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).accessibilityLabel("Clear shortcut")
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == UInt16(kVK_Escape) { stop(); return nil }
            let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !mods.isEmpty else { NSSound.beep(); return nil }
            // shortcut: F-keys/arrows show as raw glyphs, add a keyCode name table if that bothers.
            let key = e.charactersIgnoringModifiers?.uppercased() ?? "?"
            shortcut = Shortcut(keyCode: e.keyCode, modifiers: mods.rawValue, display: Shortcut.symbols(mods) + key)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
