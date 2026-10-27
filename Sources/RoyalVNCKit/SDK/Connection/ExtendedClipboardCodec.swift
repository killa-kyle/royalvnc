import Foundation
@_implementationOnly import Z

/// Original implementation of the public RFB Extended Clipboard specification.
/// https://github.com/rfbproto/rfbproto/blob/master/rfbproto.rst
struct ExtendedClipboardPacket {
    static let text: UInt32 = 1
    static let caps: UInt32 = 1 << 24
    static let request: UInt32 = 1 << 25
    static let peek: UInt32 = 1 << 26
    static let notify: UInt32 = 1 << 27
    static let provide: UInt32 = 1 << 28
    static let actions = caps | request | peek | notify | provide
    static let limit = 1_048_576
    let action: UInt32
    let formats: UInt32
    var sizes: [UInt32: UInt32] = [:]
    var content: [UInt32: Data] = [:]

    static func decode(_ payload: Data) throws -> Self {
        guard payload.count >= 4, payload.count <= limit else { throw invalid }
        var cursor = 0
        let flags = try readWord(payload, cursor: &cursor)
        let action = flags & 0xff000000
        let formats = flags & 0xffff
        guard flags & 0x00ff0000 == 0 else { throw invalid }
        var packet = Self(action: action, formats: formats)
        if action & caps != 0 {
            guard action & ~actions == 0 else { throw invalid }
            for bit in 0..<16 where formats & (1 << bit) != 0 {
                packet.sizes[1 << bit] = try readWord(payload, cursor: &cursor)
            }
            guard cursor == payload.count else { throw invalid }
            return packet
        }
        guard [request, peek, notify, provide].contains(action) else { throw invalid }
        if action != provide {
            guard payload.count == 4, action != peek || formats == 0 else { throw invalid }
            return packet
        }
        let inflated = try inflate(Data(payload.dropFirst(4)))
        cursor = 0
        var total = 0
        for bit in 0..<16 where formats & (1 << bit) != 0 {
            let length = Int(try readWord(inflated, cursor: &cursor))
            guard length <= limit, cursor <= inflated.count, length <= inflated.count - cursor else { throw invalid }
            total += length
            guard total <= limit else { throw invalid }
            packet.content[1 << bit] = Data(inflated[cursor..<cursor + length])
            cursor += length
        }
        guard cursor == inflated.count else { throw invalid }
        return packet
    }

    func payload() throws -> Data {
        var payload = Data()
        payload.append(action | formats, bigEndian: true)
        if action & Self.caps != 0 {
            for bit in 0..<16 where formats & (1 << bit) != 0 {
                payload.append(sizes[1 << bit] ?? 0, bigEndian: true)
            }
        } else if action == Self.provide {
            var raw = Data()
            var total = 0
            for bit in 0..<16 where formats & (1 << bit) != 0 {
                guard let bytes = content[1 << bit], bytes.count <= Self.limit else { throw Self.invalid }
                total += bytes.count
                guard total <= Self.limit else { throw Self.invalid }
                raw.append(UInt32(bytes.count), bigEndian: true)
                raw.append(bytes)
            }
            payload.append(try Self.deflate(raw))
        }
        guard payload.count <= Self.limit else { throw Self.invalid }
        return payload
    }

    static func textData(_ text: String) throws -> Data {
        guard !text.contains("\0") else { throw VNCClipboardError.unsupportedCharacters }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "\r\n")
        var data = Data(normalized.utf8)
        guard data.count < limit else { throw VNCClipboardError.tooLarge }
        data.append(0)
        return data
    }

    func textValue() throws -> String? {
        guard formats & Self.text != 0, let data = content[Self.text] else { return nil }
        guard data.last == 0, let value = String(data: data.dropLast(), encoding: .utf8),
              !value.contains("\0") else { throw Self.invalid }
        return value.replacingOccurrences(of: "\r\n", with: "\n")
    }

    static var invalid: Error { VNCError.protocol(.invalidData) }
    private static func readWord(_ bytes: Data, cursor: inout Int) throws -> UInt32 {
        guard cursor <= bytes.count, bytes.count - cursor >= 4 else { throw invalid }
        let value = bytes[cursor..<cursor + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        cursor += 4
        return value
    }

    // Fixed destination bounds allocation and inflation, including length fields.
    // uncompress2 also reports consumed input: reject trailing/concatenated streams.
    static func inflate(_ input: Data) throws -> Data {
        var output = Data(count: limit + 16 * 4)
        var outputLength = uLongf(output.count)
        var inputLength = uLong(input.count)
        let status = output.withUnsafeMutableBytes { destination in
            input.withUnsafeBytes { source in
                uncompress2(destination.bindMemory(to: Bytef.self).baseAddress!, &outputLength,
                            source.bindMemory(to: Bytef.self).baseAddress, &inputLength)
            }
        }
        guard status == Z_OK, inputLength == input.count else { throw invalid }
        output.count = Int(outputLength)
        return output
    }
    static func deflate(_ input: Data) throws -> Data {
        var output = Data(count: Int(compressBound(uLong(input.count))))
        var length = uLongf(output.count)
        let status = output.withUnsafeMutableBytes { destination in
            input.withUnsafeBytes { source in
                compress2(destination.bindMemory(to: Bytef.self).baseAddress!, &length,
                          source.bindMemory(to: Bytef.self).baseAddress, uLong(input.count), Z_DEFAULT_COMPRESSION)
            }
        }
        guard status == Z_OK else { throw invalid }
        output.count = Int(length)
        return output
    }
}

struct ExtendedClipboardMessage: VNCSendableMessage {
    let payload: Data
    let messageType: UInt8 = 6
    var data: Data {
        var bytes = Data([6, 0, 0, 0])
        bytes.append(UInt32(bitPattern: -Int32(payload.count)), bigEndian: true)
        bytes.append(payload)
        return bytes
    }
    func send(connection: NetworkConnectionWriting) async throws {
        try await connection.write(data: data)
    }
}
