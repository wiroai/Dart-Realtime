import Flutter
import AVFoundation
import Combine

public class WiroVoiceEnginePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "wiro_voice_engine", binaryMessenger: registrar.messenger())
        let eventChannel = FlutterEventChannel(name: "wiro_voice_engine/events", binaryMessenger: registrar.messenger())
        let instance = WiroVoiceEnginePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance)
    }

    private var audioManager: AudioManager
    private var eventSink: FlutterEventSink?
    private var cancellables = Set<AnyCancellable>()
    private var isInitialized: Bool = false

    override init() {
        audioManager = AudioManager()
        super.init()
        setupInterruptionObserver()
        setupConfigurationChangeObserver()
    }

    private func setupInterruptionObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    private func setupConfigurationChangeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioEngineConfigurationChange),
            name: NSNotification.Name.AVAudioEngineConfigurationChange,
            object: nil
        )
    }

    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        if type == .began {
            audioManager.stopPlayback()
            DispatchQueue.main.async { [weak self] in
                self?.eventSink?(["type": "error", "message": "Audio session interrupted"])
            }
        }
    }

    @objc private func handleAudioEngineConfigurationChange(notification: Notification) {
        audioManager.handleConfigurationChange()
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            guard let args = call.arguments as? [String: Any],
                  let audioConfig = args["audioConfig"] as? [String: Any],
                  let sessionConfig = args["sessionConfig"] as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing or invalid arguments", details: nil))
                return
            }
            initialize(audioConfig: audioConfig, sessionConfig: sessionConfig, result: result)
        case "startRecording":
            startRecording(result: result)
        case "stopRecording":
            stopRecording(result: result)
        case "playAudioChunk":
            guard let args = call.arguments as? [String: Any],
                  let audioData = args["audioData"] as? FlutterStandardTypedData else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing or invalid audioData", details: nil))
                return
            }
            playAudioChunk(audioData: audioData, result: result)
        case "stopPlayback":
            stopPlayback(result: result)
        case "shutdownAll":
            shutdownAll(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func initialize(audioConfig: [String: Any], sessionConfig: [String: Any], result: @escaping FlutterResult) {
        if isInitialized {
            result(nil)
            return
        }

        let channels = audioConfig["channels"] as? UInt32 ?? 1
        let sampleRate = audioConfig["sampleRate"] as? Double ?? 48000.0
        let bitDepth = audioConfig["bitDepth"] as? Int ?? 16
        let bufferSize = audioConfig["bufferSize"] as? Int ?? 4096
        let amplitudeThreshold = audioConfig["amplitudeThreshold"] as? Float ?? 0.05
        let enableAEC = audioConfig["enableAEC"] as? Bool ?? true
        let category = mapCategory(sessionConfig["category"] as? String ?? "playAndRecord")
        let mode = mapMode(sessionConfig["mode"] as? String ?? "spokenAudio")
        let options = (sessionConfig["options"] as? [String] ?? []).compactMap { mapOption($0) }
        let preferredBufferDuration = sessionConfig["preferredBufferDuration"] as? Double ?? 0.005

        audioManager = AudioManager(
            channels: channels,
            sampleRate: sampleRate,
            bitDepth: bitDepth,
            bufferSize: bufferSize,
            amplitudeThreshold: amplitudeThreshold,
            enableAEC: enableAEC,
            category: category,
            mode: mode,
            options: AVAudioSession.CategoryOptions(options),
            preferredSampleRate: sampleRate,
            preferredBufferDuration: preferredBufferDuration
        )
        audioManager.eventSink = eventSink
        audioManager.setupEngine()
        isInitialized = true
        result(nil)
    }

    private func startRecording(result: @escaping FlutterResult) {
        audioManager.startRecording().sink { [weak self] audioData in
            DispatchQueue.main.async {
                self?.eventSink?(["type": "audio_chunk", "data": FlutterStandardTypedData(bytes: audioData)])
            }
        }.store(in: &cancellables)
        result(nil)
    }

    private func stopRecording(result: @escaping FlutterResult) {
        audioManager.stopRecording()
        cancellables.removeAll()
        result(nil)
    }

    private func playAudioChunk(audioData: FlutterStandardTypedData, result: @escaping FlutterResult) {
        // Scheduling happens on the manager's playback queue; replying
        // immediately keeps the Dart feed loop and the main thread decoupled
        // from per-chunk conversion work. A stopped engine is revived on
        // that queue rather than rejected here, so a reconnect after the
        // session was deactivated heals itself.
        audioManager.playAudioChunk(audioData: audioData.data)
        result(nil)
    }

    private func stopPlayback(result: @escaping FlutterResult) {
        audioManager.stopPlayback()
        result(nil)
    }

    private func shutdownAll(result: @escaping FlutterResult) {
        audioManager.shutdownAll()
        cancellables.removeAll()
        NotificationCenter.default.removeObserver(self)
        eventSink = nil
        result(nil)
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        audioManager.eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        audioManager.eventSink = nil
        audioManager.stopRecording()
        cancellables.removeAll()
        return nil
    }

    private func mapCategory(_ category: String) -> AVAudioSession.Category {
        switch category {
        case "ambient": return .ambient
        case "soloAmbient": return .soloAmbient
        case "playback": return .playback
        case "record": return .record
        case "playAndRecord": return .playAndRecord
        case "multiRoute": return .multiRoute
        default: return .playAndRecord
        }
    }

    private func mapMode(_ mode: String) -> AVAudioSession.Mode {
        switch mode {
        case "defaultMode": return .default
        case "spokenAudio": return .spokenAudio
        case "voiceChat": return .voiceChat
        case "videoChat": return .videoChat
        case "videoRecording": return .videoRecording
        case "measurement": return .measurement
        case "moviePlayback": return .moviePlayback
        case "gameChat": return .gameChat
        default: return .spokenAudio
        }
    }

    private func mapOption(_ option: String) -> AVAudioSession.CategoryOptions? {
        switch option {
        case "mixWithOthers": return .mixWithOthers
        case "duckOthers": return .duckOthers
        case "allowBluetooth": return .allowBluetooth
        case "allowBluetoothA2DP": return .allowBluetoothA2DP
        case "allowAirPlay": return .allowAirPlay
        case "defaultToSpeaker": return .defaultToSpeaker
        default: return nil
        }
    }
}
