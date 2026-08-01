import Foundation

/// One dictation take: capture audio, then produce a transcript. Implemented in the app target by
/// the Apple Speech adapter; faked in tests.
public protocol SpeechSession: AnyObject {
    func start() throws
    /// Stops capture and returns the final transcript. Must call `completion` exactly once.
    func finish(_ completion: @escaping (Result<String, Error>) -> Void)
    func cancel()
}

public enum DeliveryOutcome: Equatable, Sendable {
    case pasted
    case copiedToClipboard
}

public protocol TextDelivering: AnyObject {
    func deliver(_ text: String) -> DeliveryOutcome
}

public protocol TimerScheduling: AnyObject {
    /// Schedules `handler` and returns a closure that cancels it.
    func schedule(after seconds: Double, _ handler: @escaping () -> Void) -> () -> Void
}

/// Owns the idle -> recording -> transcribing lifecycle. All UI state derives from here.
@MainActor
public final class DictationController {
    public enum State: Equatable, Sendable {
        case idle
        case recording
        case transcribing
    }

    public enum Event: Equatable, Sendable {
        case delivered(DeliveryOutcome)
        case emptyTranscript
        case failed(String)
    }

    public private(set) var state: State = .idle {
        didSet {
            guard state != oldValue else { return }
            onStateChange(state)
        }
    }

    private let makeSession: () -> SpeechSession
    private let delivery: TextDelivering
    private let timers: TimerScheduling
    private let maxRecordingSeconds: Double
    private let onStateChange: (State) -> Void
    private let onEvent: (Event) -> Void

    private var session: SpeechSession?
    private var cancelTimeout: (() -> Void)?

    public init(
        makeSession: @escaping () -> SpeechSession,
        delivery: TextDelivering,
        timers: TimerScheduling,
        maxRecordingSeconds: Double = 300,
        onStateChange: @escaping (State) -> Void,
        onEvent: @escaping (Event) -> Void
    ) {
        self.makeSession = makeSession
        self.delivery = delivery
        self.timers = timers
        self.maxRecordingSeconds = maxRecordingSeconds
        self.onStateChange = onStateChange
        self.onEvent = onEvent
    }

    public func handle(_ intent: HotkeyIntent) {
        switch intent {
        case .begin: begin()
        case .commit: commit()
        case .cancel: cancel()
        }
    }

    /// Menu-driven equivalent of the hotkey: start when idle, stop when recording, ignore while a
    /// transcript is still being produced.
    public func toggleFromMenu() {
        switch state {
        case .idle: begin()
        case .recording: commit()
        case .transcribing: break
        }
    }

    private func begin() {
        guard state == .idle else { return }
        let newSession = makeSession()
        do {
            try newSession.start()
        } catch {
            onEvent(.failed(String(describing: error)))
            return
        }
        session = newSession
        // Safety net: a stuck hotkey (or a forgotten toggle) must not record forever.
        cancelTimeout = timers.schedule(after: maxRecordingSeconds) { [weak self] in
            self?.commit()
        }
        state = .recording
    }

    private func commit() {
        guard state == .recording, let session else { return }
        disarmTimeout()
        state = .transcribing
        session.finish { [weak self] result in
            guard let self else { return }
            self.session = nil
            switch result {
            case .success(let transcript):
                let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    onEvent(.emptyTranscript)
                } else {
                    onEvent(.delivered(delivery.deliver(text)))
                }
            case .failure(let error):
                onEvent(.failed(String(describing: error)))
            }
            state = .idle
        }
    }

    private func cancel() {
        guard state == .recording else { return }
        disarmTimeout()
        session?.cancel()
        session = nil
        state = .idle
    }

    private func disarmTimeout() {
        cancelTimeout?()
        cancelTimeout = nil
    }
}
