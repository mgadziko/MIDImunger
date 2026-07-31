import AppKit
import SwiftUI

@main
struct MIDImungerApp: App {
    @StateObject private var monitor = MIDIMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView(monitor: monitor)
                .frame(minWidth: 1240, minHeight: 860)
        }

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
                }

                Section("Input Filtering") {
                    Toggle("Suppress repeated Note On within 300 ms", isOn: $suppressRepeatedNoteOn)
                }

                Section("Notes") {
                    Text("MIDImunger keeps only the most recent 1000 lines in each log.")
                        .foregroundStyle(.secondary)
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
