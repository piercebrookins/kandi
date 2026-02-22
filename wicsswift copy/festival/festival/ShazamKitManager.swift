import ShazamKit
import AVFoundation
import Observation

/// Uses Apple's ShazamKit to identify songs locally on the device
/// No server needed, works offline, uses official Shazam database
@Observable
@MainActor
final class ShazamKitManager: NSObject, SHSessionDelegate {
    var isMatching = false
    var lastMatch: SHMatch?
    var lastError: Error?
    var statusMessage: String = "Ready to identify"

    private var session: SHSession?
    private var audioEngine: AVAudioEngine?
    private var signatureGenerator: SHSignatureGenerator?
    private var continuation: CheckedContinuation<SHMatch?, Never>?

    override init() {
        super.init()
        setupSession()
    }

    private func setupSession() {
        session = SHSession()
        session?.delegate = self
    }

    /// Identify from raw PCM samples using SignatureGenerator (better method)
    func identifyFromPCM(_ samples: [Float], sampleRate: Double) async -> (title: String, artist: String)? {
        print("🔵 ShazamKit: Starting identification with \(samples.count) samples at \(sampleRate)Hz")

        guard !samples.isEmpty else {
            statusMessage = "No audio samples"
            print("🔴 ShazamKit: No audio samples provided")
            return nil
        }

        // Check audio level first
        let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count))
        let db = 20 * log10(rms + 1e-10)
        print("🔵 ShazamKit: Audio level: \(db) dB (RMS: \(rms))")

        guard db > -50 else {
            statusMessage = "Audio too quiet"
            print("🔴 ShazamKit: Audio too quiet (\(db) dB), need > -50 dB")
            return nil
        }

        isMatching = true
        statusMessage = "Creating signature..."

        // Create signature generator with correct format
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        guard let audioFormat = format else {
            statusMessage = "Invalid audio format"
            print("🔴 ShazamKit: Could not create audio format")
            isMatching = false
            return nil
        }

        print("🟢 ShazamKit: Audio format - \(audioFormat.sampleRate)Hz, \(audioFormat.channelCount) channels")

        // Create signature generator
        let generator = SHSignatureGenerator()
        print("🟢 ShazamKit: Signature generator created")

        // Convert Float samples to AVAudioPCMBuffer
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: AVAudioFrameCount(samples.count)) else {
            statusMessage = "Failed to create audio buffer"
            print("🔴 ShazamKit: Failed to create AVAudioPCMBuffer")
            isMatching = false
            return nil
        }

        // Copy samples to buffer
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channelData = buffer.floatChannelData {
            for (index, sample) in samples.enumerated() {
                channelData[0][index] = sample
            }
        }

        print("🟢 ShazamKit: Audio buffer created with \(buffer.frameLength) frames")

        // Append buffer to signature generator
        do {
            try generator.append(buffer, at: nil)
            print("🟢 ShazamKit: Buffer appended to generator")
        } catch {
            statusMessage = "Failed to append audio: \(error.localizedDescription)"
            print("🔴 ShazamKit: Failed to append buffer: \(error)")
            isMatching = false
            return nil
        }

        // Generate signature
        let signature = generator.signature()
        print("🟢 ShazamKit: Signature generated (\(signature.dataRepresentation.count) bytes)")

        guard let session = session else {
            statusMessage = "ShazamKit session not available"
            print("🔴 ShazamKit: Session not available")
            isMatching = false
            return nil
        }

        statusMessage = "Matching..."

        // Match the signature
        let match = await withCheckedContinuation { continuation in
            self.continuation = continuation
            print("🔵 ShazamKit: Starting match...")
            session.match(signature)
        }

        return processMatchResult(match)
    }

    /// Process match result and extract song info
    func processMatchResult(_ match: SHMatch?) -> (title: String, artist: String)? {
        isMatching = false

        guard let match = match else {
            statusMessage = "No match found"
            print("🟡 ShazamKit: No match found")
            return nil
        }

        print("🟢 ShazamKit: Match found with \(match.mediaItems.count) media items")

        if let mediaItem = match.mediaItems.first {
            let title = mediaItem.title ?? "Unknown"
            let artist = mediaItem.artist ?? "Unknown"
            statusMessage = "Found: \(title)"
            print("🟢 ShazamKit: Matched - \(title) by \(artist)")
            return (title, artist)
        }

        statusMessage = "Match found but no song info"
        print("🟡 ShazamKit: Match found but no media items")
        return nil
    }

    /// Identify from raw PCM samples (wrapper that processes result)
    func identifySong(from samples: [Float], sampleRate: Double) async -> (title: String, artist: String)? {
        return await identifyFromPCM(samples, sampleRate: sampleRate)
    }

    // MARK: - SHSessionDelegate

    nonisolated func session(_ session: SHSession, didFind match: SHMatch) {
        Task { @MainActor in
            print("🟢 ShazamKit Delegate: Match found!")
            self.lastMatch = match
            self.isMatching = false
            self.statusMessage = "Match found!"
            self.continuation?.resume(returning: match)
            self.continuation = nil
        }
    }

    nonisolated func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: Error?) {
        Task { @MainActor in
            if let error = error {
                print("🔴 ShazamKit Delegate: Error - \(error.localizedDescription)")
            } else {
                print("🟡 ShazamKit Delegate: No match found")
            }
            self.lastError = error
            self.isMatching = false
            self.statusMessage = error?.localizedDescription ?? "No match found"
            self.continuation?.resume(returning: nil)
            self.continuation = nil
        }
    }
}
