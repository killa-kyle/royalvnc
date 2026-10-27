#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Clipboard callbacks run on the connection receive task. Dispatch UI changes
/// to the main actor. The delegate never accesses a platform pasteboard.
public protocol VNCClipboardDelegate: AnyObject {
    func connection(_ connection: VNCConnection, didReceiveClipboardText text: String)
}

public enum VNCClipboardError: Error {
    case notConnected
    case unsupportedCharacters
    case tooLarge
}

public extension VNCConnection {
    /// Standard RFB clipboard text is ISO-8859-1. Reject unsupported text rather
    /// than silently replacing it with an empty clipboard. This manual API works
    /// with automatic redirection disabled; callers own consent/observe policy.
    func sendClipboardText(_ text: String) throws {
        guard connectionState.status == .connected else { throw VNCClipboardError.notConnected }
        try Self.validateClipboardText(text)
        enqueueClientCutTextMessage(text)
    }

    static func validateClipboardText(_ text: String) throws {
        guard let data = text.data(using: .isoLatin1, allowLossyConversion: false) else {
            throw VNCClipboardError.unsupportedCharacters
        }
        guard data.count <= 1_048_576 else { throw VNCClipboardError.tooLarge }
    }
}
