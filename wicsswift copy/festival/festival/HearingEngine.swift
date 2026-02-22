import AVFoundation
import Foundation
import Observation

@Observable
@MainActor
final class HearingEngine {
    var currentDB: Double = 0
    var peakDB: Double = 0
    var riskBand: RiskBand = .safe
    var safeTimeLeftMinutes: Double = 480
    var trend: Trend = .steady
    var suggestion: String = "Sound levels are stable."
    var isMonitoring: Bool = false
    private(set) var isEventModeEnabled: Bool = false

    private var engine: AVAudioEngine?
    private var smoothedRMS: Float = 0
    private var smoothingFactor: Float = 0.3
    private var exposureDose: Double = 0
    private var lastUpdateTime: Date = .now
    private var previousDB: Double = 0
    private var recentPCM: [Float] = []
    private let maxBufferedSeconds: Double = 12
    private(set) var sampleRate: Double = 44_100
    var calibrationOffset: Double = UserDefaults.standard.object(forKey: "hearingCalibrationOffset") as? Double ?? 100 {
        didSet {
            UserDefaults.standard.set(calibrationOffset, forKey: Self.calibrationOffsetKey)
        }
    }

    private static let calibrationOffsetKey = "hearingCalibrationOffset"

    var hearingData: HearingData {
        HearingData(
            dbLevel: currentDB,
            riskBand: riskBand,
            safeTimeLeftMinutes: safeTimeLeftMinutes,
            peakDB: peakDB,
            trend: trend,
            suggestion: suggestion,
            timestamp: .now
        )
    }

    func startMonitoring() {
        guard !isMonitoring else { return }

        do {
            let session = AVAudioSession.sharedInstance()

            // FIX: Use .playAndRecord with options to ensure we get phone mic, not Bluetooth headset
            // .defaultToSpeaker - routes audio to speaker
            // .allowBluetoothA2DP - allows Bluetooth speakers but NOT headset mic
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try session.setActive(true)

            // FIX: Force built-in microphone (not AirPods or Bluetooth headset)
            if let inputs = session.availableInputs {
                for input in inputs {
                    if input.portType == .builtInMic {
                        try session.setPreferredInput(input)
                        break
                    }
                }
            }

            // FIX: Set preferred input gain to maximum for song detection
            // iOS input gain range is typically 0.0 to 1.0
            if session.isInputGainSettable {
                try session.setInputGain(1.0)
            }

            let audioEngine = AVAudioEngine()
            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            sampleRate = format.sampleRate

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.processBuffer(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            engine = audioEngine
            isMonitoring = true
            lastUpdateTime = .now
        } catch {
            print("HearingEngine start error: \(error)")
            isMonitoring = false
        }
    }

    func stopMonitoring() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isMonitoring = false
        recentPCM.removeAll()
        resetExposure()
    }

    func resetExposure() {
        exposureDose = 0
        safeTimeLeftMinutes = 480
        peakDB = 0
    }

    func resetCalibration() {
        calibrationOffset = 100
    }

    func setEventMode(_ enabled: Bool) {
        isEventModeEnabled = enabled
        smoothingFactor = enabled ? 0.5 : 0.3
    }

