import SwiftUI

struct ContentView: View {
    @ObservedObject var monitor: MIDIMonitor

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            signalToolbar

            Divider()

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(monitor.channelStates) { channelState in
                        ChannelRowView(channelState: channelState)
                    }
                }
                .padding(16)
            }
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            footer
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.11, green: 0.13, blue: 0.16),
                    Color(red: 0.08, green: 0.09, blue: 0.11),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            HeaderPanel(
                title: "Inputs",
                bodyText: monitor.sourceSummaryText
            )

            DestinationPanel(monitor: monitor)

            HeaderPanel(
                title: "Activity Scope",
                bodyText: "The LED strip below shows the latest value received on any MIDI channel."
            )

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var signalToolbar: some View {
        HStack(alignment: .center, spacing: 12) {
            ReadOnlyLEDValue(label: "Channel", value: monitor.latestChannelText, width: 78)
            ReadOnlyLEDValue(label: "Program", value: monitor.latestProgramText, width: 78)
            ReadOnlyLEDValue(label: "Last Note", value: monitor.latestNoteText, width: 78)
            ReadOnlyLEDValue(label: "Velocity", value: monitor.latestVelocityText, width: 78)
            ReadOnlyLEDValue(label: "Aftertouch", value: monitor.latestAftertouchText, width: 78)
            ReadOnlyLEDValue(label: "Pitch Bend", value: monitor.latestPitchBendText, width: 106)
            ReadOnlyLEDValue(label: "Modulation", value: monitor.latestModulationText, width: 78)
            ReadOnlyLEDValue(label: "Output Volume", value: monitor.latestOutputVolumeText, width: 88)

            Spacer(minLength: 8)

            Button("All Notes Off") {
                monitor.sendAllNotesOff()
            }
            .controlSize(.large)
            .frame(width: 168)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.12))
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(monitor.footerStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Text(monitor.lastSystemMessage)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.12))
    }
}

private struct HeaderPanel: View {
    var title: String
    var bodyText: String

    var bodyView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(bodyText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(12)
        .frame(maxWidth: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    var body: some View { bodyView }
}

private struct DestinationPanel: View {
    @ObservedObject var monitor: MIDIMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MIDI Thru Destination")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Menu {
                ForEach(monitor.destinations) { destination in
                    Button {
                        monitor.selectedDestinationID = destination.uniqueID
                    } label: {
                        Label(destination.name, systemImage: monitor.selectedDestinationID == destination.uniqueID ? "checkmark" : "circle")
                    }
                }
            } label: {
                Label(monitor.selectedDestinationName, systemImage: "arrow.triangle.branch")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                monitor.refreshEndpoints()
            } label: {
                Label("Refresh MIDI", systemImage: "arrow.clockwise")
            }
        }
        .padding(12)
        .frame(maxWidth: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

private struct ChannelRowView: View {
    let channelState: ChannelState

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(String(format: "%02d", channelState.channelNumber))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 48)

            ReadOnlyLEDValue(label: "Value", value: channelState.numericDisplay, width: 104)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Text(channelState.sourceName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if channelState.isActive {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                    }
                }

                Text(channelState.statusText)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}
