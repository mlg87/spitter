import Foundation
import SpitterCore

/// `TimerScheduling` backed by the main queue. Cancellation is what the controller uses to disarm
/// the max-recording timeout, so the returned closure must be safe to call more than once.
final class DispatchTimers: TimerScheduling {
    func schedule(after seconds: Double, _ handler: @escaping () -> Void) -> () -> Void {
        let boxed = UncheckedBox(handler)
        let item = DispatchWorkItem { boxed.value() }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
        return { item.cancel() }
    }
}
