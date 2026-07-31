import AppKit
import CoreMIDI
import Foundation

struct ChannelState: Identifiable {
    let id: Int
    let channelNumber: Int
    var numericDisplay: String
    var statusText: String
    var sourceName: String
    var lastOutputVolume: Int?
    var lastNote: Int?
    var lastVelocity: Int?
    var lastProgram: Int?
    var lastAftertouch: Int?
    var lastPitchBend: Int?
    var lastModulation: Int?
    var isActive: Bool

    static func placeholder(channel: Int) -> ChannelState {
        ChannelState(
            id: channel,
            channelNumber: channel + 1,
            numericDisplay: "---",
            statusText: "Waiting for MIDI input on channel \(channel + 1).",
            sourceName: "No input yet",
            lastOutputVolume: nil,
            lastNote: nil,
            lastVelocity: nil,
            lastProgram: nil,
            lastAftertouch: nil,
            lastPitchBend: nil,
            lastModulation: nil,
            isActive: false
        )
    }
}

struct MIDIEndpointOption: Identifiable, Hashable {
    let uniqueID: MIDIUniqueID
    let name: String

    var id: MIDIUniqueID { uniqueID }
}

struct MIDIInputSourceOption: Identifiable, Hashable {
    let uniqueID: MIDIUniqueID
    let name: String
    var isEnabled: Bool

    var id: MIDIUniqueID { uniqueID }
}

struct MIDIRouteDiagnostic: Identifiable {
    struct RecentMessage: Identifiable {
        let id = UUID()
        let timestamp: String
        let text: String
        let isPerformance: Bool
        let isRepeatWarning: Bool
    }

    struct Activity {
        let totalEventCount: Int
        let performanceEventCount: Int
        let activeSensingCount: Int
        let repeatWarningCount: Int
        let lastAnyTimestamp: String
        let lastAnyMessage: String
        let lastPerformanceTimestamp: String?
        let lastPerformanceMessage: String?
        let lastRepeatWarningTimestamp: String?
        let lastRepeatWarningMessage: String?
        let isRecentlyActive: Bool
        let isPerformanceRecentlyActive: Bool
        let recentMessages: [RecentMessage]
    }

    let kind: String
    let endpointUniqueID: MIDIUniqueID
    let name: String
    let entityUniqueID: MIDIUniqueID?
    let deviceUniqueID: MIDIUniqueID?
    let isSelected: Bool
    let activity: Activity?

    var id: String { "\(kind)-\(endpointUniqueID)" }
}

private struct MIDIEndpointActivity {
    var totalEventCount: Int = 0
    var performanceEventCount: Int = 0
    var activeSensingCount: Int = 0
    var repeatWarningCount: Int = 0
    var lastAnyTimestamp: String = ""
    var lastAnyMessage: String = ""
    var lastAnySeenAt: Date = .distantPast
    var lastPerformanceTimestamp: String?
    var lastPerformanceMessage: String?
    var lastPerformanceSeenAt: Date = .distantPast
    var lastRepeatWarningTimestamp: String?
    var lastRepeatWarningMessage: String?
    var recentMessages: [MIDIRouteDiagnostic.RecentMessage] = []

    var diagnosticActivity: MIDIRouteDiagnostic.Activity {
        MIDIRouteDiagnostic.Activity(
            totalEventCount: totalEventCount,
            performanceEventCount: performanceEventCount,
            activeSensingCount: activeSensingCount,
            repeatWarningCount: repeatWarningCount,
            lastAnyTimestamp: lastAnyTimestamp,
            lastAnyMessage: lastAnyMessage,
            lastPerformanceTimestamp: lastPerformanceTimestamp,
            lastPerformanceMessage: lastPerformanceMessage,
            lastRepeatWarningTimestamp: lastRepeatWarningTimestamp,
            lastRepeatWarningMessage: lastRepeatWarningMessage,
            isRecentlyActive: Date().timeIntervalSince(lastAnySeenAt) <= 2.0,
            isPerformanceRecentlyActive: Date().timeIntervalSince(lastPerformanceSeenAt) <= 2.0,
            recentMessages: recentMessages
        )
    }
}

private struct MIDINoteRepeatState {
    let timestamp: Date
    let velocity: Int
}

private struct MIDIEndpointDescriptor {
    let endpoint: MIDIEndpointRef
    let entityUniqueID: MIDIUniqueID?
    let deviceUniqueID: MIDIUniqueID?
}

private final class MIDIInputSourceContext {
    let uniqueID: MIDIUniqueID
    let name: String
    let descriptor: MIDIEndpointDescriptor

    init(uniqueID: MIDIUniqueID, name: String, descriptor: MIDIEndpointDescriptor) {
        self.uniqueID = uniqueID
        self.name = name
        self.descriptor = descriptor
    }
}

private struct ConnectedSource {
    let endpoint: MIDIEndpointRef
    let contextPointer: UnsafeMutableRawPointer
}

@MainActor
final class MIDIMonitor: ObservableObject {
    private enum DefaultsKey {
        static let suppressRepeatedNoteOn = "suppressRepeatedNoteOn"
        static let selectedDestinationID = "selectedDestinationID"
        static let selectedDestinationName = "selectedDestinationName"
    }

    struct EventLogEntry: Identifiable {
        let id = UUID()
        let timestamp: String
        let text: String
    }

    enum SaveLogsResult {
        case saved(inputURL: URL, outputURL: URL)
        case cancelled
        case failed
    }

    enum QuitLogDecision {
        case saveAndQuit
        case quitWithoutSaving
        case cancel
    }

