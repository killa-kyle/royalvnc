import Foundation

/// Serializes UI sends and receiver-side negotiation, without accessing pasteboards.
final class ExtendedClipboardState {
    private let lock = NSLock()
    private var peerFlags: UInt32 = 0
    private var peerTextLimit: UInt32 = 0
    private var localText: Data?
    typealias Packet = ExtendedClipboardPacket

    var supportsUTF8: Bool {
        lock.lock(); defer { lock.unlock() }
        return peerFlags & Packet.text != 0 && peerFlags & Packet.provide != 0
    }
    func clearLocal() {
        lock.lock(); defer { lock.unlock() }
        localText = nil
    }
    func reset() {
        lock.lock(); defer { lock.unlock() }
        peerFlags = 0
        peerTextLimit = 0
        localText = nil
    }
    func send(_ text: String) throws -> Packet? {
        lock.lock(); defer { lock.unlock() }
        guard peerFlags & Packet.text != 0, peerFlags & Packet.provide != 0 else { return nil }
        let bytes = try Packet.textData(text)
        if bytes.count <= peerTextLimit {
            localText = bytes
            return Packet(action: Packet.provide, formats: Packet.text, content: [Packet.text: bytes])
        }
        guard peerFlags & Packet.notify != 0 else { throw VNCClipboardError.unsupportedCharacters }
        localText = bytes
        return Packet(action: Packet.notify, formats: Packet.text)
    }
    func receive(_ packet: Packet) throws -> (responses: [Packet], text: String?) {
        lock.lock(); defer { lock.unlock() }
        if packet.action & Packet.caps != 0 {
            peerFlags = packet.action | packet.formats
            peerTextLimit = packet.sizes[Packet.text] ?? 0
            return ([Packet(action: Packet.actions, formats: Packet.text, sizes: [Packet.text: 0])], nil)
        }
        // Extension payloads must never activate negotiation themselves.
        guard peerFlags != 0 else { return ([], nil) }
        switch packet.action {
        case Packet.request:
            guard packet.formats & Packet.text != 0, let bytes = localText,
                  peerFlags & Packet.provide != 0 else { return ([], nil) }
            return ([Packet(action: Packet.provide, formats: Packet.text, content: [Packet.text: bytes])], nil)
        case Packet.peek:
            guard peerFlags & Packet.notify != 0 else { return ([], nil) }
            return ([Packet(action: Packet.notify, formats: localText == nil ? 0 : Packet.text)], nil)
        case Packet.notify:
            localText = nil
            guard packet.formats & Packet.text != 0, peerFlags & Packet.request != 0 else { return ([], nil) }
            return ([Packet(action: Packet.request, formats: Packet.text)], nil)
        case Packet.provide:
            localText = nil
            return ([], try packet.textValue())
        default:
            throw Packet.invalid
        }
    }
}
