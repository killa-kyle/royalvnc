import Foundation
import XCTest
@testable import RoyalVNCKit

final class ExtendedClipboardTests: XCTestCase {
    typealias Packet = ExtendedClipboardPacket
    private func caps(size: UInt32 = 0) -> Packet {
        Packet(action: Packet.actions, formats: Packet.text, sizes: [Packet.text: size])
    }
    func testNegotiationNotificationRequestAndRevocation() throws {
        let state = ExtendedClipboardState()
        XCTAssertFalse(state.supportsUTF8)
        XCTAssertNil(try state.send("漢字")) // caller uses standard Latin1 fallback, which rejects it
        let reply = try state.receive(try Packet.decode(caps().payload()))
        XCTAssertTrue(state.supportsUTF8)
        XCTAssertEqual(reply.responses.first?.sizes[Packet.text], 0)
        XCTAssertEqual(try state.send("漢字\n🙂")?.action, Packet.notify)
        let requested = try state.receive(Packet(action: Packet.request, formats: Packet.text))
        XCTAssertEqual(requested.responses.first?.action, Packet.provide)
        let wire = try XCTUnwrap(requested.responses.first).payload()
        let decoded = try Packet.decode(wire)
        XCTAssertEqual(try decoded.textValue(), "漢字\n🙂")
        XCTAssertEqual(decoded.content[Packet.text], Data("漢字\r\n🙂\0".utf8))
        state.clearLocal()
        XCTAssertTrue(try state.receive(Packet(action: Packet.request, formats: Packet.text)).responses.isEmpty)
        XCTAssertEqual(try state.receive(Packet(action: Packet.peek, formats: 0)).responses.first?.formats, 0)
        state.reset()
        XCTAssertFalse(state.supportsUTF8)
        XCTAssertTrue(try state.receive(Packet(action: Packet.notify, formats: Packet.text)).responses.isEmpty)
    }
    func testProvideWithinNegotiatedLimitAndRemoteNotify() throws {
        let state = ExtendedClipboardState()
        _ = try state.receive(caps(size: 100))
        XCTAssertEqual(try state.send("שלום")?.action, Packet.provide)
        let notify = try state.receive(Packet(action: Packet.notify, formats: Packet.text))
        XCTAssertEqual(notify.responses.first?.action, Packet.request)
        let packet = Packet(action: Packet.provide, formats: Packet.text,
                            content: [Packet.text: try Packet.textData("日本語")])
        let result = try state.receive(try Packet.decode(packet.payload()))
        XCTAssertEqual(result.text, "日本語")
    }
    func testCapabilitySizesAndWireEnvelope() throws {
        let packet = Packet(action: Packet.actions, formats: 5, sizes: [1: 1234, 4: 5678])
        let decoded = try Packet.decode(packet.payload())
        XCTAssertEqual(decoded.sizes[1], 1234)
        XCTAssertEqual(decoded.sizes[4], 5678)
        let message = ExtendedClipboardMessage(payload: try packet.payload()).data
        XCTAssertEqual(Array(message.prefix(4)), [6, 0, 0, 0])
        XCTAssertEqual(Array(message[4..<8]), [255, 255, 255, 244]) // signed -12
    }
    func testMalformedTruncatedAndTrailingDataRejected() throws {
        for bytes: [UInt8] in [[], [0], [0,0,0], [0,0,0,1], [6,0,0,1],
                              [1,0,0,1], [2,0,0,1,9], [4,0,0,1], [16,0,0,1]] {
            XCTAssertThrowsError(try Packet.decode(Data(bytes)), "Accepted \(bytes)")
        }
        let valid = try Packet(action: Packet.provide, formats: 1,
                               content: [1: Data("hello\0".utf8)]).payload()
        for count in 4..<valid.count { XCTAssertThrowsError(try Packet.decode(Data(valid.prefix(count)))) }
        XCTAssertThrowsError(try Packet.decode(valid + Data([0])))
        XCTAssertThrowsError(try Packet.decode(valid + valid.dropFirst(4)))
        XCTAssertThrowsError(try Packet.textData("bad\0text"))
        let invalidUTF8 = Packet(action: Packet.provide, formats: 1, content: [1: Data([255, 0])])
        XCTAssertThrowsError(try Packet.decode(invalidUTF8.payload()).textValue())
        let noTerminator = Packet(action: Packet.provide, formats: 1, content: [1: Data([65])])
        XCTAssertThrowsError(try Packet.decode(noTerminator.payload()).textValue())
    }
    func testInflationBombAndHugeAdvertisedFormatLengthRejected() throws {
        // This zlib stream is tiny on the wire but exceeds the fixed inflation budget.
        let compressed = try Packet.deflate(Data(repeating: 65, count: Packet.limit + 65))
        var bomb = Data([16, 0, 0, 1]); bomb.append(compressed)
        XCTAssertThrowsError(try Packet.decode(bomb))
        var hugeLength = Data([16, 0, 0, 1])
        hugeLength.append(try Packet.deflate(Data([255, 255, 255, 255])))
        XCTAssertThrowsError(try Packet.decode(hugeLength))
        var inconsistent = Data([16, 0, 0, 1])
        inconsistent.append(try Packet.deflate(Data([0, 0, 0, 5, 65, 0])))
        XCTAssertThrowsError(try Packet.decode(inconsistent))
        XCTAssertThrowsError(try Packet.textData(String(repeating: "a", count: Packet.limit)))
    }
}
