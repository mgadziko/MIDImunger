import AppKit
import SwiftUI

@main
struct MIDImungerApp: App {
    @StateObject private var monitor = MIDIMonitor()
    @NSApplicationDelegateAdaptor(MIDImungerAppDelegate.self) private var appDelegate
    private let minimumWindowSize = NSSize(width: 1560, height: 860)

    var body: some Scene {
        WindowGroup {
            ContentView(monitor: monitor)
                .frame(minWidth: minimumWindowSize.width, minHeight: minimumWindowSize.height)
                .onAppear {
                    appDelegate.monitor = monitor
                    appDelegate.minimumWindowSize = minimumWindowSize
                    appDelegate.enforceWindowSizing()
                }
        }
        .defaultSize(width: minimumWindowSize.width, height: minimumWindowSize.height)
        .windowResizability(.contentMinSize)

        Settings {
            PreferencesView()
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About MIDImunger") {
                    AboutBoxController.shared.show()
                }
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save Logs...") {
                    _ = monitor.saveLogsInteractively()
                }
            }

            CommandGroup(after: .appInfo) {
                Button("Refresh MIDI Endpoints") {
                    monitor.refreshEndpoints()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("All Notes Off") {
                    monitor.sendAllNotesOff()
                }
                .keyboardShortcut(".")
            }
        }
    }
}

@MainActor
final class MIDImungerAppDelegate: NSObject, NSApplicationDelegate {
    weak var monitor: MIDIMonitor?
    var minimumWindowSize = NSSize(width: 1560, height: 860)
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = NotificationCenter.default

        observers.append(
            center.addObserver(
                forName: NSWindow.didBecomeMainNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let window = notification.object as? NSWindow else { return }
                self?.enforceWindowSizing(for: window)
            }
        )

        observers.append(
            center.addObserver(
                forName: NSWindow.didEndLiveResizeNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let window = notification.object as? NSWindow else { return }
                self?.enforceWindowSizing(for: window)
            }
        )

        DispatchQueue.main.async { [weak self] in
            self?.enforceWindowSizing()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        observers.removeAll()
    }

    func enforceWindowSizing() {
        NSApp.windows.forEach(enforceWindowSizing(for:))
    }

    func enforceWindowSizing(for window: NSWindow) {
        guard window.title.localizedCaseInsensitiveContains("MIDImunger") || window.identifier?.rawValue.contains("MIDImunger") == true else {
            return
        }

        window.minSize = minimumWindowSize

        var frame = window.frame
        let widthChanged = frame.size.width < minimumWindowSize.width
        let heightChanged = frame.size.height < minimumWindowSize.height

        guard widthChanged || heightChanged else { return }

        frame.size.width = max(frame.size.width, minimumWindowSize.width)
        frame.size.height = max(frame.size.height, minimumWindowSize.height)
        window.setFrame(frame, display: true, animate: false)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let monitor, monitor.shouldPromptToSaveLogsOnQuit else {
            return .terminateNow
        }

        switch monitor.promptToSaveLogsBeforeQuit() {
        case .saveAndQuit:
            return .terminateNow
        case .quitWithoutSaving:
            return .terminateNow
        case .cancel:
            return .terminateCancel
        }
    }
}

private struct PreferencesView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var showInputLog = true
    @State private var showOutputLog = true
    @State private var showRouteInspector = true
    @State private var suppressRepeatedNoteOn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Form {
                Section("View") {
                    Toggle("Show MIDI Route Inspector", isOn: $showRouteInspector)
                }

                Section("Logging") {
                    Toggle("Show Input Log", isOn: $showInputLog)
                    Toggle("Show Output Log", isOn: $showOutputLog)
                    Text("MIDImunger keeps only the most recent 1000 lines in each log when they are not shown.")
                        .foregroundStyle(.secondary)
                }

                Section("Input Filtering") {
                    Toggle("Suppress repeated Note On within 300 ms", isOn: $suppressRepeatedNoteOn)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Close without Saving") {
                    loadPreferences()
                    dismiss()
                }

                Spacer()

                Button("Save Changes") {
                    savePreferences()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            loadPreferences()
        }
    }

    private func loadPreferences() {
        let defaults = UserDefaults.standard
        showInputLog = defaults.object(forKey: "showInputLog") as? Bool ?? true
        showOutputLog = defaults.object(forKey: "showOutputLog") as? Bool ?? true
        showRouteInspector = defaults.object(forKey: "showRouteInspector") as? Bool ?? true
        suppressRepeatedNoteOn = defaults.object(forKey: "suppressRepeatedNoteOn") as? Bool ?? false
    }

    private func savePreferences() {
        let defaults = UserDefaults.standard
        defaults.set(showInputLog, forKey: "showInputLog")
        defaults.set(showOutputLog, forKey: "showOutputLog")
        defaults.set(showRouteInspector, forKey: "showRouteInspector")
        defaults.set(suppressRepeatedNoteOn, forKey: "suppressRepeatedNoteOn")
    }
}
