import XCTest
@testable import BrandMeisterKit

final class ProtocolTests: XCTestCase {

    private func makeDMRD(sequence: UInt8,
                          source: UInt32,
                          destination: UInt32,
                          flags: UInt8,
                          payload: [UInt8] = Array(repeating: 0xAB, count: 33)) -> [UInt8] {
        var bytes = Array("DMRD".utf8)
        bytes.append(sequence)
        bytes += source.beUInt24Bytes
        bytes += destination.beUInt24Bytes
        bytes += UInt32(460123).bigEndianBytes
        bytes.append(flags)
        bytes += UInt32(0x0000BEEF).bigEndianBytes
        bytes += Array(payload.prefix(33))
        bytes.append(7)     // BER
        bytes.append(90)    // RSSI
        return bytes
    }

    func testDMRDParsingUsesPiStarOffsets() throws {
        // TS2 + 组呼 + 语音同步帧
        let raw = makeDMRD(sequence: 3, source: 4601234, destination: 91, flags: 0x90)
        let packet = try XCTUnwrap(DMRDataPacket(raw))

        XCTAssertEqual(packet.sequence, 3)
        XCTAssertEqual(packet.sourceID, 4_601_234)
        XCTAssertEqual(packet.destinationID, 91)
        XCTAssertEqual(packet.slot, 2)
        XCTAssertFalse(packet.isPrivate)
        XCTAssertEqual(packet.kind, .voiceSync)
        XCTAssertEqual(packet.payload.count, 33)
        XCTAssertEqual(packet.bitErrorRate, 7)
        XCTAssertEqual(packet.rssi, 90)
    }

    func testDMRDDecodesCallTypeAndFrameKind() throws {
        let header = try XCTUnwrap(DMRDataPacket(makeDMRD(sequence: 0, source: 1, destination: 2, flags: 0x62)))
        XCTAssertEqual(header.dataType, .voiceLCHeader)
        XCTAssertTrue(header.isPrivate)

        let voice = try XCTUnwrap(DMRDataPacket(makeDMRD(sequence: 1, source: 1, destination: 2, flags: 0x04)))
        XCTAssertEqual(voice.kind, .voiceFrame(4))
    }

    func testDMRDRoundTrip() throws {
        let raw = makeDMRD(sequence: 9, source: 4601234, destination: 91, flags: 0x90)
        let packet = try XCTUnwrap(DMRDataPacket(raw))
        XCTAssertEqual(packet.encoded(), raw)
    }

    func testFramerSplitsCoalescedPackets() {
        var stream: [UInt8] = []
        stream += Array("RPTACK".utf8) + UInt32(0x11223344).bigEndianBytes
        stream += Array("MSTPONG".utf8) + UInt32(4601234).bigEndianBytes
        stream += makeDMRD(sequence: 1, source: 4601234, destination: 91, flags: 0x90)

        var framer = HomebrewFramer()
        // 故意拆成两半喂进去，模拟 TCP 粘包/半包。
        framer.append(Array(stream[0..<7]))
        XCTAssertNil(framer.next())

        framer.append(Array(stream[7...]))

        guard case .repeaterAck(let value)? = framer.next() else {
            XCTFail("第一个报文应当是 RPTACK")
            return
        }
        XCTAssertEqual(value, 0x11223344)

        guard case .masterPong(let repeater)? = framer.next() else {
            XCTFail("第二个报文应当是 MSTPONG")
            return
        }
        XCTAssertEqual(repeater, 4_601_234)

        guard case .dmrData(let packet)? = framer.next() else {
            XCTFail("第三个报文应当是 DMRD")
            return
        }
        XCTAssertEqual(packet.destinationID, 91)
        XCTAssertNil(framer.next())
    }

    func testLoginPacketLayout() {
        var login = HBP.login
        login += UInt32(4_601_234).bigEndianBytes
        XCTAssertEqual(login.count, 8)
        XCTAssertEqual(String(decoding: login[0..<4], as: UTF8.self), "RPTL")
        XCTAssertEqual(login.beUInt32(4), 4_601_234)
    }

    func testAuthDigestIsSHA256OfSaltPlusPassword() {
        XCTAssertEqual(SHA256Auth.digest(Array("abc".utf8)).hexString.lowercased(),
                       "ba 78 16 bf 8f 01 cf ea 41 41 40 de 5d ae 22 23 b0 03 61 a3 96 17 7a 9c b4 10 ff 61 f2 00 15 ad")
        // 4 字节 salt(大端) + 密码
        let digest = SHA256Auth.digest(salt: 0x01020304, password: "pass")
        XCTAssertEqual(digest.count, 32)
        XCTAssertEqual(digest, SHA256Auth.digest([0x01, 0x02, 0x03, 0x04] + Array("pass".utf8)))
    }

    func testConfigPacketIs302Bytes() {
        let bytes = RepeaterInfo(callsign: "BG1ABC").encoded(repeaterID: 4_601_234)
        XCTAssertEqual(bytes.count, RepeaterInfo.packetLength)
        XCTAssertEqual(bytes.beUInt32(4), 4_601_234)
        XCTAssertEqual(String(decoding: bytes[8..<14], as: UTF8.self), "BG1ABC")
    }

    func testVoicePayloadSplitsIntoThreeAMBEBlocks() {
        let payload = Array(UInt8(0)...UInt8(32))
        let blocks = DMRVoicePayload.ambeBlocks(from: payload)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0].first, 6)
        XCTAssertEqual(blocks[2].last, 32)
    }
}
