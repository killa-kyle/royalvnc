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
    /// Standard servers use ISO-8859-1; servers negotiating Extended Clipboard
    /// use UTF-8 text. Reject unsupported text rather than sending empty data.
    /// This manual API works
    /// with automatic redirection disabled; callers own consent/observe policy.
    func sendClipboardText(_ text: String) throws {
        guard connectionState.status == .connected else { throw VNCClipboardError.notConnected }
        if let packet = try extendedClipboardState.send(text) {
            enqueueClientToServerMessage(ExtendedClipboardMessage(payload: try packet.payload()))
        } else {
            try Self.validateClipboardText(text)
            enqueueClientCutTextMessage(text)
        }
    }

    /// Revoke previously supplied data before entering observe/background modes.
    /// A later server request will no longer receive that cached clipboard.
    func clearLocalClipboardText() { extendedClipboardState.clearLocal() }

    var supportsUTF8Clipboard: Bool { extendedClipboardState.supportsUTF8 }

    static func validateClipboardText(_ text: String) throws {
        guard let data = text.data(using: .isoLatin1, allowLossyConversion: false) else {
            throw VNCClipboardError.unsupportedCharacters
        }
        guard data.count <= 1_048_576 else { throw VNCClipboardError.tooLarge }
    }
}
