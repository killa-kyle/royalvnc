#if os(macOS)
import Foundation
import XCTest
import RoyalVNCKit

final class ExtendedClipboardWireTests: XCTestCase, @unchecked Sendable {
    func testNegotiatedUnicodeRoundTripOnLoopback() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let ready = directory.appendingPathComponent("ready.json")
        let received = directory.appendingPathComponent("received.json")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [Bundle.module.url(forResource: "extended_fixture", withExtension: "py")!.path,
                             ready.path, received.path]
        try process.run()
        defer { if process.isRunning { process.terminate(); process.waitUntilExit() } }
        try await waitUntil { (try? Data(contentsOf: ready)).flatMap { try? JSONSerialization.jsonObject(with: $0) } != nil }
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: ready)) as! [String: Int]
        let connection = VNCConnection(settings: .init(isDebugLoggingEnabled: false, hostname: "127.0.0.1",
            port: UInt16(object["port"]!), isShared: true, isScalingEnabled: false, useDisplayLink: false,
            inputMode: .none, isClipboardRedirectionEnabled: false, colorDepth: .depth24Bit, frameEncodings: .default),
            logger: VNCPrintLogger())
        let delegate = WireDelegate()
        connection.delegate = delegate
        connection.clipboardDelegate = delegate
        connection.connect()
        defer { connection.disconnect() }
        try await waitUntil { delegate.text == "遠隔\n🙂" }
        XCTAssertTrue(connection.supportsUTF8Clipboard)
        try connection.sendClipboardText("日本語\nمرحبا🙂")
        try await waitUntil { (try? Data(contentsOf: received)).flatMap { try? JSONSerialization.jsonObject(with: $0) } != nil }
        let result = try JSONSerialization.jsonObject(with: Data(contentsOf: received)) as! [String: String]
        XCTAssertEqual(result["text"], "日本語\r\nمرحبا🙂")
        connection.clearLocalClipboardText()
    }
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<250 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for extended clipboard wire fixture")
        throw NSError(domain: "ExtendedClipboardTest", code: 1)
    }
}
private final class WireDelegate: VNCConnectionDelegate, VNCClipboardDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    var text: String? { lock.lock(); defer { lock.unlock() }; return value }
    func connection(_ connection: VNCConnection, didReceiveClipboardText text: String) {
        lock.lock(); value = text; lock.unlock()
    }
    func connection(_ connection: VNCConnection, stateDidChange connectionState: VNCConnection.ConnectionState) {}
    func connection(_ connection: VNCConnection, credentialFor authenticationType: VNCAuthenticationType,
                    completion: @escaping ((any VNCCredential)?) -> Void) { completion(nil) }
    func connection(_ connection: VNCConnection, didCreateFramebuffer framebuffer: VNCFramebuffer) {}
    func connection(_ connection: VNCConnection, didResizeFramebuffer framebuffer: VNCFramebuffer) {}
    func connection(_ connection: VNCConnection, didUpdateCursor cursor: VNCCursor) {}
    func connection(_ connection: VNCConnection, didUpdateFramebuffer framebuffer: VNCFramebuffer,
                    x: UInt16, y: UInt16, width: UInt16, height: UInt16) {}
}
#endif