    private static let eventTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private static let logFileTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMdd-HHmmss"
        return formatter
    }()

    @Published var channelStates: [ChannelState] = (0..<16).map(ChannelState.placeholder)
    @Published var inputSources: [MIDIInputSourceOption] = []
    @Published var destinations: [MIDIEndpointOption] = []
    @Published var selectedDestinationID: MIDIUniqueID? {
        didSet {
            persistSelectedDestination()
            updateDestinationSelectionDiagnostics()
            updateRealtimeDestinationSnapshot()
        }
    }
    @Published var footerStatus = "Starting CoreMIDI monitor..."
    @Published var lastSystemMessage = "System messages will appear here."
    @Published var inputLogEntries: [EventLogEntry] = []
    @Published var outputLogEntries: [EventLogEntry] = []
    @Published var sourceDiagnostics: [MIDIRouteDiagnostic] = []
    @Published var destinationDiagnostics: [MIDIRouteDiagnostic] = []
    @Published var lastReceivedChannel: Int?
    @Published var lastReceivedProgram: Int?
    @Published var lastReceivedNote: Int?
    @Published var lastReceivedVelocity: Int?
    @Published var lastReceivedAftertouch: Int?
    @Published var lastReceivedPitchBend: Int?
    @Published var lastReceivedModulation: Int?
    @Published var lastReceivedOutputVolume: Int?

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var outputPort = MIDIPortRef()
    nonisolated(unsafe) private var realtimeOutputPort = MIDIPortRef()
    nonisolated(unsafe) private var realtimeSelectedDestination = MIDIEndpointRef()
    nonisolated(unsafe) private var realtimeSelectedDestinationName = "No MIDI Thru"
    private var connectedSources: [MIDIUniqueID: ConnectedSource] = [:]
    private var sourceNameByID: [MIDIUniqueID: String] = [:]
    private var destinationByID: [MIDIUniqueID: MIDIEndpointDescriptor] = [:]
    private var sourceActivityByID: [MIDIUniqueID: MIDIEndpointActivity] = [:]
    private var destinationActivityByID: [MIDIUniqueID: MIDIEndpointActivity] = [:]
    private var recentNoteOnBySourceAndNote: [MIDIUniqueID: [Int: MIDINoteRepeatState]] = [:]
    private var parser = MIDIByteStreamParser()
    private var hasShownAnyLogThisSession = false
    private var inputSourceEnabledByID: [MIDIUniqueID: Bool] = [:]

    init() {
        setupMIDI()
        restoreSelectedDestinationPreference()
        refreshEndpoints()
    }

    deinit {
        MainActor.assumeIsolated {
            disconnectAllSources()
        }
        MIDIPortDispose(inputPort)
        MIDIPortDispose(outputPort)
        MIDIClientDispose(client)
    }

    var latestChannelText: String {
        lastReceivedChannel.map { ledText(for: $0 + 1) } ?? "---"
    }

    var latestProgramText: String {
        ledText(for: lastReceivedProgram)
    }

    var latestNoteText: String {
        ledText(for: lastReceivedNote)
    }

    var latestVelocityText: String {
        ledText(for: lastReceivedVelocity)
    }

    var latestAftertouchText: String {
        ledText(for: lastReceivedAftertouch)
    }

    var latestPitchBendText: String {
        ledText(for: lastReceivedPitchBend, digits: 5)
    }

    var latestModulationText: String {
        ledText(for: lastReceivedModulation)
    }

    var latestOutputVolumeText: String {
        ledText(for: lastReceivedOutputVolume)
    }

    var selectedDestinationName: String {
        guard let selectedDestinationID,
              let destination = destinations.first(where: { $0.uniqueID == selectedDestinationID }) else {
            return "No MIDI Thru"
        }
        return destination.name
    }

    var sourceSummaryText: String {
        if inputSources.isEmpty {
            return "No CoreMIDI sources found."
        }
        return inputSources.map(\.name).sorted().joined(separator: ", ")
    }

    var inputLogText: String {
        if inputLogEntries.isEmpty {
            return "Waiting for MIDI input..."
        }
        return inputLogEntries
            .map { "[\($0.timestamp)] \($0.text)" }
            .joined(separator: "\n")
    }

    var outputLogText: String {
        if outputLogEntries.isEmpty {
            return "Waiting for MIDI output..."
        }
        return outputLogEntries
            .map { "[\($0.timestamp)] \($0.text)" }
            .joined(separator: "\n")
    }

    var selectedDestinationDiagnosticText: String {
        guard let selectedDestinationID,
              let destination = destinationDiagnostics.first(where: { $0.endpointUniqueID == selectedDestinationID }) else {
            return "No MIDI Thru selected."
        }
        return "\(destination.name)  endpoint \(destination.endpointUniqueID)  entity \(diagnosticValue(destination.entityUniqueID))  device \(diagnosticValue(destination.deviceUniqueID))"
    }

    private var suppressRepeatedNoteOnEnabled: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.suppressRepeatedNoteOn)
    }

    var shouldPromptToSaveLogsOnQuit: Bool {
        hasShownAnyLogThisSession
    }

    func refreshEndpoints() {
        reconnectSources()
        refreshDestinations()
    }

    func setInputSourceEnabled(_ uniqueID: MIDIUniqueID, isEnabled: Bool) {
        inputSourceEnabledByID[uniqueID] = isEnabled
        if let index = inputSources.firstIndex(where: { $0.uniqueID == uniqueID }) {
            inputSources[index].isEnabled = isEnabled
        }
        reconnectSources()
    }

    func updateLogVisibility(inputVisible: Bool, outputVisible: Bool) {
        if inputVisible || outputVisible {
            hasShownAnyLogThisSession = true
        }
    }

    func saveLogsInteractively() -> SaveLogsResult {
        let panel = NSOpenPanel()
        panel.title = "Save Logs"
        panel.message = "Choose a folder where MIDImunger should save separate input and output log files."
        panel.prompt = "Save Logs"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let directoryURL = panel.url else {
            return .cancelled
        }

        do {
            let savedURLs = try saveLogs(to: directoryURL)
            footerStatus = "Saved logs to \(directoryURL.path)."
            return .saved(inputURL: savedURLs.inputURL, outputURL: savedURLs.outputURL)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn’t Save MIDImunger Logs"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return .failed
        }
    }

    func promptToSaveLogsBeforeQuit() -> QuitLogDecision {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Save MIDImunger logs before quitting?"
        alert.informativeText = "MIDImunger can save the current input and output logs as separate plain-text files."
        alert.addButton(withTitle: "Save Logs")
        alert.addButton(withTitle: "Quit Without Saving")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            switch saveLogsInteractively() {
            case .saved:
                return .saveAndQuit
            case .cancelled, .failed:
                return .cancel
            }
        case .alertSecondButtonReturn:
            return .quitWithoutSaving
        default:
            return .cancel
        }
    }

    func sendAllNotesOff() {
        guard selectedDestinationID != nil else {
            footerStatus = "Choose a MIDI Thru destination before sending All Notes Off."
            return
        }
        for channel in 0..<16 {
            send(bytes: [0xB0 | UInt8(channel), 123, 0])
        }
        footerStatus = "Sent All Notes Off on channels 1-16 to \(selectedDestinationName)."
    }

    private func setupMIDI() {
        MIDIClientCreateWithBlock("MIDImunger Client" as CFString, &client) { notificationPointer in
            let messageID = notificationPointer.pointee.messageID
            Task { @MainActor [weak self] in
                self?.footerStatus = "CoreMIDI notification: \(messageID.rawValue). Refreshing endpoints."
                self?.refreshEndpoints()
            }
        }

        MIDIInputPortCreateWithBlock(client, "MIDImunger Input" as CFString, &inputPort) { [weak self] packetList, sourceConnectionContext in
            guard let self else { return }
            let bytesByPacket = Self.packetBytes(from: packetList)
            let sourceContext = sourceConnectionContext.map {
                Unmanaged<MIDIInputSourceContext>.fromOpaque($0).takeUnretainedValue()
            }
            let sourceName = sourceContext?.name
            let sourceUniqueID = sourceContext?.uniqueID
            let forwardedResults = bytesByPacket.map { packetBytes in
                self.forwardRealtime(bytes: packetBytes, from: sourceContext?.descriptor)
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                for (packetBytes, forwardedResult) in zip(bytesByPacket, forwardedResults) {
                    self.handleIncomingBytes(packetBytes, sourceID: sourceUniqueID, sourceName: sourceName)
                    if let forwardedResult {
                        self.appendOutputLog("\(forwardedResult.destinationName): \(forwardedResult.bytesDescription)")
                    }
                }
            }
        }

        MIDIOutputPortCreate(client, "MIDImunger Output" as CFString, &outputPort)
        realtimeOutputPort = outputPort
    }

    private func reconnectSources() {
        disconnectAllSources()
        sourceNameByID.removeAll()
        sourceDiagnostics.removeAll()
        inputSources.removeAll()

        let sourceCount = MIDIGetNumberOfSources()
        var enabledSourceCount = 0
        for index in 0..<sourceCount {
            let source = MIDIGetSource(index)
            guard source != 0 else { continue }
            let uniqueID = propertyInt32(kMIDIPropertyUniqueID, of: source)
            let name = endpointDisplayName(source)
            let descriptor = endpointDescriptor(for: source)
            let isEnabled = inputSourceEnabledByID[uniqueID] ?? true
            inputSourceEnabledByID[uniqueID] = isEnabled
            sourceNameByID[uniqueID] = name
            inputSources.append(MIDIInputSourceOption(uniqueID: uniqueID, name: name, isEnabled: isEnabled))
            sourceDiagnostics.append(
                MIDIRouteDiagnostic(
                    kind: "source",
                    endpointUniqueID: uniqueID,
                    name: name,
                    entityUniqueID: descriptor.entityUniqueID,
                    deviceUniqueID: descriptor.deviceUniqueID,
                    isSelected: false,
                    activity: sourceActivityByID[uniqueID]?.diagnosticActivity
                )
            )
            guard isEnabled else { continue }
            let context = MIDIInputSourceContext(uniqueID: uniqueID, name: name, descriptor: descriptor)
            let contextPointer = Unmanaged.passRetained(context).toOpaque()
            let status = MIDIPortConnectSource(inputPort, source, contextPointer)
            guard status == noErr else {
                Unmanaged<MIDIInputSourceContext>.fromOpaque(contextPointer).release()
                continue
            }
            connectedSources[uniqueID] = ConnectedSource(endpoint: source, contextPointer: contextPointer)
            enabledSourceCount += 1
        }

        footerStatus = sourceCount == 0
            ? "No MIDI input sources are available."
            : "Listening to \(enabledSourceCount) of \(sourceCount) MIDI source\(sourceCount == 1 ? "" : "s")."
    }

    private func disconnectAllSources() {
        for connectedSource in connectedSources.values {
            MIDIPortDisconnectSource(inputPort, connectedSource.endpoint)
            Unmanaged<MIDIInputSourceContext>.fromOpaque(connectedSource.contextPointer).release()
        }
        connectedSources.removeAll()
    }

    private func refreshDestinations() {
        destinationByID.removeAll()
        destinations.removeAll()
        destinationDiagnostics.removeAll()

        let destinationCount = MIDIGetNumberOfDestinations()
        for index in 0..<destinationCount {
            let destination = MIDIGetDestination(index)
            guard destination != 0 else { continue }
            let uniqueID = propertyInt32(kMIDIPropertyUniqueID, of: destination)
            let name = endpointDisplayName(destination)
            let descriptor = endpointDescriptor(for: destination)
            destinationByID[uniqueID] = descriptor
            destinations.append(MIDIEndpointOption(uniqueID: uniqueID, name: name))
            destinationDiagnostics.append(
                MIDIRouteDiagnostic(
                    kind: "destination",
                    endpointUniqueID: uniqueID,
                    name: name,
                    entityUniqueID: descriptor.entityUniqueID,
                    deviceUniqueID: descriptor.deviceUniqueID,
                    isSelected: selectedDestinationID == uniqueID,
                    activity: destinationActivityByID[uniqueID]?.diagnosticActivity
                )
            )
        }
        restoreSelectedDestinationIfPossible()
        updateDestinationSelectionDiagnostics()
        updateRealtimeDestinationSnapshot()
    }

    private func handleIncomingBytes(_ bytes: [UInt8], sourceID: MIDIUniqueID?, sourceName: String?) {
        for message in parser.consume(bytes: bytes, sourceName: sourceName) {
            let repeatWarning = sourceID.flatMap { detectRepeatedNoteOn(for: $0, parsedMessage: message) }
            if let sourceID {
                recordSourceActivity(sourceID, message: message.statusText, parsedMessage: message, repeatWarning: repeatWarning)
            }
            if let repeatWarning {
                if suppressRepeatedNoteOnEnabled {
                    footerStatus = "Suppressed repeated Note On from \(sourceName ?? "Unknown Source")."
                    appendInputLog("[Suppressed Repeat] " + repeatWarning)
                    continue
                }
            }
            apply(message: message)
            appendInputLog(message.statusText + "  [" + hex(bytes) + "]")
        }
    }

    private func apply(message: ParsedMIDIMessage) {
        guard let channel = message.channel else {
            lastSystemMessage = message.statusText
            return
        }

        var state = channelStates[channel]
        state.numericDisplay = message.numericDisplay
        state.statusText = message.statusText
        state.sourceName = message.sourceName ?? "Any MIDI source"
        state.isActive = true
        lastReceivedChannel = channel

        if let lastOutputVolume = message.lastOutputVolume {
            state.lastOutputVolume = lastOutputVolume
            lastReceivedOutputVolume = lastOutputVolume
        }
        if let lastNote = message.lastNote {
            state.lastNote = lastNote
        }
        if let lastVelocity = message.lastVelocity {
            state.lastVelocity = lastVelocity
        }
        if let lastProgram = message.lastProgram {
            state.lastProgram = lastProgram
            lastReceivedProgram = lastProgram
        }
        if let lastAftertouch = message.lastAftertouch {
            state.lastAftertouch = lastAftertouch
            lastReceivedAftertouch = lastAftertouch
        }
        if let lastPitchBend = message.lastPitchBend {
            state.lastPitchBend = lastPitchBend
            lastReceivedPitchBend = lastPitchBend
        }
        if let lastModulation = message.lastModulation {
            state.lastModulation = lastModulation
            lastReceivedModulation = lastModulation
        }

        if let lastPlayedNote = message.lastPlayedNote {
            lastReceivedNote = lastPlayedNote
        }
        if let lastPlayedVelocity = message.lastPlayedVelocity {
            lastReceivedVelocity = lastPlayedVelocity
        }

        channelStates[channel] = state
    }

    private func forward(bytes: [UInt8], from sourceDescriptor: MIDIEndpointDescriptor?) {
        guard shouldForward(from: sourceDescriptor) else { return }
        send(bytes: bytes)
    }

    private func updateRealtimeDestinationSnapshot() {
        if let selectedDestinationID,
           let destination = destinationByID[selectedDestinationID]?.endpoint {
            realtimeSelectedDestination = destination
            realtimeSelectedDestinationName = selectedDestinationName
        } else {
            realtimeSelectedDestination = 0
            realtimeSelectedDestinationName = "No MIDI Thru"
        }
    }

    private struct ImmediateForwardResult {
        let destinationName: String
        let bytesDescription: String
    }

    nonisolated private func forwardRealtime(bytes: [UInt8], from sourceDescriptor: MIDIEndpointDescriptor?) -> ImmediateForwardResult? {
        let destination = realtimeSelectedDestination
        guard destination != 0 else { return nil }
        if let sourceDescriptor, sourceDescriptor.endpoint == destination {
            return nil
        }

        let bufferSize = 1024
        var packetBuffer = [UInt8](repeating: 0, count: bufferSize)
        packetBuffer.withUnsafeMutableBytes { rawBuffer in
            guard let packetListPointer = rawBuffer.baseAddress?.assumingMemoryBound(to: MIDIPacketList.self) else {
                return
            }

            let startPacket = MIDIPacketListInit(packetListPointer)
            _ = MIDIPacketListAdd(packetListPointer, bufferSize, startPacket, 0, bytes.count, bytes)
            MIDISend(realtimeOutputPort, destination, packetListPointer)
        }

        return ImmediateForwardResult(
            destinationName: realtimeSelectedDestinationName,
            bytesDescription: "[" + bytes.map { String(format: "%02X", $0) }.joined(separator: " ") + "]"
        )
    }

    private func send(bytes: [UInt8]) {
        guard let selectedDestinationID,
              let destination = destinationByID[selectedDestinationID]?.endpoint else {
            return
        }

        let bufferSize = 1024
        var packetBuffer = [UInt8](repeating: 0, count: bufferSize)
        packetBuffer.withUnsafeMutableBytes { rawBuffer in
            guard let packetListPointer = rawBuffer.baseAddress?.assumingMemoryBound(to: MIDIPacketList.self) else {
                return
            }

            let startPacket = MIDIPacketListInit(packetListPointer)
            _ = MIDIPacketListAdd(packetListPointer, bufferSize, startPacket, 0, bytes.count, bytes)
            MIDISend(outputPort, destination, packetListPointer)
        }

        recordDestinationActivity(selectedDestinationID, message: "[\(hex(bytes))]")
        appendOutputLog("\(selectedDestinationName): [" + hex(bytes) + "]")
    }

    private static func packetBytes(from packetList: UnsafePointer<MIDIPacketList>) -> [[UInt8]] {
        var packets: [[UInt8]] = []
        var packet = packetList.pointee.packet

        for _ in 0..<packetList.pointee.numPackets {
            let count = Int(packet.length)
            let bytes = withUnsafeBytes(of: packet.data) { rawBuffer in
                Array(rawBuffer.prefix(count))
            }
            packets.append(bytes)
            packet = MIDIPacketNext(&packet).pointee
        }

        return packets
    }

    private func endpointDisplayName(_ endpoint: MIDIObjectRef) -> String {
        propertyString(kMIDIPropertyDisplayName, of: endpoint)
            ?? propertyString(kMIDIPropertyName, of: endpoint)
            ?? "Unnamed MIDI Endpoint"
    }

    private func propertyString(_ property: CFString, of object: MIDIObjectRef) -> String? {
        var unmanaged: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(object, property, &unmanaged)
        guard status == noErr else { return nil }
        return unmanaged?.takeRetainedValue() as String?
    }

    private func propertyInt32(_ property: CFString, of object: MIDIObjectRef) -> Int32 {
        var value: Int32 = 0
        MIDIObjectGetIntegerProperty(object, property, &value)
        return value
    }

    private func shouldForward(from sourceDescriptor: MIDIEndpointDescriptor?) -> Bool {
        guard let selectedDestinationID,
              let destinationDescriptor = destinationByID[selectedDestinationID] else {
            return false
        }
        guard let sourceDescriptor else {
            return true
        }

        if sourceDescriptor.endpoint == destinationDescriptor.endpoint {
            footerStatus = "Suppressed MIDI Thru loop back into the same endpoint: \(selectedDestinationName)."
            return false
        }

        return true
    }

    private func endpointDescriptor(for endpoint: MIDIEndpointRef) -> MIDIEndpointDescriptor {
        var entity = MIDIEntityRef()
        let entityStatus = MIDIEndpointGetEntity(endpoint, &entity)
        let entityUniqueID = entityStatus == noErr && entity != 0
            ? propertyInt32(kMIDIPropertyUniqueID, of: entity)
            : nil

        var device = MIDIDeviceRef()
        let deviceStatus = entityStatus == noErr && entity != 0 ? MIDIEntityGetDevice(entity, &device) : kMIDIUnknownEndpoint
        let deviceUniqueID = deviceStatus == noErr && device != 0
            ? propertyInt32(kMIDIPropertyUniqueID, of: device)
            : nil

        return MIDIEndpointDescriptor(
            endpoint: endpoint,
            entityUniqueID: entityUniqueID,
            deviceUniqueID: deviceUniqueID
        )
    }

    private func ledText(for value: Int?, digits: Int = 3) -> String {
        guard let value else { return String(repeating: "-", count: digits) }
        let upperBound = Int(pow(10.0, Double(digits))) - 1
        let clamped = min(max(value, 0), upperBound)
        return String(format: "%0\(digits)d", clamped)
    }

    private func appendInputLog(_ text: String) {
        appendLogEntry(text, to: &inputLogEntries)
    }

    private func appendOutputLog(_ text: String) {
        appendLogEntry(text, to: &outputLogEntries)
    }

    private func appendLogEntry(_ text: String, to entries: inout [EventLogEntry]) {
        let entry = EventLogEntry(
            timestamp: Self.eventTimestampFormatter.string(from: Date()),
            text: text
        )
        entries.append(entry)
        let maxEntries = 1000
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private func saveLogs(to directoryURL: URL) throws -> (inputURL: URL, outputURL: URL) {
        let timestamp = Self.logFileTimestampFormatter.string(from: Date())
        let inputURL = directoryURL.appendingPathComponent("MIDImunger In \(timestamp).txt")
        let outputURL = directoryURL.appendingPathComponent("MIDImunger Out \(timestamp).txt")

        try savedLogText(for: inputLogEntries).write(to: inputURL, atomically: true, encoding: .utf8)
        try savedLogText(for: outputLogEntries).write(to: outputURL, atomically: true, encoding: .utf8)

        return (inputURL, outputURL)
    }

    private func savedLogText(for entries: [EventLogEntry]) -> String {
        entries.map { "[\($0.timestamp)] \($0.text)" }.joined(separator: "\n")
    }

    private func updateDestinationSelectionDiagnostics() {
        destinationDiagnostics = destinationDiagnostics.map { diagnostic in
            MIDIRouteDiagnostic(
                kind: diagnostic.kind,
                endpointUniqueID: diagnostic.endpointUniqueID,
                name: diagnostic.name,
                entityUniqueID: diagnostic.entityUniqueID,
                deviceUniqueID: diagnostic.deviceUniqueID,
                isSelected: diagnostic.endpointUniqueID == selectedDestinationID,
                activity: destinationActivityByID[diagnostic.endpointUniqueID]?.diagnosticActivity
            )
        }
    }

    private func persistSelectedDestination() {
        let defaults = UserDefaults.standard

        guard let selectedDestinationID,
              let destination = destinations.first(where: { $0.uniqueID == selectedDestinationID }) else {
            defaults.removeObject(forKey: DefaultsKey.selectedDestinationID)
            defaults.removeObject(forKey: DefaultsKey.selectedDestinationName)
            return
        }

        defaults.set(Int(selectedDestinationID), forKey: DefaultsKey.selectedDestinationID)
        defaults.set(destination.name, forKey: DefaultsKey.selectedDestinationName)
    }

    private func restoreSelectedDestinationPreference() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: DefaultsKey.selectedDestinationID) != nil else {
            selectedDestinationID = nil
            return
        }

        selectedDestinationID = MIDIUniqueID(defaults.integer(forKey: DefaultsKey.selectedDestinationID))
    }

    private func restoreSelectedDestinationIfPossible() {
        guard !destinations.isEmpty else {
            selectedDestinationID = nil
            return
        }

        if let selectedDestinationID, destinationByID[selectedDestinationID] != nil {
            return
        }

        let defaults = UserDefaults.standard
        if defaults.object(forKey: DefaultsKey.selectedDestinationID) != nil {
            let savedID = MIDIUniqueID(defaults.integer(forKey: DefaultsKey.selectedDestinationID))
            if destinationByID[savedID] != nil {
                selectedDestinationID = savedID
                return
            }
        }

        if let savedName = defaults.string(forKey: DefaultsKey.selectedDestinationName),
           let matchingDestination = destinations.first(where: { $0.name == savedName }) {
            selectedDestinationID = matchingDestination.uniqueID
            return
        }

        selectedDestinationID = nil
    }

    private func recordSourceActivity(_ uniqueID: MIDIUniqueID, message: String, parsedMessage: ParsedMIDIMessage, repeatWarning: String?) {
        var activity = sourceActivityByID[uniqueID] ?? MIDIEndpointActivity()
        let now = Date()
        let timestamp = Self.eventTimestampFormatter.string(from: now)
        let isPerformance = isPerformanceMessage(message)
        activity.totalEventCount += 1
        activity.lastAnyTimestamp = timestamp
        activity.lastAnyMessage = message
        activity.lastAnySeenAt = now
        activity.recentMessages.append(
            MIDIRouteDiagnostic.RecentMessage(
                timestamp: timestamp,
                text: message,
                isPerformance: isPerformance,
                isRepeatWarning: false
            )
        )
        if activity.recentMessages.count > 5 {
            activity.recentMessages.removeFirst(activity.recentMessages.count - 5)
        }
        if isPerformance {
            activity.performanceEventCount += 1
            activity.lastPerformanceTimestamp = timestamp
            activity.lastPerformanceMessage = message
            activity.lastPerformanceSeenAt = now
        } else if isActiveSensingMessage(message) {
            activity.activeSensingCount += 1
        }

        if let warning = repeatWarning {
            activity.repeatWarningCount += 1
            activity.lastRepeatWarningTimestamp = timestamp
            activity.lastRepeatWarningMessage = warning
            activity.recentMessages.append(
                MIDIRouteDiagnostic.RecentMessage(
                    timestamp: timestamp,
                    text: warning,
                    isPerformance: true,
                    isRepeatWarning: true
                )
            )
            if activity.recentMessages.count > 5 {
                activity.recentMessages.removeFirst(activity.recentMessages.count - 5)
            }
            appendInputLog("[Repeat Detector] " + warning)
        }

        sourceActivityByID[uniqueID] = activity
        refreshSourceActivityDiagnostics()
    }

    private func recordDestinationActivity(_ uniqueID: MIDIUniqueID, message: String) {
        var activity = destinationActivityByID[uniqueID] ?? MIDIEndpointActivity()
        let now = Date()
        let timestamp = Self.eventTimestampFormatter.string(from: now)
        activity.totalEventCount += 1
        activity.performanceEventCount += 1
        activity.lastAnyTimestamp = timestamp
        activity.lastAnyMessage = message
        activity.lastAnySeenAt = now
        activity.lastPerformanceTimestamp = timestamp
        activity.lastPerformanceMessage = message
        activity.lastPerformanceSeenAt = now
        activity.recentMessages.append(
            MIDIRouteDiagnostic.RecentMessage(
                timestamp: timestamp,
                text: message,
                isPerformance: true,
                isRepeatWarning: false
            )
        )
        if activity.recentMessages.count > 5 {
            activity.recentMessages.removeFirst(activity.recentMessages.count - 5)
        }
        destinationActivityByID[uniqueID] = activity
        updateDestinationSelectionDiagnostics()
    }

    private func refreshSourceActivityDiagnostics() {
        sourceDiagnostics = sourceDiagnostics.map { diagnostic in
            MIDIRouteDiagnostic(
                kind: diagnostic.kind,
                endpointUniqueID: diagnostic.endpointUniqueID,
                name: diagnostic.name,
                entityUniqueID: diagnostic.entityUniqueID,
                deviceUniqueID: diagnostic.deviceUniqueID,
                isSelected: diagnostic.isSelected,
                activity: sourceActivityByID[diagnostic.endpointUniqueID]?.diagnosticActivity
            )
        }
    }

    private func diagnosticValue(_ value: MIDIUniqueID?) -> String {
        value.map(String.init) ?? "-"
    }

    private func isActiveSensingMessage(_ message: String) -> Bool {
        message.contains("Active Sensing")
    }

    private func isPerformanceMessage(_ message: String) -> Bool {
        !isActiveSensingMessage(message)
    }

    private func detectRepeatedNoteOn(for uniqueID: MIDIUniqueID, parsedMessage: ParsedMIDIMessage) -> String? {
        guard parsedMessage.isNoteOn,
              let note = parsedMessage.lastPlayedNote,
              let velocity = parsedMessage.lastPlayedVelocity else {
            return nil
        }

        let now = Date()
        let prior = recentNoteOnBySourceAndNote[uniqueID]?[note]
        recentNoteOnBySourceAndNote[uniqueID, default: [:]][note] = MIDINoteRepeatState(timestamp: now, velocity: velocity)

        guard let prior else { return nil }
        let intervalMS = Int(now.timeIntervalSince(prior.timestamp) * 1000.0)
        guard intervalMS >= 0, intervalMS <= 300 else { return nil }

        let sourceName = sourceNameByID[uniqueID] ?? "Unknown Source"
        return "\(sourceName): repeated Note On note \(note) within \(intervalMS) ms (velocities \(prior.velocity)->\(velocity))"
    }
}

