import AVFoundation
import Combine
import Speech

/// Wraps Apple's Speech framework to capture live audio and produce transcriptions locally for privacy.
@MainActor
final class SpeechService: NSObject, ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))

    /// Asks users for microphone + speech permissions up front and caches the result for UI bindings.
    func requestAuthorization() async {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-testing-speech-denied") {
            authorizationStatus = .denied
            return
        }
        if arguments.contains("-ui-testing-speech-success") {
            authorizationStatus = .authorized
            return
        }
        #endif

        let microphoneGranted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard microphoneGranted else {
            authorizationStatus = .denied
            return
        }

        authorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// Starts a new transcription session, piping microphone audio into Speech framework.
    func startRecording() throws {
        guard authorizationStatus == .authorized else {
            throw NSError(domain: "SpeechService", code: 1, userInfo: [NSLocalizedDescriptionKey: "语音识别未授权"])
        }

        transcript = ""

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-speech-success") {
            transcript = "今天我感到有些紧张，但说出来后轻松了些。"
            isRecording = true
            return
        }
        #endif

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            if let result {
                transcript = result.bestTranscription.formattedString
            }

            if error != nil || result?.isFinal == true {
                stopRecording()
            }
        }
    }

    /// Stops the recording gracefully, ending the recognition task and audio session.
    func stopRecording() {
        isRecording = false

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-speech-success") {
            return
        }
        #endif

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }
}
