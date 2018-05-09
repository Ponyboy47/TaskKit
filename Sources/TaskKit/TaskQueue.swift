import Foundation
import Dispatch

public class TaskQueue {
    /// The name of the TaskQueue
    public private(set) var name: String

    /// The tasks that are waiting to be run
    public private(set) var waiting: [Task] = []
    /// A semaphore to use for preventing simultaneous access to the waiting array
    private var waitingSemaphore = DispatchSemaphore(value: 1)

    /// The tasks that are currently running
    public private(set) var running: [Task] = []
    /// A semaphore to use for preventing simultaneous access to the running array
    private var runningSemaphore = DispatchSemaphore(value: 1)

    /// The running tasks that may be cancelled
    private var cancellables: [CancellableTask] {
        return running.flatMap() {
            guard $0 is CancellableTask else { return nil }
            return $0 as! CancellableTask
        }
    }
    /// The waiting tasks that may have dependencies
    private var dependents: [DependentTask] {
        return waiting.flatMap() {
            guard $0 is DependentTask else { return nil }
            return $0 as! DependentTask
        }
    }

    /// The number of tasks that are currently running
    public var active: Int { return running.count }
    /// The total number of tasks left (including the currently running tasks)
    public var count: Int {
        let dependencies = dependents.reduce(0, { return $0 + $1.dependencies.count })
        return waiting.count + dependencies + active
    }

    /// Tracks whether the DispatchQueue is currently running or if it is suspended
    private var isActive: Bool = false
    /// Whether or not the queue is currently running any tasks
    public var isRunning: Bool { return isActive && active > 0 }

    /// The maximum number of tasks that can run simultaneously
    public var maxSimultaneous: Int

    /// The underlying DispatchQueue used to run the tasks
    public private(set) var queue: DispatchQueue
    /// The underlying DispatchGroups that tasks are added to when running
    private var groups: [String : DispatchGroup] = [:]
    /// A semaphore to use for preventing simultaneous access to the groups dictionary
    private var groupSemaphore = DispatchSemaphore(value: 1)

    /// The default number of tasks that can run simultaneously
    public static let defaultMaxSimultaneous: Int = 1
    /// A TaskQueue that runs on the main queue
    public static let main = TaskQueue(queue: .main)

    /**
    Initialize a TaskQueue

    - Parameter:
        - name: The name of the TaskQueue
        - maxSimultaneous: The maximum number of tasks that can run simultaneously
    */
    public init(_ name: String, maxSimultaneous: Int = TaskQueue.defaultMaxSimultaneous) {
        self.name = name
        self.maxSimultaneous = maxSimultaneous

        if maxSimultaneous > 1 {
            self.queue = DispatchQueue(label: "com.taskqueue.\(Foundation.UUID().description)", attributes: .concurrent)
        } else {
            self.queue = DispatchQueue(label: "com.taskqueue.\(Foundation.UUID().description)")
        }

        self.queue.suspend()
    }

    /**
    Initialize a TaskQueue

    - Parameter:
        - name: The name of the TaskQueue
        - maxSimultaneous: The maximum number of tasks that can run simultaneously
        - queue: The underlying DispatchQueue to use when running the tasks
    */
    public init(_ name: String, maxSimultaneous: Int = TaskQueue.defaultMaxSimultaneous, queue: DispatchQueue) {
        self.name = name
        self.maxSimultaneous = maxSimultaneous
        self.queue = queue
        self.queue.suspend()
    }

    /**
    Initialize a TaskQueue. Uses the queue's label as the name for the TaskQueue

    - Parameter:
        - maxSimultaneous: The maximum number of tasks that can run simultaneously
        - queue: The underlying DispatchQueue to use when running the tasks
    */
    public convenience init(maxSimultaneous: Int = TaskQueue.defaultMaxSimultaneous, queue: DispatchQueue) {
        self.init(queue.label, maxSimultaneous: maxSimultaneous, queue: queue)
    }

    /**
    Adds a task to the task array, then sorts the task array based on its tasks' priorities

    - Parameter task: The task to add
    */
    public func addTask(_ task: Task) {
        waitingSemaphore.wait()
        defer { waitingSemaphore.signal() }

        waiting.append(task)
        waiting.sort(by: { $0.priority.rawValue > $1.priority.rawValue })
    }

    /**
    Adds an array of tasks to the existing task array, then sorts the task array based on its tasks' priorities

    - Parameter tasks: The tasks to add
    */
    public func addTasks(_ tasks: [Task]) {
        waitingSemaphore.wait()
        defer { waitingSemaphore.signal() }

        waiting += tasks
        waiting.sort(by: { $0.priority.rawValue > $1.priority.rawValue })
    }

    /**
    Adds a variadic array of tasks to the existing task array, then sorts the task array based on its tasks' priorities

    - Parameter tasks: The tasks to add
    */
    public func addTasks(_ tasks: Task...) {
        self.addTasks(tasks)
    }

    /// Begin executing the tasks in the task array
    public func start() {
        // No need to start if we're already running
        guard !isRunning else { return }

        // Make sure that once we leave this function we resume the queue and set the isActive variable
        defer {
            queue.resume()
            isActive = true
        }

        // Fill the running array with the next tasks that need to be run
        while (running.count < maxSimultaneous) {
            startNext()
        }
    }

