import Dispatch

public protocol TaskQueue: class {
    var _runner: DispatchWorkItem? { get set }
    var frequency: DispatchTimeInterval { get }
    var count: Int { get }
    var isEmpty: Bool { get }

    func queue<T: Task>(task: T)
    func dequeue() -> Task?
}

public let defaultFrequency: DispatchTimeInterval = .seconds(5)

extension TaskQueue {
    public var frequency: DispatchTimeInterval { return defaultFrequency }
    public var isEmpty: Bool { return count == 0 }

    public func start(qos: DispatchQoS = .utility) {
        start(on: .global(qos: qos.qosClass))
    }

    public func start(on queue: DispatchQueue) {
        guard _runner == nil else { return }

        _runner = DispatchWorkItem() {
            self.runNext(on: queue)
        }

        queue.async(execute: _runner!)
    }

    private func runNext(on queue: DispatchQueue) {
        guard _runner != nil else { return }

        defer {
            let runner = DispatchWorkItem() {
                self.runNext(on: queue)
            }

            // If there are no more items left to run, then wait for the
            // configured frequency before checking again
            if isEmpty {
                queue.asyncAfter(deadline: .now() + frequency, execute: runner)
            } else {
                queue.async(execute: runner)
            }
        }

        guard let next = dequeue() else { return }

        next.state = .executing
        next.state = next.execute() ? .succeeded : .failed
    }

    public func stop() {
        guard _runner != nil else { return }
        defer { _runner = nil }

        _runner!.cancel()
    }
}
