import AVFoundation
import Foundation

public enum AudioError: Error {
    case formatUnavailable
}

/// 8kHz 单声道 PCM 播放。AVAudioEngine 会自动重采样到设备输出率。
public final class PCMAudioPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    public private(set) var isRunning = false

    public init() {}

    public func start(sampleRate: Double = 8000) throws {
        guard !isRunning else { return }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw AudioError.formatUnavailable
        }
        self.format = format
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try engine.start()
        player.play()
        isRunning = true
    }

    public func play(_ samples: [Int16]) {
        guard isRunning, let format, !samples.isEmpty else { return }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channel = buffer.floatChannelData?[0] {
            for index in 0..<samples.count {
                channel[index] = Float(samples[index]) / 32768.0
            }
        }
        player.scheduleBuffer(buffer, completionHandler: nil)
    }

    public func stop() {
        player.stop()
        engine.stop()
        isRunning = false
    }
}
