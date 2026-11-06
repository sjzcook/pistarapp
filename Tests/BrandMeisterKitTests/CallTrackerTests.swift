import XCTest
@testable import BrandMeisterKit

final class CallTrackerTests: XCTestCase {

    private func packet(kind: DMRDataPacket.FrameKind,
                        source: UInt32 = 4_601_234,
                        destination: UInt32 = 91,
                        slot: Int = 2,
                        sequence: UInt8 = 0) -> DMRDataPacket {
        DMRDataPacket(sequence: sequence,
                      sourceID: source,
                      destinationID: destination,
                      repeaterID: 4_601_234,
                      slot: slot,
                      isPrivate: false,
                      kind: kind,
                      streamID: 0x1234,
                      payload: Array(repeating: 0, count: 33))
    }

    func testCallLifecycleFromHeaderToTerminator() {
        let tracker = CallTracker()
        var started: [CallSession] = []
        var ended: [CallSummary] = []
        tracker.onCallStarted = { started.append($0) }
        tracker.onCallEnded = { ended.append($0) }

        let t0 = Date()
        tracker.process(packet(kind: .data(DMRDataType.voiceLCHeader.rawValue)), now: t0)
        tracker.process(packet(kind: .voiceSync), now: t0.addingTimeInterval(0.06))
        tracker.process(packet(kind: .voiceFrame(1)), now: t0.addingTimeInterval(0.12))
        tracker.process(packet(kind: .data(DMRDataType.terminatorWithLC.rawValue)), now: t0.addingTimeInterval(0.18))

        XCTAssertEqual(started.count, 1)
        XCTAssertEqual(ended.count, 1)
        XCTAssertEqual(ended.first?.frameCount, 2)
        XCTAssertEqual(ended.first?.destinationID, 91)
        XCTAssertTrue(tracker.activeCalls.isEmpty)
    }

    func testCallWithoutHeaderStartsOnFirstVoiceFrame() {
        let tracker = CallTracker()
        var started = 0
        tracker.onCallStarted = { _ in started += 1 }

        let t0 = Date()
        tracker.process(packet(kind: .voiceFrame(0)), now: t0)
        XCTAssertEqual(started, 1)
        XCTAssertEqual(tracker.activeCalls.count, 1)
        XCTAssertEqual(tracker.activeCalls.first?.frameCount, 1)
    }

    func testSilentCallExpires() {
        let tracker = CallTracker()
        tracker.callTimeout = 1.0
        var ended: [CallSummary] = []
        tracker.onCallEnded = { ended.append($0) }

        let t0 = Date()
        tracker.process(packet(kind: .voiceFrame(0)), now: t0)
        tracker.process(packet(kind: .voiceFrame(1)), now: t0.addingTimeInterval(0.06))
        tracker.expireStale(now: t0.addingTimeInterval(2.0))

        XCTAssertEqual(ended.count, 1)
        XCTAssertTrue(tracker.activeCalls.isEmpty)
    }

    func testTwoSlotsAreTrackedIndependently() {
        let tracker = CallTracker()
        let t0 = Date()
        tracker.process(packet(kind: .voiceFrame(0), source: 111, destination: 91, slot: 1), now: t0)
        tracker.process(packet(kind: .voiceFrame(0), source: 222, destination: 91, slot: 2), now: t0)

        XCTAssertEqual(tracker.activeCalls.count, 2)
        XCTAssertEqual(Set(tracker.activeCalls.map(\.slot)), [1, 2])
    }
}
