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

    /// 停止录音后置为 true：忽略迟到的 final 结果，避免覆盖用户停止后继续编辑的文字。
    private var suppressTranscriptUpdates = false

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
        suppressTranscriptUpdates = false

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
        // iOS 16+：让中文识别自带断句和标点，否则整段无标点很难读
        recognitionRequest.addsPunctuation = true

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
            // 只在成功回调里更新文字；cancel 等错误回调可能携带空 result，
            // 直接赋值会把已转写出的文字清空（用户停止后文字消失的原因）。
            if let result, error == nil, !suppressTranscriptUpdates {
                transcript = result.bestTranscription.formattedString
            }

            if error != nil || result?.isFinal == true {
                recognitionTask = nil
                recognitionRequest = nil
            }
        }
    }

    /// Stops the recording gracefully, ending the recognition task and audio session.
    ///
    /// 注意：这里**不** cancel 识别任务。endAudio 之后 Speech 会把最后一段
    /// final 结果吐回来，立刻 cancel 会把它一起丢弃。转写结果以停止瞬间
    /// 的最后一次 partial 为准（suppressTranscriptUpdates 挡住迟到的覆盖）。
    func stopRecording() {
        isRecording = false
        suppressTranscriptUpdates = true

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-speech-success") {
            return
        }
        #endif

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
    }
}
