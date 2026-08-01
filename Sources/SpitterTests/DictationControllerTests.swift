import Foundation
import SpitterCore

final class FakeSpeechSession: SpeechSession {
    var startError: Error?
    private(set) var started = false
    private(set) var cancelled = false
    private(set) var finishCount = 0
    private var pending: ((Result<String, Error>) -> Void)?

    func start() throws {
        if let startError { throw startError }
        started = true
    }

    func finish(_ completion: @escaping (Result<String, Error>) -> Void) {
        finishCount += 1
        pending = completion
    }

    func cancel() { cancelled = true }

    /// Deliver the transcript the app is waiting on, simulating recognition completing.
    func resolve(_ result: Result<String, Error>) {
        let completion = pending
        pending = nil
        completion?(result)
    }
}

final class FakeDelivery: TextDelivering {
    var outcome: DeliveryOutcome = .pasted
    private(set) var delivered: [String] = []

    func deliver(_ text: String) -> DeliveryOutcome {
        delivered.append(text)
        return outcome
    }
}

final class ManualTimers: TimerScheduling {
    private(set) var scheduled: [(seconds: Double, handler: () -> Void)] = []
    private(set) var cancelCount = 0

    func schedule(after seconds: Double, _ handler: @escaping () -> Void) -> () -> Void {
        scheduled.append((seconds, handler))
        return { [weak self] in self?.cancelCount += 1 }
    }

    func fireLast() { scheduled.last?.handler() }
}

struct FakeError: Error, Equatable { let message: String }

@MainActor
private func makeController() -> (DictationController, FakeSpeechSession, FakeDelivery, ManualTimers, Box) {
    let session = FakeSpeechSession()
    let delivery = FakeDelivery()
    let timers = ManualTimers()
    let box = Box()
    let controller = DictationController(
        makeSession: { session },
        delivery: delivery,
        timers: timers,
        onStateChange: { box.states.append($0) },
        onEvent: { box.events.append($0) }
    )
    return (controller, session, delivery, timers, box)
}

final class Box {
    var states: [DictationController.State] = []
    var events: [DictationController.Event] = []
}

@MainActor
func runDictationControllerTests() {
    test("hold happy path: begin records, commit transcribes and delivers") {
        let (controller, session, delivery, _, box) = makeController()
        controller.handle(.begin)
        expect(session.started, "session started")
        expectEqual(controller.state, .recording)

        controller.handle(.commit)
        expectEqual(controller.state, .transcribing)
        session.resolve(.success("  hello world.  "))

        expectEqual(delivery.delivered, ["hello world."], "transcript trimmed before delivery")
        expectEqual(controller.state, .idle)
        expectEqual(box.states, [.recording, .transcribing, .idle])
        expectEqual(box.events, [.delivered(.pasted)])
    }

    test("delivery outcome is reported verbatim") {
        let (controller, session, delivery, _, box) = makeController()
        delivery.outcome = .copiedToClipboard
        controller.handle(.begin)
        controller.handle(.commit)
        session.resolve(.success("text"))
        expectEqual(box.events, [.delivered(.copiedToClipboard)])
    }

    test("menu toggle drives the same transitions as hotkey intents") {
        let (controller, session, delivery, _, _) = makeController()
        controller.toggleFromMenu()
        expectEqual(controller.state, .recording)
        controller.toggleFromMenu()
        expectEqual(controller.state, .transcribing)
        controller.toggleFromMenu()
        expectEqual(controller.state, .transcribing, "toggle while transcribing is a no-op")
        session.resolve(.success("ok"))
        expectEqual(delivery.delivered, ["ok"])
    }

    test("a failing start reports the error and stays idle") {
        let (controller, session, delivery, timers, box) = makeController()
        session.startError = FakeError(message: "no microphone")
        controller.handle(.begin)
        expectEqual(controller.state, .idle)
        expectEqual(timers.scheduled.count, 0, "no timeout armed")
        expectEqual(delivery.delivered, [])
        expectEqual(box.events.count, 1)
        if case .failed(let message)? = box.events.first {
            expect(message.contains("no microphone"), "error surfaced: \(message)")
        } else {
            expect(false, "expected a failure event")
        }
    }

    test("a failing transcription reports and returns to idle without delivering") {
        let (controller, session, delivery, _, box) = makeController()
        controller.handle(.begin)
        controller.handle(.commit)
        session.resolve(.failure(FakeError(message: "recognition died")))
        expectEqual(delivery.delivered, [])
        expectEqual(controller.state, .idle)
        expectEqual(box.events.count, 1)
    }

    test("an empty transcript skips delivery entirely") {
        let (controller, session, delivery, _, box) = makeController()
        controller.handle(.begin)
        controller.handle(.commit)
        session.resolve(.success("   \n  "))
        expectEqual(delivery.delivered, [], "clipboard must be left alone")
        expectEqual(box.events, [.emptyTranscript])
        expectEqual(controller.state, .idle)
    }

    test("cancel discards the session and never delivers") {
        let (controller, session, delivery, timers, box) = makeController()
        controller.handle(.begin)
        controller.handle(.cancel)
        expect(session.cancelled, "session cancelled")
        expectEqual(session.finishCount, 0)
        expectEqual(delivery.delivered, [])
        expectEqual(controller.state, .idle)
        expectEqual(timers.cancelCount, 1, "timeout disarmed")
        expectEqual(box.events, [])
    }

    test("the max-duration timeout self-commits") {
        let (controller, session, delivery, timers, _) = makeController()
        controller.handle(.begin)
        expectEqual(timers.scheduled.count, 1)
        expectEqual(timers.scheduled[0].seconds, 300)
        timers.fireLast()
        expectEqual(controller.state, .transcribing)
        session.resolve(.success("long one"))
        expectEqual(delivery.delivered, ["long one"])
    }

    test("a manual commit disarms the timeout") {
        let (controller, session, _, timers, _) = makeController()
        controller.handle(.begin)
        controller.handle(.commit)
        expectEqual(timers.cancelCount, 1)
        session.resolve(.success("x"))
    }

    test("intents in the wrong state are no-ops") {
        let (controller, session, delivery, _, box) = makeController()
        controller.handle(.commit)
        controller.handle(.cancel)
        expectEqual(controller.state, .idle)
        expect(!session.started, "nothing started")

        controller.handle(.begin)
        controller.handle(.begin)
        expectEqual(controller.state, .recording)
        controller.handle(.commit)
        controller.handle(.begin)
        expectEqual(controller.state, .transcribing, "begin while transcribing is ignored")
        session.resolve(.success("done"))
        expectEqual(delivery.delivered, ["done"])
        expectEqual(box.states, [.recording, .transcribing, .idle])
    }
}