private struct ParsedMIDIMessage {
    var channel: Int?
    var numericDisplay: String
    var statusText: String
    var sourceName: String?
    var lastOutputVolume: Int?
    var lastNote: Int?
    var lastVelocity: Int?
    var lastProgram: Int?
    var lastAftertouch: Int?
    var lastPitchBend: Int?
    var lastModulation: Int?
    var lastPlayedNote: Int?
    var lastPlayedVelocity: Int?
    var isNoteOn: Bool
}

private struct MIDIByteStreamParser {
    private var runningStatus: UInt8?
    private var currentStatus: UInt8?
    private var currentData: [UInt8] = []
    private var currentExpectedDataLength = 0
    private var inSysEx = false
    private var sysexBytes: [UInt8] = []

    mutating func consume(bytes: [UInt8], sourceName: String? = nil) -> [ParsedMIDIMessage] {
        var messages: [ParsedMIDIMessage] = []

        for byte in bytes {
            if byte >= 0xF8 {
                messages.append(systemMessage(text: realtimeName(for: byte), bytes: [byte], sourceName: sourceName))
                continue
            }

            if inSysEx {
                sysexBytes.append(byte)
                if byte == 0xF7 {
                    messages.append(systemMessage(text: describeSysEx(bytes: sysexBytes), bytes: sysexBytes, sourceName: sourceName))
                    sysexBytes.removeAll(keepingCapacity: true)
                    inSysEx = false
                    currentStatus = nil
                    currentData.removeAll(keepingCapacity: true)
                    currentExpectedDataLength = 0
                }
                continue
            }

            if byte & 0x80 != 0 {
                currentData.removeAll(keepingCapacity: true)
                currentStatus = byte
                currentExpectedDataLength = expectedDataLength(for: byte)

                if byte == 0xF0 {
                    inSysEx = true
                    sysexBytes = [byte]
                    runningStatus = nil
                    continue
                }

                if byte < 0xF0 {
                    runningStatus = byte
                } else {
                    runningStatus = nil
                }

                if currentExpectedDataLength == 0 {
                    messages.append(systemMessage(text: systemCommonName(for: byte), bytes: [byte], sourceName: sourceName))
                    currentStatus = nil
                }
                continue
            }

            if currentStatus == nil, let runningStatus {
                currentStatus = runningStatus
                currentExpectedDataLength = expectedDataLength(for: runningStatus)
            }

            guard let currentStatus else {
                continue
            }

            currentData.append(byte)
            if currentData.count == currentExpectedDataLength {
                let complete = [currentStatus] + currentData
                messages.append(describeChannelOrSystemMessage(bytes: complete, sourceName: sourceName))
                if currentStatus < 0xF0 {
                    currentData.removeAll(keepingCapacity: true)
                    self.currentStatus = runningStatus
                    currentExpectedDataLength = expectedDataLength(for: runningStatus ?? currentStatus)
                } else {
                    self.currentStatus = nil
                    currentData.removeAll(keepingCapacity: true)
                    currentExpectedDataLength = 0
                }
            }
        }

        return messages
    }

