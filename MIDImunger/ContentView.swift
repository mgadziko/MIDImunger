import CoreMIDI
import SwiftUI

struct ContentView: View {
    @ObservedObject var monitor: MIDIMonitor
    @AppStorage("showInputLog") private var showInputLog = true
    @AppStorage("showOutputLog") private var showOutputLog = true
    @AppStorage("showRouteInspector") private var showRouteInspector = true

    private let sectionSpacing: CGFloat = 16
    private let outerWindowGutter: CGFloat = 24

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header

                Divider()

                ScrollView {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(spacing: sectionSpacing) {
                            performanceInspectorSection
                            controlChangeSection
                            channelInspectorSection

                            if showRouteInspector {
                                diagnosticSection
                            }

                            if showInputLog {
                                inputLogPanel
                            }

                            if showOutputLog {
                                outputLogPanel
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background(Color(nsColor: .windowBackgroundColor))

                Divider()

                footer
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, outerWindowGutter)
            .padding(.trailing, outerWindowGutter)
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
        .onAppear {
            monitor.updateLogVisibility(inputVisible: showInputLog, outputVisible: showOutputLog)
        }
        .onChange(of: showInputLog) { _, newValue in
            monitor.updateLogVisibility(inputVisible: newValue, outputVisible: showOutputLog)
        }
        .onChange(of: showOutputLog) { _, newValue in
            monitor.updateLogVisibility(inputVisible: showInputLog, outputVisible: newValue)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                TitledSection(title: "Routing") {
                    RoutingPanel(monitor: monitor)
                }

                TitledSection(title: "Activity Scope") {
                    HeaderPanel(
                        bodyText: "The LED strip below shows the latest value received on any MIDI channel."
                    )
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var performanceInspectorSection: some View {
        TitledSection(title: "Performance Inspector") {
            signalToolbar
        }
    }

    private var controlChangeSection: some View {
        TitledSection(title: "Control Change Inspector") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(monitor.visibleControlChangeRowStarts, id: \.self) { rowStart in
                    controlChangeRow(controllers: Array(rowStart...(rowStart + 7)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(sectionPanelBackground)
        }
    }

    private func controlChangeRow(controllers: [Int]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(controllers, id: \.self) { controller in
                HStack(alignment: .top, spacing: 4) {
                    ReadOnlyLEDValue(
                        label: "CC\(controller)",
                        value: monitor.controlChangeText(for: controller),
                        width: 78
                    )
                    ReadOnlyLEDValue(
                        label: "Ch",
                        value: monitor.controlChangeChannelText(for: controller),
                        width: 52
                    )
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .background(controlChangePairBackground)
            }
        }
    }

    private var channelInspectorSection: some View {
        TitledSection(title: "Channel Inspector") {
            channelGrid
        }
    }

    private var channelGrid: some View {
        HStack(alignment: .top, spacing: 12) {
            channelColumn(states: Array(monitor.channelStates.prefix(8)))
            channelColumn(states: Array(monitor.channelStates.suffix(8)))
        }
    }

    private func channelColumn(states: [ChannelState]) -> some View {
        VStack(spacing: 10) {
            ForEach(states) { channelState in
                ChannelRowView(channelState: channelState)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
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

            VStack(spacing: 8) {
                Button("All Notes Off") {
                    monitor.sendAllNotesOff()
                }
                .controlSize(.large)
                .frame(width: 168)

                Button("DX Play") {
                    monitor.sendDXPlay()
                }
                .controlSize(.large)
                .frame(width: 168)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(sectionPanelBackground)
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

    private var inputLogPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Input Log")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Newest events at the bottom. Text can be selected and copied.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(monitor.inputLogText)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(12)
                        .id("input-log-bottom")
                }
                .frame(minHeight: 180, maxHeight: 180)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.28))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
                .onAppear {
                    proxy.scrollTo("input-log-bottom", anchor: .bottom)
                }
                .onChange(of: monitor.inputLogEntries.count) { _, _ in
                    proxy.scrollTo("input-log-bottom", anchor: .bottom)
                }
            }
        }
        .background(Color.black.opacity(0.10))
    }

    private var outputLogPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Output Log")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Shows MIDI bytes actually sent by MIDImunger.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(monitor.outputLogText)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(12)
                        .id("output-log-bottom")
                }
                .frame(minHeight: 180, maxHeight: 180)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.28))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
                .onAppear {
                    proxy.scrollTo("output-log-bottom", anchor: .bottom)
                }
                .onChange(of: monitor.outputLogEntries.count) { _, _ in
                    proxy.scrollTo("output-log-bottom", anchor: .bottom)
                }
            }
        }
        .background(Color.black.opacity(0.10))
    }

    private var diagnosticSection: some View {
        TitledSection(title: "MIDI Route Inspector") {
            diagnosticPanel
        }
    }

    private var diagnosticPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Selected Thru: \(monitor.selectedDestinationDiagnosticText)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .textSelection(.enabled)

            HStack(alignment: .top, spacing: 12) {
                diagnosticColumn(title: "Input Sources", endpoints: monitor.sourceDiagnostics)
                diagnosticColumn(title: "Output Destinations", endpoints: monitor.destinationDiagnostics)
            }
        }
        .padding(12)
        .background(sectionCardBackground)
    }

    private func diagnosticColumn(title: String, endpoints: [MIDIRouteDiagnostic]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            BlueSectionTitle(title)

            if endpoints.isEmpty {
                Text("None detected.")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(endpoints) { endpoint in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(endpoint.name)
                                .font(.system(size: 12, weight: endpoint.isSelected ? .semibold : .regular, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            if endpoint.isSelected {
                                Text("Selected")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.green)
                            }

                            if endpoint.activity?.isPerformanceRecentlyActive == true {
                                Text("Playing")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.green)
                            } else if endpoint.activity?.isRecentlyActive == true {
                                Text("Background")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.yellow)
                            }
                        }

                        Text("endpoint \(endpoint.endpointUniqueID)  entity \(diagnosticValue(endpoint.entityUniqueID))  device \(diagnosticValue(endpoint.deviceUniqueID))")
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)

                        if let activity = endpoint.activity {
                            Text("events \(activity.totalEventCount)  musical \(activity.performanceEventCount)  active-sense \(activity.activeSensingCount)  repeats \(activity.repeatWarningCount)")
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)

                            if let lastPerformanceTimestamp = activity.lastPerformanceTimestamp,
                               let lastPerformanceMessage = activity.lastPerformanceMessage {
                                Text("last musical \(lastPerformanceTimestamp)")
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)

                                Text(lastPerformanceMessage)
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.88))
                                    .lineLimit(2)
                                    .truncationMode(.tail)
                                    .textSelection(.enabled)
                            } else {
                                Text("No musical/controller activity this session.")
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }

                            if let lastRepeatWarningTimestamp = activity.lastRepeatWarningTimestamp,
                               let lastRepeatWarningMessage = activity.lastRepeatWarningMessage {
                                Text("last repeat \(lastRepeatWarningTimestamp)")
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .foregroundStyle(.orange)
                                    .textSelection(.enabled)

                                Text(lastRepeatWarningMessage)
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .foregroundStyle(.orange)
                                    .lineLimit(2)
                                    .truncationMode(.tail)
                                    .textSelection(.enabled)
                            }

                            Text("last any \(activity.lastAnyTimestamp)")
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)

                            Text(activity.lastAnyMessage)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .truncationMode(.tail)
                                .textSelection(.enabled)

                            if !activity.recentMessages.isEmpty {
                                Text("recent history")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.secondary)

                                ForEach(activity.recentMessages) { message in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(message.isPerformance ? "M" : "B")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundStyle(message.isRepeatWarning ? .orange : (message.isPerformance ? .green : .yellow))
                                            .frame(width: 10, alignment: .leading)

                                        Text("\(message.timestamp)  \(message.text)")
                                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                                            .foregroundStyle(message.isRepeatWarning ? .orange : .secondary)
                                            .lineLimit(2)
                                            .truncationMode(.tail)
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                        } else {
                            Text("No MIDI activity this session.")
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.20))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private func diagnosticValue(_ value: MIDIUniqueID?) -> String {
        value.map(String.init) ?? "-"
    }

    private var sectionPanelBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    private var sectionCardBackground: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.white.opacity(0.07))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    private var controlChangePairBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.black.opacity(0.20))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}

