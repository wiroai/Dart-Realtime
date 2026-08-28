import AVFoundation
import Combine
import Flutter

public class AudioManager {
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var inputNode: AVAudioInputNode { audioEngine.inputNode }
    private var inputFormat: AVAudioFormat
    private var audioFormat: AVAudioFormat
    private var webSocketFormat: AVAudioFormat
    private var isRecording = false
    private let audioChunkPublisher = PassthroughSubject<Data, Never>()
    public let errorPublisher = PassthroughSubject<String, Never>()
    private var recordingConverter: AVAudioConverter?
    private var playbackConverter: AVAudioConverter?
    private let amplitudeThreshold: Float
    private let enableAEC: Bool
    private let targetSampleRate: Float64 = 24000

    /// Serial queue that owns playback scheduling so per-chunk conversion
    /// never competes with UI work on the main thread.
    private let playbackQueue = DispatchQueue(
        label: "wiro_voice_engine.playback",
        qos: .userInteractive
    )

    public var eventSink: FlutterEventSink?

    public init(
        channels: UInt32 = 1,
        sampleRate: Double = 48000,
        bitDepth: Int = 16,
        bufferSize: Int = 4096,
        amplitudeThreshold: Float = 0.05,
        enableAEC: Bool = true,
        category: AVAudioSession.Category = .playAndRecord,
        mode: AVAudioSession.Mode = .voiceChat,
        options: AVAudioSession.CategoryOptions = [.allowBluetooth, .defaultToSpeaker],
        preferredSampleRate: Double = 48000,
        preferredBufferDuration: Double = 0.005
    ) {
        self.amplitudeThreshold = amplitudeThreshold
        self.enableAEC = enableAEC

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(category, mode: mode, options: options)
            try session.setPreferredSampleRate(preferredSampleRate)
            try session.setPreferredIOBufferDuration(preferredBufferDuration)
            try session.setInputGain(1.0)
            try session.setActive(true, options: [.notifyOthersOnDeactivation])
        } catch {
            errorPublisher.send("Audio session error: \(error.localizedDescription)")
        }

