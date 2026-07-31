import AppKit
import SwiftUI

@main
struct MIDImungerApp: App {
    @StateObject private var monitor = MIDIMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView(monitor: monitor)
                .frame(minWidth: 1240, minHeight: 760)
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