private struct TitledSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BlueSectionTitle(title)
            content
                .padding(.leading, 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BlueSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.blue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 24)
    }
}

private struct RoutingPanel: View {
    @ObservedObject var monitor: MIDIMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer()

                Button {
                    monitor.refreshEndpoints()
                } label: {
                    Label("Refresh MIDI", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
            }

            HStack(alignment: .top, spacing: 14) {
                InputsPanel(rows: alignedRows, monitor: monitor)
                OutputsPanel(rows: alignedRows, monitor: monitor)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var alignedRows: [RoutingAlignmentRow] {
        let groupedInputs = Dictionary(grouping: monitor.inputSources, by: \.name)
        let groupedOutputs = Dictionary(grouping: monitor.destinations, by: \.name)
        let sortedNames = Set(groupedInputs.keys)
            .union(groupedOutputs.keys)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        return sortedNames.flatMap { name in
            let inputs = groupedInputs[name, default: []]
            let outputs = groupedOutputs[name, default: []]
            let rowCount = max(inputs.count, outputs.count)

            return (0..<rowCount).map { index in
                RoutingAlignmentRow(
                    id: "\(name)-\(index)",
                    input: inputs.indices.contains(index) ? inputs[index] : nil,
                    output: outputs.indices.contains(index) ? outputs[index] : nil
                )
            }
        }
    }
}

private struct InputsPanel: View {
    let rows: [RoutingAlignmentRow]
    @ObservedObject var monitor: MIDIMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Inputs")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if rows.isEmpty {
                Text("No CoreMIDI sources found.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            } else {
                ForEach(rows) { row in
                    if let source = row.input {
                        Toggle(
                            source.name,
                            isOn: Binding(
                                get: { source.isEnabled },
                                set: { monitor.setInputSourceEnabled(source.uniqueID, isEnabled: $0) }
                            )
                        )
                        .toggleStyle(.checkbox)
                        .font(.subheadline.weight(.medium))
                    } else {
                        Color.clear
                            .frame(height: 22)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .frame(maxWidth: 320, alignment: .leading)
    }
}

private struct HeaderPanel: View {
    var bodyText: String

    var body: some View {
        Text(bodyText)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .lineLimit(2)
            .truncationMode(.middle)
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

private struct OutputsPanel: View {
    let rows: [RoutingAlignmentRow]
    @ObservedObject var monitor: MIDIMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Outputs")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if rows.isEmpty {
                Text("No CoreMIDI destinations found.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            } else {
                ForEach(rows) { row in
                    if let destination = row.output {
                        Toggle(
                            destination.name,
                            isOn: Binding(
                                get: { monitor.selectedDestinationIDs.contains(destination.uniqueID) },
                                set: { monitor.setDestinationEnabled(destination.uniqueID, isEnabled: $0) }
                            )
                        )
                        .toggleStyle(.checkbox)
                        .font(.subheadline.weight(.medium))
                    } else {
                        Color.clear
                            .frame(height: 22)
                            .accessibilityHidden(true)
                    }
                }

                if monitor.selectedDestinationIDs.isEmpty {
                    Text("No MIDI Thru")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: 320, alignment: .leading)
    }
}

private struct RoutingAlignmentRow: Identifiable {
    let id: String
    let input: MIDIInputSourceOption?
    let output: MIDIEndpointOption?
}

private struct ChannelRowView: View {
    let channelState: ChannelState

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(String(format: "Ch %02d", channelState.channelNumber))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 58, alignment: .leading)

            ReadOnlyLEDValue(label: "Value", value: channelState.numericDisplay, width: 92)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
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
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
