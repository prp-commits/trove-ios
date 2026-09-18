import Foundation
import AVFoundation
import Speech

/// The real on-device capture engine (Theme C C1d) behind the `VoiceCaptureEngine`
/// seam. An `AVAudioEngine` mic tap drives BOTH a live amplitude level (for the
/// waveform) and `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`, so
/// on the free tier **audio never leaves the phone**. SpeechAnalyzer (iOS 26) is a
/// later refinement; this is the iOS 18+ baseline.
@MainActor final class AppleVoiceCaptureEngine: VoiceCaptureEngine {
    var onTick: ((CGFloat, TimeInterval, String) -> Void)?
    var onFailure: ((String) -> Void)?

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var startedAt = Date()
    private var committed = ""   // finalized segments, joined — survives the recognizer resetting after a pause
    private var latest = ""      // committed + the in-progress partial; what finish() returns

    func start() {
        startedAt = Date(); latest = ""; committed = ""
        guard let recognizer, recognizer.isAvailable else { onFailure?("stt_failed"); return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            req.requiresOnDeviceRecognition = true       // free tier: nothing leaves the device
            request = req

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
                let level = AppleVoiceCaptureEngine.rms(buffer)
                DispatchQueue.main.async { self?.emit(level: level) }
            }
            audioEngine.prepare()
            try audioEngine.start()

            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let result {
                        // On-device recognition finalizes an utterance after a pause, then starts a
                        // FRESH transcription for what follows — so each result's formattedString is
                        // only the current utterance, not the running total. Commit finalized segments
                        // and keep the whole note; assigning `latest` directly would erase everything
                        // before the pause.
                        let segment = result.bestTranscription.formattedString
                        if result.isFinal {
                            self.committed = Self.join(self.committed, segment)
                            self.latest = self.committed
                        } else {
                            self.latest = Self.join(self.committed, segment)
                        }
                    }
                    if error != nil, self.latest.isEmpty { self.onFailure?("stt_failed") }
                }
            }
        } catch {
            teardown()
            onFailure?("stt_failed")
        }
    }

    func finish() -> String {
        teardown()
        return latest
    }

    func cancel() {
        task?.cancel()
        teardown()
        latest = ""; committed = ""
    }

    /// Join two transcript fragments with a single space, tolerating either being empty.
    private static func join(_ a: String, _ b: String) -> String {
        let head = a.trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = b.trimmingCharacters(in: .whitespacesAndNewlines)
        if head.isEmpty { return tail }
        if tail.isEmpty { return head }
        return head + " " + tail
    }

    private func emit(level: CGFloat) {
        onTick?(level, Date().timeIntervalSince(startedAt), latest)
    }

    private func teardown() {
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning { audioEngine.stop() }
        request?.endAudio()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Peak-ish RMS of a buffer, mapped to 0…1 with speech headroom, for the waveform.
    private static func rms(_ buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let ch = buffer.floatChannelData?[0] else { return 0 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<n { let s = ch[i]; sum += s * s }
        let rms = sqrt(sum / Float(n))
        return CGFloat(min(1, max(0, rms * 6)))   // typical speech RMS ~0.05–0.3 → usable bar heights
    }
}
