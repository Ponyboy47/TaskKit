import Dispatch

public protocol TaskQueue: AnyObject {
    var _runner: DispatchWorkItem? { get set }
    var frequency: DispatchTimeInterval { get }
    var count: Int { get }
    var isEmpty: Bool { get }
    var running: Task? { get set }

    func queue<T: Task>(task: T)
    func dequeue() -> Task?

    /**
     Used to signal to the TaskQueue that a task has finished running. If the
     task failed you may want to requeue it or if it succeeded then you might
     want to officially remove it from the array/storage of queued tasks
     **/
    func complete(task: Task)
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

        _runner = DispatchWorkItem {
            self.runNext(on: queue)
        }

        queue.async(execute: _runner!)
    }

    @discardableResult
    private func run(task: Task, on queue: DispatchQueue) -> Bool {
        defer {
            running = nil
            queue.async {
                self.complete(task: task)
            }
        }

        switch task {
        case is DependentTask:
            guard runDependencies(of: task as! DependentTask, on: queue) else {
                task.state = .failed
                return false
            }
        default: break
        }

        guard _runner != nil else { return false }

        task.state = .executing
        running = task
        task.state = task.execute() ? .succeeded : .failed

        return task.state == .succeeded
    }

    private func runDependencies(of task: DependentTask, on queue: DispatchQueue) -> Bool {
        while let dep = task.nextDependency() {
            guard run(task: dep, on: queue) else { return false }
        }

        return true
    }

    private func runNext(on queue: DispatchQueue) {
        defer {
            let runner = DispatchWorkItem {
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
        run(task: next, on: queue)
    }

    public func stop() {
        guard _runner != nil else { return }
        defer { _runner = nil }

        if let active = running {
            switch active {
            case is PausableTask: active.state = (active as! PausableTask).pause() ? .paused : .failed
            default: active.state = .cancelled
            }
        }

        _runner!.cancel()
    }

    public func complete(task _: Task) {}
}
