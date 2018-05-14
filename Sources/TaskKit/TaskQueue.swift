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
    public private(set) var running: [UUID: Task] = [:]
    /// A semaphore to use for preventing simultaneous access to the running array
    private var runningSemaphore = DispatchSemaphore(value: 1)

    /// The tasks that did not transition safely from one state to the next
    public private(set) var errored: [Task] = []
    /// A semaphore to use for preventing simultaneous access to the errored array
    private var erroredSemaphore = DispatchSemaphore(value: 1)

    /// The running tasks that may be cancelled
    private var pausables: [PausableTask] {
        return running.compactMap() {
            return $0.value as? PausableTask
        }
    }

    /// The running tasks that may be cancelled
    private var cancellables: [CancellableTask] {
        return running.compactMap() {
            return $0.value as? CancellableTask
        }
    }

    /// The waiting tasks that may have dependencies
    private var dependents: [DependentTask] {
        var dependents = waiting.compactMap() {
            return $0 as? DependentTask
        }
        return dependents.map { dependentTasks(of: $0) }.flatMap { $0 }
    }
    private func dependentTasks(of task: DependentTask) -> [DependentTask] {
        return task.dependencies.compactMap() {
            return $0 as? DependentTask
        }
    }

    /// The count of waiting task dependencies
    private var dependencies: Int {
        return dependents.reduce(0, { return $0 + $1.dependencies.count })
    }

    /// The number of tasks that are currently running
    public var active: Int { return running.count }
    /// The total number of tasks left (including the currently running tasks)
    public var count: Int {
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
    private var groups: [UUID: DispatchGroup] = [:]
    /// A semaphore to use for preventing simultaneous access to the groups dictionary
    private var groupSemaphore = DispatchSemaphore(value: 1)

    /// When set to true, will grab the next task and begin executing it
    private var _getNext: Bool = false
    private var getNext: Bool {
        get { return _getNext }
        set {
            getNextSemaphore.waitAndRun() {
                _getNext = newValue
            }
            if newValue {
                self.nextSemaphore.waitAndRun() {
                    self.startNext()
                }
                self.getNext = false
            } else if active < maxSimultaneous {
                self.getNext = true
            }
        }
    }
    /// A semaphore to use for preventing simultaneous access to the getNext boolean
    private var getNextSemaphore = DispatchSemaphore(value: 1)
    /// A semaphore to use for preventing simultaneous access to the startNext function
    private var nextSemaphore = DispatchSemaphore(value: 1)

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
            self.queue = DispatchQueue(label: "com.taskqueue.\(UUID().description)", attributes: .concurrent)
        } else {
            self.queue = DispatchQueue(label: "com.taskqueue.\(UUID().description)")
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
        waitingSemaphore.waitAndRun() {
            waiting.append(task)
            waiting.sort(by: { $0.priority.rawValue > $1.priority.rawValue })
        }
    }

    /**
    Adds an array of tasks to the existing task array, then sorts the task array based on its tasks' priorities

    - Parameter tasks: The tasks to add
    */
    public func addTasks(_ tasks: [Task]) {
        waitingSemaphore.waitAndRun() {
            waiting += tasks
            waiting.sort(by: { $0.priority.rawValue > $1.priority.rawValue })
        }
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

        // This should trigger startNext until there are maxSimultaneous tasks running
        getNext = true
    }

    /**
    Prepares to execute the task by ensuring all dependencies are run and that
    it is in the ready state and sucessfully configures itself

    - Parameter task: The task to prepare

    - Returns: Whether or not the task was successfully prepared for execution
    */
    private func prepare(_ task: inout Task) -> Bool {
        if (task is DependentTask) {
            var task: DependentTask! = task as? DependentTask

            var dependency: Task? = nil
            while !task.dependencies.isEmpty {
                dependency = task.dependencies.removeFirst()

                guard prepare(&dependency!) else { break }

                let uniqueKey = UUID()
                guard execute(dependency!, uniqueKey) else { break }
                guard finish(uniqueKey) else { break }
                dependency = nil
            }

            guard task.dependencies.isEmpty && dependency == nil else {
                task.status.state = .failed(.dependency(dependency!))
                failed(task)
                return false
            }
        }

        switch task.status.state {
        case .ready: 
            guard task.configure() else {
                task.status.state = .failed(.configured)
                failed(task)
                return false
            }
        default:
            task.status.state = .failed(.configured)
            failed(task)
            return false
        }

        task.status.state = .configured
        return true
    }

    private func execute(_ task: Task, _ runningKey: UUID) -> Bool {
        runningSemaphore.waitAndRun() {
            running[runningKey] = task
            running[runningKey]!.status.state = .executing
        }

        if running[runningKey]!.execute() {
            return true
        }

        runningSemaphore.waitAndRun() {
            var task: Task! = running.removeValue(forKey: runningKey)
            task.status.state = .failed(.executing)
            failed(task)
        }

        return false
    }

    private func finish(_ runningKey: UUID) -> Bool {
        var returnVal: Bool = false
        runningSemaphore.waitAndRun() {
            var task: Task! = running.removeValue(forKey: runningKey)

            if task.finish() {
                returnVal = true
            }

            task.status.state = .failed(.finished)
            failed(task)

            returnVal = false
        }
        return returnVal
    }

    private func failed(_ task: Task) {
        erroredSemaphore.waitAndRun() {
            errored.append(task)
        }
    }

    /// Begins execution of the next task in the waiting list
    private func startNext() {
        guard active < maxSimultaneous else { return }

        waitingSemaphore.waitAndRun() {
            var next = self.waiting.removeFirst()

            let group = DispatchGroup()
            let uniqueKey = UUID()

            self.groupSemaphore.waitAndRun() {
                self.groups[uniqueKey] = group
            }

            self.queue.async(group: group, qos: next.qos) {
                guard self.prepare(&next) else { return }

                let uniqueKey = UUID()

                guard self.execute(next, uniqueKey) else { return }
                guard self.finish(uniqueKey) else { return }
            }

            group.notify(qos: self.queue.qos, queue: self.queue) {
                self.groupSemaphore.waitAndRun() {
                    self.groups.removeValue(forKey: uniqueKey)
                }

                self.getNext = true
            }
        }
    }

    @available(*, renamed: "start")
    public func resume() { self.start() }

    /// Pauses (AKA suspends) current execution of the running tasks and does not begin to run any new tasks
    public func pause() {
        runningSemaphore.waitAndRun() {
            self.pauseAllTasks()
        }

        queue.suspend()
        isActive = false
    }

    @available(*, renamed: "pause")
    public func suspend() { self.pause() }

    private func pauseAllTasks() {
        for (key, _) in running {
            let task = running[key]

            // Look at stopping the dispatch queue/group for other ones (or both)
            if (task is PausableTask) {
                let task: PausableTask! = task as? PausableTask
                guard task.pause() else {
                    var fail: Task! = running.removeValue(forKey: key)
                    fail.status.state = .failed(.paused)
                    failed(fail)
                    continue
                }
            }
        }
    }

    /// Cancel execution of all currently running tasks
    public func cancel() {
        runningSemaphore.waitAndRun() {
            self.cancelAllTasks()
        }

        queue.suspend()
        isActive = false
    }

    private func cancelAllTasks() {
        for (key, _) in running {
            let task: Task! = running.removeValue(forKey: key)

            // Look at stopping the dispatch queue/group for other ones (or both)
            if (task is CancellableTask) {
                var task: CancellableTask! = task as? CancellableTask
                guard task.cancel() else {
                    task.status.state = .failed(.cancelled)
                    failed(task)
                    continue
                }
            }
        }
    }

    /// Blocks execution until all tasks have finished executing (including the tasks not currently running)
    public func wait() {
        while !groups.isEmpty {
            var group: DispatchGroup!
            groupSemaphore.waitAndRun() {
                let (key, g) = groups.first!
                groups.removeValue(forKey: key)
                group = g
            }
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
            self.wait()
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
            self.wait()
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