        self.inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: session.sampleRate,
            channels: channels,
            interleaved: true
        )!
        self.audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: session.sampleRate,
            channels: 2,
            interleaved: false
        )!
        self.webSocketFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: channels,
            interleaved: true
        )!
        setupConverters()
    }

    private func setupConverters() {
        recordingConverter = AVAudioConverter(from: inputFormat, to: webSocketFormat)
        playbackConverter = AVAudioConverter(from: webSocketFormat, to: audioFormat)
        if recordingConverter == nil || playbackConverter == nil {
            reportError("Failed to initialize audio converters")
        }
    }

    public func setupEngine() {
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: audioFormat)
        audioEngine.connect(audioEngine.mainMixerNode, to: audioEngine.outputNode, format: audioFormat)
        audioEngine.mainMixerNode.outputVolume = 1.0

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(true)
            if enableAEC {
                try inputNode.setVoiceProcessingEnabled(true)
            }
            try audioEngine.start()
            primePlayerNode()
        } catch {
            reportError("Engine error: \(error.localizedDescription)")
        }
    }

    /// Brings a stopped engine back to life, session included.
    ///
    /// The engine dies whenever the Dart side deactivates the shared audio
    /// session — a failed turn, a reconnect after the server drops the
    /// socket. The engine object itself survives, so every later playback
    /// call lands here first and revives it instead of scheduling onto a
    /// dead graph. Capture goes through [restartEngineForCapture] instead,
    /// because a revived engine is not good enough for the microphone.
    @discardableResult
    private func ensureEngineRunning() -> Bool {
        // Both the recording path (main thread) and the playback path (the
        // playback queue) can arrive here; the restart must happen once.
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        if audioEngine.isRunning {
            return true
        }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try audioEngine.start()
            primePlayerNode()
            return true
        } catch {
            reportError("Engine restart failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Starts the player on a short silent buffer right after the engine
    /// spins up. A cold first `play()` racing engine start is where the
    /// first real buffer can get rendered twice (heard as a repeated
    /// word); priming establishes the render timeline before any real
    /// audio arrives, so the first chunk appends to a running node.
    private func primePlayerNode() {
        let frameCount = AVAudioFrameCount(audioFormat.sampleRate * 0.1)
        guard let silence = AVAudioPCMBuffer(
            pcmFormat: audioFormat,
            frameCapacity: frameCount
        ) else { return }
        silence.frameLength = frameCount
        if let channels = silence.floatChannelData {
            for channel in 0..<Int(audioFormat.channelCount) {
                memset(
                    channels[channel],
                    0,
                    Int(frameCount) * MemoryLayout<Float>.size
                )
            }
        }
        playerNode.scheduleBuffer(silence, completionHandler: nil)
        playerNode.play()
    }

    @discardableResult
    private func installRecordingTap() -> Bool {
        let bus = 0
        let nativeInputFormat = inputNode.outputFormat(forBus: bus)
        guard nativeInputFormat.sampleRate > 0,
              nativeInputFormat.channelCount > 0 else {
            reportError("Microphone input format is unavailable")
            return false
        }
        guard let converter = AVAudioConverter(
            from: nativeInputFormat,
            to: webSocketFormat
        ) else {
            reportError("Recording converter unavailable")
            return false
        }

        inputFormat = nativeInputFormat
        recordingConverter = converter
        inputNode.removeTap(onBus: bus)
        inputNode.installTap(onBus: bus, bufferSize: 4096, format: nil) { [weak self, converter] buffer, _ in
            guard let self = self else { return }
            let frameCapacity = UInt32(round(Double(buffer.frameLength) * converter.outputFormat.sampleRate / buffer.format.sampleRate))
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: converter.outputFormat,
                frameCapacity: frameCapacity
            ) else {
                self.reportError("Failed to create output buffer")
                return
            }
            var error: NSError?
            // One pull per buffer, or the converter consumes the same
            // microphone samples twice.
            var inputProvided = false
            let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                if inputProvided {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                inputProvided = true
                outStatus.pointee = .haveData
                return buffer
            }
            if let error = error {
                self.reportError("Recording conversion error: \(error.localizedDescription)")
                return
            }
            if status == .error {
                self.reportError("Recording conversion failed")
                return
            }
            if let data = outputBuffer.int16ChannelData?.pointee {
                let byteCount = Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size * Int(outputBuffer.format.channelCount)
                self.audioChunkPublisher.send(Data(bytes: data, count: byteCount))
            } else {
                self.reportError("No audio data in output buffer")
            }
        }
        return true
    }

    public func startRecording() -> AnyPublisher<Data, Never> {
        guard !isRecording else {
            return audioChunkPublisher.eraseToAnyPublisher()
        }
        // A tap on a stopped engine installs fine and then never fires;
        // the engine must be alive before the tap means anything.
        guard restartEngineForCapture() else {
            return audioChunkPublisher.eraseToAnyPublisher()
        }
        guard installRecordingTap() else {
            return audioChunkPublisher.eraseToAnyPublisher()
        }
        isRecording = true
        return audioChunkPublisher.eraseToAnyPublisher()
    }

    /// Rebuilds the engine before every capture session instead of reviving
    /// whatever the previous conversation left behind.
    ///
    /// After the Dart side deactivates and reactivates the shared audio
    /// session between conversations, an engine that survived — or was
    /// revived by a stray configuration change — can keep reporting itself
    /// as running while its voice-processed input renders pure silence.
    /// Buffers still arrive, so no watchdog that counts them can tell the
    /// difference, and the user talks to a model that hears nothing. iOS
    /// only clears that state when the engine is fully stopped, voice
    /// processing is asserted again, and the engine starts against the
    /// session that is active now.
    private func restartEngineForCapture() -> Bool {
        // Ordered ahead of the lock: playback tasks take the same lock in
        // ensureEngineRunning, and a sync wait while holding it deadlocks.
        stopPlaybackAndWait()
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        audioEngine.stop()
        audioEngine.reset()
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            reportError("Engine restart failed: \(error.localizedDescription)")
            return false
        }
        if enableAEC {
            // The off-and-on pass is the documented way out of the muted
            // voice-processing state; a toggle iOS refuses leaves the
            // previous AEC state in place and capture is still worth
            // starting.
            do {
                if inputNode.isVoiceProcessingEnabled {
                    try inputNode.setVoiceProcessingEnabled(false)
                }
                try inputNode.setVoiceProcessingEnabled(true)
            } catch {
                reportError(
                    "Voice processing toggle failed: \(error.localizedDescription)"
                )
            }
        }
        do {
            try audioEngine.start()
            primePlayerNode()
            return true
        } catch {
            reportError("Engine restart failed: \(error.localizedDescription)")
            return false
        }
    }

    public func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        inputNode.removeTap(onBus: 0)
    }

    /// Schedules a chunk asynchronously on the playback queue. Errors are
    /// reported through `errorPublisher` and the event sink because the
    /// caller has already returned by the time conversion happens.
    public func playAudioChunk(audioData: Data) {
        playbackQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.scheduleAudioChunk(audioData)
            } catch {
                self.reportError("Playback failed: \(error.localizedDescription)")
            }
        }
    }

    private func scheduleAudioChunk(_ audioData: Data) throws {
        guard ensureEngineRunning(), let converter = playbackConverter else {
            throw NSError(domain: "AudioManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Engine or converter unavailable"])
        }
        let frameCount = AVAudioFrameCount(audioData.count / (MemoryLayout<Int16>.size * Int(self.webSocketFormat.channelCount)))
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: webSocketFormat, frameCapacity: frameCount) else {
            throw NSError(domain: "AudioManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to create input buffer"])
        }
        inputBuffer.frameLength = frameCount
        audioData.withUnsafeBytes { rawBuffer in
            inputBuffer.int16ChannelData?.pointee.update(from: rawBuffer.baseAddress!.assumingMemoryBound(to: Int16.self), count: Int(frameCount * webSocketFormat.channelCount))
        }
        let outputFrameCapacity = UInt32(round(Double(frameCount) * audioFormat.sampleRate / webSocketFormat.sampleRate))
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: AVAudioFrameCount(outputFrameCapacity)) else {
            throw NSError(domain: "AudioManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "Failed to create output buffer"])
        }
        var error: NSError?
        // The converter may pull input several times to fill the output
        // buffer (its resampler keeps a filter delay, so the first convert
        // never fills capacity from one pull). Handing it the same buffer
        // on every pull played the same audio twice; each chunk must be
        // provided exactly once and then report .noDataNow.
        var inputProvided = false
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if inputProvided {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputProvided = true
            outStatus.pointee = .haveData
            return inputBuffer
        }
        if let error = error {
            throw error
        }
        if status == .error {
            throw NSError(domain: "AudioManager", code: -5, userInfo: [NSLocalizedDescriptionKey: "Playback conversion failed"])
        }
        playerNode.scheduleBuffer(outputBuffer, completionHandler: nil)
        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    /// Runs on the playback queue so a flush stays ordered with chunks that
    /// were scheduled before it.
    public func stopPlayback() {
        playbackQueue.async { [weak self] in
            self?.playerNode.stop()
            self?.playerNode.reset()
        }
    }

    /// Synchronous variant for teardown paths that must observe the stop
    /// before the engine itself is shut down.
    private func stopPlaybackAndWait() {
        playbackQueue.sync { [weak self] in
            self?.playerNode.stop()
            self?.playerNode.reset()
        }
    }

    public func shutdownAll() {
        stopRecording()
        stopPlaybackAndWait()
        audioEngine.stop()
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            reportError("Failed to deactivate audio session: \(error.localizedDescription)")
        }
    }

    public func handleConfigurationChange() {
        // Only a live capture is worth reviving. Restarting an idle engine
        // here would re-activate an audio session the Dart side already
        // let go of, and leave a zombie engine for the next conversation
        // to inherit.
        guard isRecording, !audioEngine.isRunning else { return }
        if ensureEngineRunning() {
            // The route change may have altered the input format, so the
            // tap is rebuilt against whatever the microphone is now.
            installRecordingTap()
        }
    }

    public func isRecordingActive() -> Bool {
        return isRecording
    }

    private func reportError(_ message: String) {
        errorPublisher.send(message)
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(["type": "error", "message": message])
        }
    }
}
