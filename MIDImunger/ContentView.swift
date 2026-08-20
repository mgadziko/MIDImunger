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
        HStack(alignment: .top, spacing: 18) {
            TitledSection(title: "Routing") {
                RoutingPanel(monitor: monitor)
            }
            .frame(maxWidth: 380, alignment: .topLeading)

            VStack(alignment: .leading, spacing: sectionSpacing) {
                TitledSection(title: "Reset") {
                    resetPanel
                }
                .frame(width: 192, alignment: .topLeading)

                performanceInspectorSection
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var performanceInspectorSection: some View {
        TitledSection(title: "Performance Inspector") {
            performanceInspectorPanel
        }
    }

    private var controlChangeSection: some View {
        TitledSection(
            title: "Control Change Inspector",
            trailing: {
                Button("Clear Control Change Inspector") {
                    monitor.clearControlChangeInspector()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        ) {
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
                        label: controlChangeLabel(for: controller),
                        value: monitor.controlChangeText(for: controller),
                        width: 78,
                        labelLineLimit: 3,
                        labelHeight: 40
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

    private func controlChangeLabel(for controller: Int) -> String {
        let baseLabel: String? = switch controller {
        case 0: "Bank\nSelect"
        case 1: "Modulation\nWheel"
        case 2: "Breath\nController"
        case 4: "Foot\nController"
        case 5: "Portamento\nTime"
        case 6: "Data\nEntry"
        case 7: "Output\nVolume"
        case 8: "Balance"
        case 10: "Pan"
        case 11: "Expression\nController"
        case 12: "Effect\nControl 1"
        case 13: "Effect\nControl 2"
        case 16: "General\nPurpose 1"
        case 17: "General\nPurpose 2"
        case 18: "General\nPurpose 3"
        case 19: "General\nPurpose 4"
        case 32: "Bank\nSelect LSB"
        case 33: "Modulation\nLSB"
        case 34: "Breath\nLSB"
        case 36: "Foot\nLSB"
        case 37: "Portamento\nLSB"
        case 38: "Data\nEntry LSB"
        case 39: "Volume\nLSB"
        case 40: "Balance\nLSB"
        case 42: "Pan\nLSB"
        case 43: "Expression\nLSB"
        case 44: "Effect 1\nLSB"
        case 45: "Effect 2\nLSB"
        case 48: "General 1\nLSB"
        case 49: "General 2\nLSB"
        case 50: "General 3\nLSB"
        case 51: "General 4\nLSB"
        case 64: "Sustain\nPedal"
        case 65: "Portamento\nOn/Off"
        case 66: "Sostenuto"
        case 67: "Soft\nPedal"
        case 68: "Legato\nFootswitch"
        case 69: "Hold 2"
        case 70: "Sound\nVariation"
        case 71: "Timbre\nResonance"
        case 72: "Release\nTime"
        case 73: "Attack\nTime"
        case 74: "Brightness"
        case 75: "Sound\nControl 6"
        case 76: "Sound\nControl 7"
        case 77: "Sound\nControl 8"
        case 78: "Sound\nControl 9"
        case 79: "Sound\nControl 10"
        case 80: "General\nPurpose 5"
        case 81: "General\nPurpose 6"
        case 82: "General\nPurpose 7"
        case 83: "General\nPurpose 8"
        case 84: "Portamento\nControl"
        case 88: "Velocity\nPrefix"
        case 91: "Effects 1\nDepth"
        case 92: "Effects 2\nDepth"
        case 93: "Effects 3\nDepth"
        case 94: "Effects 4\nDepth"
        case 95: "Effects 5\nDepth"
        case 96: "Data\nIncrement"
        case 97: "Data\nDecrement"
        case 98: "NRPN\nLSB"
        case 99: "NRPN\nMSB"
        case 100: "RPN\nLSB"
        case 101: "RPN\nMSB"
        case 120: "All Sound\nOff"
        case 121: "Reset All\nControllers"
        case 122: "Local\nControl"
        case 123: "All Notes\nOff"
        case 124: "Omni Off"
        case 125: "Omni On"
        case 126: "Mono\nMode On"
        case 127: "Poly\nMode On"
        default: nil
        }

        let ccNumber = String(format: "CC%02d", controller)
        guard let baseLabel else {
            return ccNumber
        }
        return "\(ccNumber)\n\(baseLabel)"
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

    private var performanceInspectorPanel: some View {
        Grid(alignment: .center, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                performanceInspectorCell(label: "Channel", value: monitor.latestChannelText, width: 78)
                performanceInspectorCell(label: "Program", value: monitor.latestProgramText, width: 78)
                performanceInspectorCell(label: "Last Note", value: monitor.latestNoteText, width: 78)
                performanceInspectorCell(label: "Velocity", value: monitor.latestVelocityText, width: 78)
            }

            GridRow {
                performanceInspectorCell(label: "Aftertouch", value: monitor.latestAftertouchText, width: 78)
                performanceInspectorCell(label: "Pitch Bend", value: monitor.latestPitchBendText, width: 106)
                performanceInspectorCell(label: "Modulation", value: monitor.latestModulationText, width: 78)
                performanceInspectorCell(label: "Output Volume", value: monitor.latestOutputVolumeText, width: 88)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(sectionPanelBackground)
    }

    private func performanceInspectorCell(label: String, value: String, width: CGFloat) -> some View {
        ReadOnlyLEDValue(label: label, value: value, width: width)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var resetPanel: some View {
        VStack(spacing: 10) {
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
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
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

private struct TitledSection<Trailing: View, Content: View>: View {
    let title: String
    let trailing: Trailing
    @ViewBuilder var content: Content

    init(
        title: String,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                BlueSectionTitle(title)
                Spacer(minLength: 0)
                trailing
            }
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