    private func describeChannelOrSystemMessage(bytes: [UInt8], sourceName: String?) -> ParsedMIDIMessage {
        guard let status = bytes.first else {
            return systemMessage(text: "Empty MIDI packet", bytes: bytes, sourceName: sourceName)
        }

        if status >= 0xF0 {
            return systemMessage(text: systemText(for: bytes), bytes: bytes, sourceName: sourceName)
        }

        let channel = Int(status & 0x0F)
        let messageType = status & 0xF0

        switch messageType {
        case 0x80:
            let note = Int(bytes[safe: 1] ?? 0)
            let velocity = Int(bytes[safe: 2] ?? 0)
            return ParsedMIDIMessage(
                channel: channel,
                numericDisplay: ledText(for: note),
                statusText: prefix(sourceName) + "Note Off  note \(note) velocity \(velocity)",
                sourceName: sourceName,
                lastOutputVolume: nil,
                lastNote: note,
                lastVelocity: velocity,
                lastProgram: nil,
                lastAftertouch: nil,
                lastPitchBend: nil,
                lastModulation: nil,
                lastPlayedNote: nil,
                lastPlayedVelocity: nil,
                isNoteOn: false
            )
        case 0x90:
            let note = Int(bytes[safe: 1] ?? 0)
            let velocity = Int(bytes[safe: 2] ?? 0)
            let label = velocity == 0 ? "Note Off" : "Note On"
            return ParsedMIDIMessage(
                channel: channel,
                numericDisplay: ledText(for: note),
                statusText: prefix(sourceName) + "\(label)  note \(note) velocity \(velocity)",
                sourceName: sourceName,
                lastOutputVolume: nil,
                lastNote: note,
                lastVelocity: velocity,
                lastProgram: nil,
                lastAftertouch: nil,
                lastPitchBend: nil,
                lastModulation: nil,
                lastPlayedNote: velocity == 0 ? nil : note,
                lastPlayedVelocity: velocity == 0 ? nil : velocity,
                isNoteOn: velocity != 0
            )
        case 0xA0:
            let note = Int(bytes[safe: 1] ?? 0)
            let pressure = Int(bytes[safe: 2] ?? 0)
            return ParsedMIDIMessage(
                channel: channel,
                numericDisplay: ledText(for: pressure),
                statusText: prefix(sourceName) + "Poly Aftertouch  note \(note) pressure \(pressure)",
                sourceName: sourceName,
                lastOutputVolume: nil,
                lastNote: note,
                lastVelocity: nil,
                lastProgram: nil,
                lastAftertouch: pressure,
                lastPitchBend: nil,
                lastModulation: nil,
                lastPlayedNote: nil,
                lastPlayedVelocity: nil,
                isNoteOn: false
            )
        case 0xB0:
            let controller = Int(bytes[safe: 1] ?? 0)
            let value = Int(bytes[safe: 2] ?? 0)
            let controllerText = controller == 7 ? "Output Volume" : "CC \(controller)"
            return ParsedMIDIMessage(
                channel: channel,
                numericDisplay: ledText(for: value),
                statusText: prefix(sourceName) + "\(controllerText) value \(value)",
                sourceName: sourceName,
                lastOutputVolume: controller == 7 ? value : nil,
                lastNote: nil,
                lastVelocity: nil,
                lastProgram: nil,
                lastAftertouch: nil,
                lastPitchBend: nil,
                lastModulation: controller == 1 ? value : nil,
                lastPlayedNote: nil,
                lastPlayedVelocity: nil,
                isNoteOn: false
            )
        case 0xC0:
            let program = Int(bytes[safe: 1] ?? 0) + 1
            return ParsedMIDIMessage(
                channel: channel,
                numericDisplay: ledText(for: program),
                statusText: prefix(sourceName) + "Program Change  program \(program)",
                sourceName: sourceName,
                lastOutputVolume: nil,
                lastNote: nil,
                lastVelocity: nil,
                lastProgram: program,
                lastAftertouch: nil,
                lastPitchBend: nil,
                lastModulation: nil,
                lastPlayedNote: nil,
                lastPlayedVelocity: nil,
                isNoteOn: false
            )
        case 0xD0:
            let pressure = Int(bytes[safe: 1] ?? 0)
            return ParsedMIDIMessage(
                channel: channel,
                numericDisplay: ledText(for: pressure),
                statusText: prefix(sourceName) + "Channel Aftertouch  pressure \(pressure)",
                sourceName: sourceName,
                lastOutputVolume: nil,
                lastNote: nil,
                lastVelocity: nil,
                lastProgram: nil,
                lastAftertouch: pressure,
                lastPitchBend: nil,
                lastModulation: nil,
                lastPlayedNote: nil,
                lastPlayedVelocity: nil,
                isNoteOn: false
            )
        case 0xE0:
            let lsb = Int(bytes[safe: 1] ?? 0)
            let msb = Int(bytes[safe: 2] ?? 0)
            let bend = (msb << 7) | lsb
            return ParsedMIDIMessage(
                channel: channel,
                numericDisplay: ledText(for: msb),
                statusText: prefix(sourceName) + "Pitch Bend  value \(bend)",
                sourceName: sourceName,
                lastOutputVolume: nil,
                lastNote: nil,
                lastVelocity: nil,
                lastProgram: nil,
                lastAftertouch: nil,
                lastPitchBend: bend,
                lastModulation: nil,
                lastPlayedNote: nil,
                lastPlayedVelocity: nil,
                isNoteOn: false
            )
        default:
            return ParsedMIDIMessage(
                channel: channel,
                numericDisplay: "---",
                statusText: prefix(sourceName) + "Unknown MIDI message \(hex(bytes))",
                sourceName: sourceName,
                lastOutputVolume: nil,
                lastNote: nil,
                lastVelocity: nil,
                lastProgram: nil,
                lastAftertouch: nil,
                lastPitchBend: nil,
                lastModulation: nil,
                lastPlayedNote: nil,
                lastPlayedVelocity: nil,
                isNoteOn: false
            )
        }
    }