    private nonisolated func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }

        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frames))
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frames))

        Task { @MainActor [weak self] in
            self?.appendRecentSamples(samples)
            self?.updateWithRMS(rms)
        }
    }

    private func updateWithRMS(_ rms: Float) {
        smoothedRMS = smoothingFactor * rms + (1 - smoothingFactor) * smoothedRMS

        let dbValue: Double
        if smoothedRMS > 0 {
            dbValue = max(0, min(140, Double(20 * log10(smoothedRMS)) + calibrationOffset))
        } else {
            dbValue = 0
        }

        currentDB = dbValue
        if dbValue > peakDB {
            peakDB = dbValue
        }

        trend = computeTrend(newDB: dbValue)
        riskBand = computeRiskBand(db: dbValue)
        updateExposure(db: dbValue)
        suggestion = computeSuggestion(db: dbValue, risk: riskBand, trend: trend)
        previousDB = dbValue
    }

    private func computeRiskBand(db: Double) -> RiskBand {
        let cautionStart = isEventModeEnabled ? 68.0 : 70.0
        let warningStart = isEventModeEnabled ? 78.0 : 80.0
        let dangerStart = isEventModeEnabled ? 83.0 : 85.0
        let criticalStart = isEventModeEnabled ? 92.0 : 95.0

        switch db {
        case ..<cautionStart: return .safe
        case cautionStart..<warningStart: return .caution
        case warningStart..<dangerStart: return .warning
        case dangerStart..<criticalStart: return .danger
        default: return .critical
        }
    }

    private func computeTrend(newDB: Double) -> Trend {
        let delta = newDB - previousDB
        if delta > 1.5 { return .rising }
        if delta < -1.5 { return .falling }
        return .steady
    }

    private func computeSuggestion(db: Double, risk: RiskBand, trend: Trend) -> String {
        if risk == .danger || risk == .critical {
            return "Safer side: left"
        }
        let risingThreshold = isEventModeEnabled ? 72.0 : 75.0
        if trend == .rising && db > risingThreshold {
            return "Volume climbing — consider stepping back"
        }
        return "Sound levels are stable"
    }

    func latestAudioBase64Wav(seconds: Double = 4) -> String? {
        guard sampleRate > 0 else { return nil }
        let requested = max(1.0, min(maxBufferedSeconds, seconds))
        let sampleCount = Int(requested * sampleRate)
        guard !recentPCM.isEmpty, sampleCount > 0 else { return nil }

        let clipped = recentPCM.suffix(sampleCount)
        guard !clipped.isEmpty else { return nil }

        var pcm16: [Int16] = []
        pcm16.reserveCapacity(clipped.count)
        for sample in clipped {
            let normalized = max(-1.0, min(1.0, sample))
            pcm16.append(Int16(normalized * Float(Int16.max)))
        }

        let wavData = buildWavData(pcm16: pcm16, sampleRate: Int(sampleRate))
        return wavData.base64EncodedString()
    }

    /// Get raw PCM samples for ShazamKit (or other local processing)
    func getLatestPCMSamples(seconds: Double = 5) -> [Float]? {
        guard sampleRate > 0 else { return nil }
        let requested = max(1.0, min(maxBufferedSeconds, seconds))
        let sampleCount = Int(requested * sampleRate)
        guard !recentPCM.isEmpty, sampleCount > 0 else { return nil }

        let clipped = Array(recentPCM.suffix(sampleCount))
        guard !clipped.isEmpty else { return nil }
        return clipped
    }

    private func appendRecentSamples(_ samples: [Float]) {
        recentPCM.append(contentsOf: samples)
        let maxSamples = Int(maxBufferedSeconds * sampleRate)
        if recentPCM.count > maxSamples {
            recentPCM.removeFirst(recentPCM.count - maxSamples)
        }
    }

    private func buildWavData(pcm16: [Int16], sampleRate: Int) -> Data {
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate: UInt32 = UInt32(sampleRate) * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign: UInt16 = channels * (bitsPerSample / 8)
        let dataSize: UInt32 = UInt32(pcm16.count * MemoryLayout<Int16>.size)
        let riffChunkSize: UInt32 = 36 + dataSize

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(contentsOf: riffChunkSize.littleEndianBytes)
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.append(contentsOf: UInt32(16).littleEndianBytes)
        data.append(contentsOf: UInt16(1).littleEndianBytes)
        data.append(contentsOf: channels.littleEndianBytes)
        data.append(contentsOf: UInt32(sampleRate).littleEndianBytes)
        data.append(contentsOf: byteRate.littleEndianBytes)
        data.append(contentsOf: blockAlign.littleEndianBytes)
        data.append(contentsOf: bitsPerSample.littleEndianBytes)
        data.append("data".data(using: .ascii)!)
        data.append(contentsOf: dataSize.littleEndianBytes)

        for sample in pcm16 {
            data.append(contentsOf: sample.littleEndianBytes)
        }

        return data
    }

    private func updateExposure(db: Double) {
        let now = Date.now
        let elapsed = now.timeIntervalSince(lastUpdateTime)
        lastUpdateTime = now

        let exposureStartDB = isEventModeEnabled ? 78.0 : 80.0
        guard db >= exposureStartDB, elapsed > 0, elapsed < 5 else { return }

        let allowedHours = 8.0 / pow(2.0, (db - 85.0) / 3.0)
        let allowedSeconds = allowedHours * 3600
        let doseIncrement = elapsed / allowedSeconds

        exposureDose += doseIncrement

        let remaining = max(0, (1.0 - exposureDose) * allowedHours * 60)
        safeTimeLeftMinutes = remaining
    }
}

private extension FixedWidthInteger {
    var littleEndianBytes: [UInt8] {
        withUnsafeBytes(of: self.littleEndian) { Array($0) }
    }
}
