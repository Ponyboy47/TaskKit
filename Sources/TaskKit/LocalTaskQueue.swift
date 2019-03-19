import class Dispatch.DispatchWorkItem
import enum Dispatch.DispatchTimeInterval

/// A TaskQueue that keeps its list of tasks in a local dictionary
open class LocalTaskQueue: TaskQueue {
    public private(set) var tasks: [TaskPriority: [Task]] = [:]
    public var _runner: DispatchWorkItem? = nil
    public var count: Int {
        return tasks.reduce(0, { return $0 + $1.1.count })
    }
    public var isEmpty: Bool { return tasks.isEmpty }
    public let frequency: DispatchTimeInterval
    public var running: Task? = nil

    public init(frequency: DispatchTimeInterval = defaultFrequency) {
        self.frequency = frequency
    }

    public func queue<T: Task>(task: T) {
        if tasks.keys.contains(task.priority) {
            tasks[task.priority]!.append(task)
        } else {
            tasks[task.priority] = [task]
        }
    }

    public func dequeue() -> Task? {
        guard !tasks.isEmpty else { return nil }

        let highKey = tasks.keys.sorted().first!
        defer {
            if tasks[highKey]!.isEmpty {
                tasks.removeValue(forKey: highKey)
            }
        }

        return tasks[highKey]!.removeFirst()
    }
}