    private func systemMessage(text: String, bytes: [UInt8], sourceName: String?) -> ParsedMIDIMessage {
        ParsedMIDIMessage(
            channel: nil,
            numericDisplay: "---",
            statusText: prefix(sourceName) + text + "  " + hex(bytes),
            sourceName: sourceName,
            lastOutputVolume: nil,
            lastNote: nil,
            lastVelocity: nil,
            lastProgram: nil,
            lastAftertouch: nil,
            lastPitchBend: nil,
            lastModulation: nil,
            lastPlayedNote: nil,
            lastPlayedVelocity: nil,
            isNoteOn: false
        )
    }

    private func expectedDataLength(for status: UInt8) -> Int {
        switch status {
        case 0x80 ... 0x8F, 0x90 ... 0x9F, 0xA0 ... 0xAF, 0xB0 ... 0xBF, 0xE0 ... 0xEF:
            return 2
        case 0xC0 ... 0xCF, 0xD0 ... 0xDF, 0xF1, 0xF3:
            return 1
        case 0xF2:
            return 2
        default:
            return 0
        }
    }

    private func systemText(for bytes: [UInt8]) -> String {
        guard let status = bytes.first else { return "System message" }
        switch status {
        case 0xF1:
            return "MIDI Time Code quarter frame \(Int(bytes[safe: 1] ?? 0))"
        case 0xF2:
            let value = Int(bytes[safe: 1] ?? 0) | (Int(bytes[safe: 2] ?? 0) << 7)
            return "Song Position Pointer \(value)"
        case 0xF3:
            return "Song Select \(Int(bytes[safe: 1] ?? 0))"
        case 0xF6:
            return "Tune Request"
        default:
            return systemCommonName(for: status)
        }
    }

