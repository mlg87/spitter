/// Ferries a non-`Sendable` value across a `DispatchQueue.main.async` hop.
///
/// Safe by construction everywhere it is used here: the value is created on one thread, handed off
/// once, and only ever read on the main queue.
struct UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
