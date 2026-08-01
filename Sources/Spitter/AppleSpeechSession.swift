import AVFoundation
import Foundation
import Speech
import SpitterCore

enum SpeechSessionError: LocalizedError {
    case recognizerUnavailable
    case onDeviceUnsupported(locale: String)
    case notAuthorized
    case timedOut
    case noTranscript

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognition is not available right now."
        case .onDeviceUnsupported(let locale):
            return "On-device speech recognition is unavailable for \(locale)."
        case .notAuthorized:
            return "Speech recognition or microphone access has not been granted."
        case .timedOut:
            return "Transcription timed out."
        case .noTranscript:
            return "No speech was recognized."
        }
    }
}

/// `SpeechSession` backed by Apple's on-device recognizer.
///
/// `requiresOnDeviceRecognition` is non-negotiable here: it is what keeps audio from leaving the
/// machine, which is the whole point of the app.
/// All mutable state is touched on the main queue only; recognizer callbacks hop there first,
/// which is what makes the `@unchecked Sendable` conformance honest.
final class AppleSpeechSession: SpeechSession, @unchecked Sendable {
    /// How long to wait for the recognizer to emit its final result after audio ends.
    private static let finalizationTimeout: Double = 10

    private let locale: Locale
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latestTranscript: String?
    private var terminalError: Error?
    private var completion: ((Result<String, Error>) -> Void)?
    private var timeoutWorkItem: DispatchWorkItem?

    init(locale: Locale = Locale(identifier: "en-US")) {
        self.locale = locale
    }

    func start() throws {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw SpeechSessionError.notAuthorized
        }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw SpeechSessionError.recognizerUnavailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw SpeechSessionError.onDeviceUnsupported(locale: locale.identifier)
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            teardownAudio()
            self.request = nil
            throw error
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let payload = UncheckedBox((self, result, error))
            DispatchQueue.main.async { payload.value.0?.consume(payload.value.1, payload.value.2) }
        }
    }

    private func consume(_ result: SFSpeechRecognitionResult?, _ error: Error?) {
        if let result {
            latestTranscript = result.bestTranscription.formattedString
        }
        if let error {
            terminalError = error
        }
        if error != nil || (result?.isFinal ?? false) {
            deliver()
        }
    }

    func finish(_ completion: @escaping (Result<String, Error>) -> Void) {
        self.completion = completion
        teardownAudio()
        request?.endAudio()

        // The recognizer occasionally never produces a final result (mic glitch, empty audio);
        // without this the controller would sit in `.transcribing` forever.
        let timeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if terminalError == nil && latestTranscript == nil {
                terminalError = SpeechSessionError.timedOut
            }
            deliver()
        }
        timeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.finalizationTimeout, execute: timeout)
    }

    func cancel() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        completion = nil
        teardownAudio()
        task?.cancel()
        task = nil
        request = nil
    }

    private func teardownAudio() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    /// Calls the pending completion exactly once. Always reached on the main queue.
    private func deliver() {
        guard let completion else { return }
        self.completion = nil
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        task = nil
        request = nil

        let transcript = latestTranscript
        let failure = terminalError
        let result: Result<String, Error>
        if let transcript, !transcript.isEmpty {
            // A late error after a usable transcript is not worth surfacing; the text is what matters.
            result = .success(transcript)
        } else if let failure {
            result = .failure(failure)
        } else {
            result = .success("")
        }

        completion(result)
    }
}
