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

private final class MIDIInputSourceContext {
    let uniqueID: MIDIUniqueID
    let name: String

    init(uniqueID: MIDIUniqueID, name: String) {
        self.uniqueID = uniqueID
        self.name = name
    }
}

private struct ConnectedSource {
    let endpoint: MIDIEndpointRef
    let contextPointer: UnsafeMutableRawPointer
}

@MainActor
final class MIDIMonitor: ObservableObject {
    @Published var channelStates: [ChannelState] = (0..<16).map(ChannelState.placeholder)
    @Published var destinations: [MIDIEndpointOption] = []
    @Published var selectedDestinationID: MIDIUniqueID?
    @Published var footerStatus = "Starting CoreMIDI monitor..."
    @Published var lastSystemMessage = "System messages will appear here."
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
    private var connectedSources: [MIDIUniqueID: ConnectedSource] = [:]
    private var sourceNameByID: [MIDIUniqueID: String] = [:]
    private var destinationByID: [MIDIUniqueID: MIDIEndpointRef] = [:]
    private var parser = MIDIByteStreamParser()

    init() {
        setupMIDI()
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
            return destinations.first?.name ?? "No MIDI destination"
        }
        return destination.name
    }

    var sourceSummaryText: String {
        if sourceNameByID.isEmpty {
            return "No CoreMIDI sources found."
        }
        return sourceNameByID.values.sorted().joined(separator: ", ")
    }

    func refreshEndpoints() {
        reconnectSources()
        refreshDestinations()
    }

    func sendAllNotesOff() {
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
            let sourceName = sourceConnectionContext.map {
                Unmanaged<MIDIInputSourceContext>.fromOpaque($0).takeUnretainedValue().name
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                for packetBytes in bytesByPacket {
                    self.handleIncomingBytes(packetBytes, sourceName: sourceName)
                    self.forward(bytes: packetBytes)
                }
            }
        }

        MIDIOutputPortCreate(client, "MIDImunger Output" as CFString, &outputPort)
    }

    private func reconnectSources() {
        disconnectAllSources()
        sourceNameByID.removeAll()

        let sourceCount = MIDIGetNumberOfSources()
        for index in 0..<sourceCount {
            let source = MIDIGetSource(index)
            guard source != 0 else { continue }
            let uniqueID = propertyInt32(kMIDIPropertyUniqueID, of: source)
            let name = endpointDisplayName(source)
            sourceNameByID[uniqueID] = name
            let context = MIDIInputSourceContext(uniqueID: uniqueID, name: name)
            let contextPointer = Unmanaged.passRetained(context).toOpaque()
            let status = MIDIPortConnectSource(inputPort, source, contextPointer)
            guard status == noErr else {
                Unmanaged<MIDIInputSourceContext>.fromOpaque(contextPointer).release()
                continue
            }
            connectedSources[uniqueID] = ConnectedSource(endpoint: source, contextPointer: contextPointer)
        }

        footerStatus = sourceCount == 0
            ? "No MIDI input sources are available."
            : "Listening to \(sourceCount) MIDI source\(sourceCount == 1 ? "" : "s")."
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

        let destinationCount = MIDIGetNumberOfDestinations()
        for index in 0..<destinationCount {
            let destination = MIDIGetDestination(index)
            guard destination != 0 else { continue }
            let uniqueID = propertyInt32(kMIDIPropertyUniqueID, of: destination)
            let name = endpointDisplayName(destination)
            destinationByID[uniqueID] = destination
            destinations.append(MIDIEndpointOption(uniqueID: uniqueID, name: name))
        }

        if let selectedDestinationID, destinationByID[selectedDestinationID] != nil {
            return
        }

        selectedDestinationID = destinations.first?.uniqueID
    }

    private func handleIncomingBytes(_ bytes: [UInt8], sourceName: String?) {
        for message in parser.consume(bytes: bytes, sourceName: sourceName) {
            apply(message: message)
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

    private func forward(bytes: [UInt8]) {
        send(bytes: bytes)
    }

    private func send(bytes: [UInt8]) {
        guard let selectedDestinationID,
              let destination = destinationByID[selectedDestinationID] else {
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

    private func ledText(for value: Int?, digits: Int = 3) -> String {
        guard let value else { return String(repeating: "-", count: digits) }
        let upperBound = Int(pow(10.0, Double(digits))) - 1
        let clamped = min(max(value, 0), upperBound)
        return String(format: "%0\(digits)d", clamped)
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
                lastPlayedVelocity: nil
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
                lastPlayedVelocity: velocity == 0 ? nil : velocity
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
                lastPlayedVelocity: nil
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
                lastPlayedVelocity: nil
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
                lastPlayedVelocity: nil
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
                lastPlayedVelocity: nil
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
                lastPlayedVelocity: nil
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
                lastPlayedVelocity: nil
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
            lastPlayedVelocity: nil
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