    private func systemCommonName(for status: UInt8) -> String {
        switch status {
        case 0xF4, 0xF5:
            return "Undefined system common"
        case 0xF6:
            return "Tune Request"
        case 0xF7:
            return "End of SysEx"
        default:
            return "System message"
        }
    }

    private func realtimeName(for status: UInt8) -> String {
        switch status {
        case 0xF8: return "Timing Clock"
        case 0xFA: return "Start"
        case 0xFB: return "Continue"
        case 0xFC: return "Stop"
        case 0xFE: return "Active Sensing"
        case 0xFF: return "System Reset"
        default: return "Realtime \(String(format: "0x%02X", status))"
        }
    }

    private func describeSysEx(bytes: [UInt8]) -> String {
        let manufacturer = bytes.count > 1 ? String(format: "0x%02X", bytes[1]) : "unknown"
        return "SysEx  manufacturer \(manufacturer)  \(bytes.count) bytes"
    }

    private func ledText(for value: Int?) -> String {
        guard let value else { return "---" }
        let clamped = min(max(value, 0), 999)
        return String(format: "%03d", clamped)
    }

    private func prefix(_ sourceName: String?) -> String {
        guard let sourceName, sourceName.isEmpty == false else { return "" }
        return "\(sourceName): "
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

private extension Array where Element == UInt8 {
    subscript(safe index: Int) -> UInt8? {
        indices.contains(index) ? self[index] : nil
    }
}
