import Foundation

extension VNCProtocol {
    struct ServerCutText: VNCReceivableMessage {
        static let messageType: UInt8 = 3
        static let stringEncoding: String.Encoding = .isoLatin1
        let messageType: UInt8
        let text: String
        let extended: ExtendedClipboardPacket?

        static func receive(connection: NetworkConnectionReading, logger: VNCLogger) async throws -> Self {
            try await connection.readPadding(length: 3)
            let raw = try await connection.readUInt32()
            let length = Int(Int32(bitPattern: raw))
            guard length != Int(Int32.min), abs(length) <= ExtendedClipboardPacket.limit else {
                throw VNCError.protocol(.invalidData)
            }
            if length >= 0 {
                let text = try await connection.readString(encoding: stringEncoding, length: length)
                return .init(messageType: messageType, text: text, extended: nil)
            }
            let payload = try await connection.read(length: -length)
            return .init(messageType: messageType, text: "", extended: try ExtendedClipboardPacket.decode(payload))
        }
    }
}
