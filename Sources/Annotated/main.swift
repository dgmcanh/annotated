import AppKit
import Carbon.HIToolbox
import ServiceManagement

if CommandLine.arguments.contains("--self-check") {
    selfCheck()
    print("self-check ok")
    exit(0)
}

private func loginItemStatus() -> String {
    switch SMAppService.mainApp.status {
    case .notRegistered: return "not registered"
    case .enabled: return "enabled"
    case .requiresApproval: return "needs approval in System Settings"
    case .notFound: return "not found"
    @unknown default: return "unknown"
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlay = OverlayController()
    private var registered = false
    private var doubleCommand: DoubleModifierTap?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only an installed copy registers itself; dev builds would otherwise
        // pile up stale entries in Login Items pointing at a build folder.
        if Bundle.main.bundlePath.hasPrefix("/Applications/") {
            do {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
                NSLog("annotated: login item %@", loginItemStatus())
            } catch {
                NSLog("annotated: login item registration failed: %@", String(describing: error))
            }
        } else {
            NSLog("annotated: not in /Applications (%@), so no login item", Bundle.main.bundlePath)
        }

        registered = HotkeyCenter.shared.register(keyCode: UInt32(kVK_ANSI_A),
                                                  modifiers: UInt32(optionKey | cmdKey)) { [overlay] in
            overlay.summonOrClear()
        } != nil

        // No UI means no other way to trigger the overlay for a test or when
        // the shortcut is taken: `Annotated.app/Contents/MacOS/Annotated --show`.
        if CommandLine.arguments.contains("--show") { overlay.show() }

        // Double-tap ⌘ is the main way in. ⌥⌘A stays as a Carbon hot key so
        // the app is still usable when Accessibility permission is refused.
        doubleCommand = DoubleModifierTap { [overlay] in overlay.summonOrClear() }
        let trusted = DoubleModifierTap.hasAccessibility(prompt: true)
        NSLog("annotated: double-command %@", trusted ? "armed" : "needs Accessibility permission")
        NSLog("annotated: hotkey %@", registered ? "registered" : "registration FAILED")

        if !registered {
            let alert = NSAlert()
            alert.messageText = "Annotated could not register ⌥⌘A"
            alert.informativeText = "Another app already owns that shortcut. Annotated will not respond until it is free."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}

// Top-level code is not main-actor isolated here, but it does run on the main
// thread, which is what AppKit actually requires.
nonisolated(unsafe) var appDelegate: AppDelegate?

MainActor.assumeIsolated {
    let delegate = AppDelegate()
    appDelegate = delegate
    NSApplication.shared.delegate = delegate
    NSApplication.shared.setActivationPolicy(.accessory)
    NSApplication.shared.run()
}
