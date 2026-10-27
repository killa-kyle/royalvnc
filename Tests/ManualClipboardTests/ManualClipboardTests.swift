import Foundation
import XCTest
@testable import RoyalVNCKit

final class ManualClipboardTests: XCTestCase {
    func testClientTextWireFormat() throws {
        try VNCConnection.validateClipboardText("Café\n")
        XCTAssertEqual(VNCProtocol.ClientCutText(text: "Café\n").data,
                       Data([6, 0, 0, 0, 0, 0, 0, 5, 67, 97, 102, 233, 10]))
    }
    func testUnsupportedTextAndOversizedTextAreRejected() {
        XCTAssertThrowsError(try VNCConnection.validateClipboardText("漢字"))
        XCTAssertThrowsError(try VNCConnection.validateClipboardText(String(repeating: "a", count: 1_048_577)))
        XCTAssertNoThrow(try VNCConnection.validateClipboardText(""))
    }
    func testServerTextWireFormat() async throws {
        let reader = Reader(Data([0, 0, 0, 0, 0, 0, 4, 67, 97, 102, 233]))
        let received = try await VNCProtocol.ServerCutText.receive(connection: reader, logger: VNCPrintLogger())
        XCTAssertEqual(received.text, "Café")
        XCTAssertTrue(reader.remaining.isEmpty)
    }
    func testUnadvertisedExtendedPayloadIsConsumedWithoutText() async throws {
        let reader = Reader(Data([0, 0, 0, 255, 255, 255, 252, 1, 2, 3, 4]))
        let received = try await VNCProtocol.ServerCutText.receive(connection: reader, logger: VNCPrintLogger())
        XCTAssertNotNil(received.extended)
        XCTAssertTrue(reader.remaining.isEmpty)
    }
    func testServerOversizedLengthIsRejectedBeforePayloadRead() async {
        let reader = Reader(Data([0, 0, 0, 0, 16, 0, 1]))
        do {
            _ = try await VNCProtocol.ServerCutText.receive(connection: reader, logger: VNCPrintLogger())
            XCTFail("Oversized clipboard accepted")
        } catch {}
        XCTAssertTrue(reader.remaining.isEmpty)
    }
}
private final class Reader: NetworkConnectionReading {
    var remaining: Data
    init(_ bytes: Data) { remaining = bytes }
    func read(minimumLength: Int, maximumLength: Int) async throws -> Data {
        guard remaining.count >= minimumLength else { throw VNCError.protocol(.invalidData) }
        let count = min(maximumLength, remaining.count)
        let data = Data(remaining.prefix(count))
        remaining.removeFirst(count)
        return data
    }
}