    /// Begins execution of the next task in the waiting list
    private func startNext() {
        waitingSemaphore.wait()
        var next = waiting.removeFirst()
        waitingSemaphore.signal()

        let group = DispatchGroup()
        if (next is DependentTask) {
            var next = next as! DependentTask

            queue.async(group: group, qos: next.qos) {
                for var dependency in next.dependencies {
                    dependency.configure()
                    dependency.execute()
                }
                next.configure()
                next.execute()
            }
        } else {
            queue.async(group: group, qos: next.qos) {
                next.configure()
                next.execute()
            }
        }

        runningSemaphore.wait()
        running.append(next)
        runningSemaphore.signal()

        groupSemaphore.wait()
        let uniqueKey = Foundation.UUID().description
        groups[uniqueKey] = group
        groupSemaphore.signal()

        group.notify(qos: queue.qos, queue: queue) {
            self.groupSemaphore.wait()
            defer { self.groupSemaphore.signal() }

            self.groups.removeValue(forKey: uniqueKey)

            self.startNext()
        }
    }

    @available(*, renamed: "start")
    public func resume() { self.start() }

    /// Pauses (AKA suspends) current execution of the running tasks and does not begin to run any new tasks
    public func pause() {
        queue.suspend()
        isActive = false
    }

    @available(*, renamed: "pause")
    public func suspend() { self.pause() }

    /// Cancel execution of all currently running tasks
    public func cancel() {
        runningSemaphore.wait()
        defer { runningSemaphore.signal() }

        for _ in 0..<active {
            running.dropFirst()
        }
    }

    /// Blocks execution until all tasks have finished executing (including the tasks not currently running)
    public func wait() {
        for (_, group) in groups {
            group.wait()
        }
    }
    /**
    Blocks execution until either all tasks have finished executing (including the tasks not currently running) or the timeout has been reached

    - Parameter timeout: The latest time to wait for the tasks to finish executing
    - Returns: Whether the tasks finished executing or the wait timed out
    */
    public func wait(timeout: DispatchTime) -> DispatchTimeoutResult {
        var results = [DispatchTimeoutResult]()

        for (_, group) in groups {
            results.append(group.wait(timeout: timeout))
        }

        return results.reduce(.success, {
            guard $0 == .success else { return $0 }
            return $1
        })
    }
    /**
    Blocks execution until either all tasks have finished executing (including the tasks not currently running) or the timeout has been reached

    - Parameter timeout: The latest time to wait for the tasks to finish executing
    - Returns: Whether the tasks finished executing or the wait timed out
    */
    public func wait(wallTimeout timeout: DispatchWallTime) -> DispatchTimeoutResult {
        var results = [DispatchTimeoutResult]()

        for (_, group) in groups {
            results.append(group.wait(wallTimeout: timeout))
        }

        return results.reduce(.success, {
            guard $0 == .success else { return $0 }
            return $1
        })
    }

    /**
    Schedules a block to be submitted to a queue with a specified quality of service class and configuration once all of the tasks in this queue finish executing

    - Parameter:
        - qos: The quality of service class for the work to be performed
        - flags: Options for how the work is performed
        - queue: The queue to which the supplied block is submitted once all of the tasks in this queue finish executing
        - work: The work to be performed on the same dispatch queue as this TaskQueue once all of the tasks in this queue finish executing
    */
    public func notify(qos: DispatchQoS = .default, flags: DispatchWorkItemFlags = [], queue: DispatchQueue, execute work: @escaping () -> ()) {
        let group = DispatchGroup()
        queue.async(group: group, qos: qos) {
            for (_, group) in self.groups {
                group.wait()
            }
        }
        group.notify(qos: qos, flags: flags, queue: queue, execute: work)
    }
    /**
    Schedules a block to be submitted to a queue with a specified quality of service class and configuration once all of the tasks in this queue finish executing

    - Parameter:
        - work: The work to be performed on the same dispatch queue as this TaskQueue once all of the tasks in this queue finish executing
    */
    public func notify(execute work: @escaping () -> ()) {
        self.notify(qos: queue.qos, queue: queue, execute: work)
    }
    /**
    Schedules a block to be submitted to a queue with a specified quality of service class and configuration once all of the tasks in this queue finish executing

    - Parameter:
        - queue: The queue to which the supplied block is submitted once all of the tasks in this queue finish executing
        - work: The work to be performed on the same dispatch queue as this TaskQueue once all of the tasks in this queue finish executing
    */
    public func notify(queue: DispatchQueue, work: DispatchWorkItem) {
        let group = DispatchGroup()
        queue.async(group: group) {
            for (_, group) in self.groups {
                group.wait()
            }
        }
        group.notify(queue: queue, work: work)
    }
    /**
    Schedules a block to be submitted to a queue with a specified quality of service class and configuration once all of the tasks in this queue finish executing

    - Parameter:
        - work: The work to be performed on the same dispatch queue as this TaskQueue once all of the tasks in this queue finish executing
    */
    public func notify(work: DispatchWorkItem) {
        self.notify(queue: queue, work: work)
    }
}
