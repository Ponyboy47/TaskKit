import Foundation
import Dispatch

// swiftlint:disable identifier_name
// swiftlint:disable file_length
// swiftlint:disable type_body_length

open class TaskQueue {
    /// The name of the TaskQueue
    public private(set) var name: String

    /// The tasks that are waiting to be run
    public private(set) var waiting: [Task] = []
    /// A semaphore to use for preventing simultaneous access to the waiting array
    private var _waitingSemaphore = DispatchSemaphore(value: 1)

    /// The tasks that are currently beginning
    private var _beginning: [UUID: Task] = [:]
    /// A semaphore to use for preventing simultaneous access to the beginning array
    private var _beginningSemaphore = DispatchSemaphore(value: 1)

    /// The tasks that are currently running
    public private(set) var running: [UUID: Task] = [:]
    /// A semaphore to use for preventing simultaneous access to the running array
    private var _runningSemaphore = DispatchSemaphore(value: 1)

    /// The tasks that did not transition safely from one state to the next
    public var errored: [Task] { return _errored.map { $0.value } }
    /// Internally used to validate task dependencies completed successfully
    public private(set) var _errored: [UUID: Task] = [:]
    /// A semaphore to use for preventing simultaneous access to the _errored array
    private var _erroredSemaphore = DispatchSemaphore(value: 1)

    /// The waiting tasks that may have _dependencies
    private var _dependents: [DependentTask] {
        let _dependents = waiting.compactMap {
            return $0 as? DependentTask
        }
        return _dependents.map { dependentTasks(of: $0) }.flatMap { $0 }
    }
    private func dependentTasks(of task: DependentTask) -> [DependentTask] {
        return task.dependencies.compactMap {
            return $0 as? DependentTask
        }
    }

    /// The count of waiting task _dependencies
    private var _dependencies: Int {
        return _dependents.reduce(0, { return $0 + $1.dependencies.count })
    }

    /// The number of tasks that are currently running or beginning
    private var _active: Int { return active + _beginning.count }
    /// The number of tasks that are currently running
    public var active: Int { return running.count }
    /// The total number of tasks left (including the currently running tasks)
    public var count: Int {
        return waiting.count + _dependencies + _active
    }
    /// Whether or not there are any tasks still executing or waiting to be executed
    public var isEmpty: Bool {
        return count == 0
    }

    /// Tracks whether the DispatchQueue is currently running or if it is suspended
    private var _isActive: Bool = false
    /// Whether or not the queue is currently running any tasks
    public var isRunning: Bool { return _isActive && _active > 0 }

    /// The maximum number of tasks that can run simultaneously
    public var maxSimultaneous: Int

    /// The underlying DispatchQueue used to run the tasks
    public private(set) var queue: DispatchQueue
    /// The underlying DispatchGroups that tasks are added to when running
    private var _groups: [UUID: DispatchGroup] = [:]
    /// A semaphore to use for preventing simultaneous access to the _groups dictionary
    private var _groupsSemaphore = DispatchSemaphore(value: 1)

    /// When set to true, will grab the next task and begin executing it
    private var __getNext: Bool = false
    private var _getNext: Bool {
        get { return __getNext }
        set {
            if newValue {
                _getNextSemaphore.wait()
                __getNext = newValue

                if !waiting.isEmpty {
                    queue.async(qos: .background) {
                        self.startNext()
                        self._getNext = false
                    }
                } else {
                    __getNext = false
                }

                _getNextSemaphore.signal()
            } else if _active < maxSimultaneous {
                self._getNext = true
            }
        }
    }

    /// A semaphore to use for preventing simultaneous access to the _getNext boolean
    private var _getNextSemaphore = DispatchSemaphore(value: 1)

    /// The default number of tasks that can run simultaneously
    public static let defaultMaxSimultaneous: Int = 1

    /**
    Initialize a TaskQueue

    - Parameter:
        - name: The name of the TaskQueue
        - maxSimultaneous: The maximum number of tasks that can run simultaneously
    */
    public init(_ name: String, maxSimultaneous: Int = TaskQueue.defaultMaxSimultaneous) {
        self.name = name
        self.maxSimultaneous = maxSimultaneous

        // If the queue doesn't run concurrently then this causes issues (especially with dependent tasks)
        self.queue = DispatchQueue(label: "com.taskqueue.\(UUID().description)", attributes: .concurrent)

        self.queue.suspend()
    }

    /**
    Adds a task to the task array, then sorts the task array based on its tasks' priorities

    - Parameter task: The task to add
    */
    public func addTask(_ task: Task) {
        _waitingSemaphore.waitAndRun {
            waiting.append(task)
            waiting.sort(by: { $0.priority.rawValue > $1.priority.rawValue })
        }
        if _isActive && !_getNext && _active < maxSimultaneous {
            queue.async(qos: .background) {
                self._getNext = true
            }
        }
    }

    /**
    Adds an array of tasks to the existing task array, then sorts the task array based on its tasks' priorities

    - Parameter tasks: The tasks to add
    */
    public func addTasks(_ tasks: [Task]) {
        _waitingSemaphore.waitAndRun {
            waiting += tasks
            waiting.sort(by: { $0.priority.rawValue > $1.priority.rawValue })
        }
        if _isActive && !_getNext && _active < maxSimultaneous {
            queue.async(qos: .background) {
                self._getNext = true
            }
        }
    }

    /**
    Adds a variadic array of tasks to the existing task array, then sorts the task array based on its tasks' priorities

    - Parameter tasks: The tasks to add
    */
    public func addTasks(_ tasks: Task...) {
        addTasks(tasks)
    }

    /**
    Adds a task to the task array, then sorts the task array based on its tasks' priorities

    - Parameter task: The task to add
    */
    public func add(task: Task) {
        addTask(task)
    }

    /**
    Adds an array of tasks to the existing task array, then sorts the task array based on its tasks' priorities

    - Parameter tasks: The tasks to add
    */
    public func add(tasks: [Task]) {
        addTasks(tasks)
    }

    /**
    Adds a variadic array of tasks to the existing task array, then sorts the task array based on its tasks' priorities

    - Parameter tasks: The tasks to add
    */
    public func add(tasks: Task...) {
        addTasks(tasks)
    }

    /// Begin executing the tasks in the waiting array
    public func start() {
        // No need to start if we're already running
        guard !isRunning else { return }

        // Make sure that once we leave this function we resume the queue and set the _isActive variable
        defer {
            queue.resume()
            _isActive = true
        }

        // This should trigger startNext until there are maxSimultaneous tasks running
        _getNext = true
    }

    /**
    Prepares to execute the task by ensuring all dependencies are run and that
    it is in the ready state

    - Parameter task: The task to prepare
    - Parameter taskKey: The unique key used to track the task

    - Returns: The task, if it was configured properly, or nil otherwise
    */
    private func prepare(_ task: DependentTask, with taskKey: UUID) -> Task? {
        var task = task

        var dependency: Task? = nil
        while !task.dependencies.isEmpty {
            let dep = task.dependencies.removeFirst()

            let depKey = start(dep, autostart: false, dependent: task)
            _groups[depKey]!.wait()

            dependency = _errored[depKey]
            guard dependency == nil else { break }
        }

        guard task.dependencies.isEmpty && dependency == nil else {
            task.status.state = .dependency(dependency!)
            failed(task, with: taskKey)
            return nil
        }
        return prepare(task as Task, with: taskKey)
    }

    /**
    Prepares to execute the task by ensuring it is in the ready state

    - Parameter task: The task to prepare
    - Parameter taskKey: The unique key used to track the task

    - Returns: The task, if it was configured properly, or nil otherwise
    */
    private func prepare(_ task: Task, with taskKey: UUID) -> Task? {
        switch task.status.state {
        case .ready:
            task.status.state = .done(.configuring)
        default:
            failed(task, with: taskKey)
            return nil
        }

        return task
    }

    /**
    Configures the task before executing it

    - Parameter task: The task to configure
    - Parameter taskKey: The unique key used to track the task

    - Returns: The task, if it was configured properly, or nil otherwise
    */
    private func configure(_ task: ConfigurableTask, with taskKey: UUID) -> Task? {
        var task = task
        task.status.state = .currently(.configuring)
        guard task.configure() else {
            failed(task, with: taskKey)
            return nil
        }

        task.status.state = .done(.configuring)
        return task
    }

    /**
    Executes the task

    - Parameter task: The task to configure
    - Parameter taskKey: The unique key used to track the task

    - Returns: Whether or not the task executed successfully
    */
    private func execute(_ task: Task, with taskKey: UUID) -> Bool {
        _runningSemaphore.waitAndRun {
            _beginningSemaphore.waitAndRun {
                _beginning.removeValue(forKey: taskKey)
            }
            running[taskKey] = task
            running[taskKey]!.status.state = .running
        }
        print("Running \(_active) tasks")

        guard running[taskKey]!.execute() else {
            _runningSemaphore.waitAndRun {
                let task: Task! = running.removeValue(forKey: taskKey)
                failed(task, with: taskKey)
            }

            return false
        }

        running[taskKey]!.status.state = .done(.executing)
        return true
    }

    /**
    Called when the task failed at some stage
    Sets the task to the failed state and places it in the errored dict

    - Parameter task: The task to configure
    - Parameter taskKey: The unique key used to track the task
    */
    private func failed(_ task: Task, with taskKey: UUID) {
        var task = task
        switch task.status.state {
        case .dependency, .currently: task.status.state = .failed(task.status.state)
        default:
            fatalError("We can only fail on a dependency or on states that are currently running. Something went awry and we failed during a supposedly impossible state. \(task.status.state)")
        }

        _erroredSemaphore.waitAndRun {
            _errored[taskKey] = task
        }
    }

    /// Begins execution of the next task in the waiting list
    private func startNext() {
        guard _active < maxSimultaneous else { return }

        _waitingSemaphore.waitAndRun {
            guard let upNext = waiting.first else { return }
            waiting.removeFirst()
            start(upNext)
        }
    }

    /**
    Begins execution of the specified task and can set it to automatically start the next task once it finished

    - Parameter task: The task to start
    - Parameter autostart: Whether or not the current task should automatically start the next task in the waiting array upon completion

    - Returns: The UUID used to track the task
    */
    @discardableResult
    private func start(_ task: Task, autostart: Bool = true, dependent: DependentTask? = nil) -> UUID {
        let group = DispatchGroup()
        let uniqueKey = UUID()

        _groupsSemaphore.waitAndRun {
            _groups[uniqueKey] = group
        }

        _beginningSemaphore.waitAndRun {
            _beginning[uniqueKey] = task
        }

        queue.async(group: group, qos: task.qos) {
            var _task: Task?
            if task is DependentTask {
                _task = self.prepare(task as! DependentTask, with: uniqueKey)
            } else {
                _task = self.prepare(task, with: uniqueKey)
            }
            guard _task != nil else { return }

            if task is ConfigurableTask {
                _task = self.configure(_task as! ConfigurableTask, with: uniqueKey)
                guard _task != nil else { return }
            }

            guard self.execute(_task!, with: uniqueKey) else { return }
        }

        setupNotify(using: group, with: uniqueKey, autostart: autostart, dependent: dependent)

        return uniqueKey
    }

    private func setupNotify(using group: DispatchGroup, with uniqueKey: UUID, autostart: Bool, dependent: DependentTask? = nil) {
        group.notify(qos: queue.qos, queue: queue) {
            self._runningSemaphore.waitAndRun {
                let task: Task
                if self.running[uniqueKey] != nil {
                    task = self.running.removeValue(forKey: uniqueKey)!
                } else {
                    task = self._errored[uniqueKey]!
                }

                task.completionBlock(task.status)

                if let dependent = dependent {
                    dependent.dependencyCompletionBlock(task)
                }
            }
            self._groupsSemaphore.waitAndRun {
                self._groups.removeValue(forKey: uniqueKey)
            }

            if autostart {
                self._getNext = true
            }
        }
    }

    /// Resumes execution of the running tasks
    public func resume() {
        _runningSemaphore.waitAndRun {
            resumeAllTasks()
        }

        queue.resume()
        _isActive = true
    }

    private func resumeAllTasks() {
        for (key, _) in running {
            let task = running[key]

            // Look at stopping the dispatch queue/group for other ones (or both)
            if task is PausableTask {
                let task: PausableTask! = task as? PausableTask
                running[key]!.status.state = .currently(.resuming)
                guard task.resume() else {
                    let fail: Task! = running.removeValue(forKey: key)
                    failed(fail, with: key)
                    _getNext = true
                    continue
                }
                running[key]!.status.state = .currently(.executing)
            }
        }
    }

    /// Pauses (AKA suspends) current execution of the running tasks and does not begin to run any new tasks
    public func pause() {
        _runningSemaphore.waitAndRun {
            pauseAllTasks()
        }

        queue.suspend()
        _isActive = false
    }

    @available(*, renamed: "pause")
    public func suspend() { pause() }

    private func pauseAllTasks() {
        for (key, _) in running {
            let task = running[key]

            // Look at stopping the dispatch queue/group for other ones (or both)
            if task is PausableTask {
                let task: PausableTask! = task as? PausableTask
                running[key]!.status.state = .currently(.pausing)
                guard task.pause() else {
                    let fail: Task! = running.removeValue(forKey: key)
                    failed(fail, with: key)
                    continue
                }
                running[key]!.status.state = .paused
            }
        }
    }

    /**
    Cancel execution of all currently running tasks and prevents new tasks from being executed
    After cancelling, you need to restart the queue with the .start() method

    - Returns: The tasks that were cancelled. This may be useful to verify your tasks were all successfully cancelled
    */
    @discardableResult
    public func cancel() -> [Task] {
        queue.suspend()
        _isActive = false

        var cancelled: [Task] = []
        _runningSemaphore.waitAndRun {
            cancelled = cancelAllTasks()
        }
        return cancelled
    }

    private func cancelAllTasks() -> [Task] {
        var cancelled: [Task] = []
        for (key, _) in running {
            var task: Task! = running.removeValue(forKey: key)

            // Look at stopping the dispatch queue/group for other ones (or both)
            if task is CancellableTask {
                var task: CancellableTask! = task as? CancellableTask
                task.status.state = .currently(.cancelling)
                guard task.cancel() else {
                    failed(task, with: key)
                    continue
                }
            }
            task.status.state = .cancelled
            cancelled.append(task)
        }

        return cancelled
    }

    /// Blocks execution until all tasks have finished executing (including the tasks not currently running)
    public func wait() {
        while !_groups.isEmpty {
            var group: DispatchGroup!
            _groupsSemaphore.waitAndRun {
                let (key, g) = _groups.first!
                _groups.removeValue(forKey: key)
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

        for (_, group) in _groups {
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

        for (_, group) in _groups {
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
    public func notify(qos: DispatchQoS = .default, flags: DispatchWorkItemFlags = [], queue: DispatchQueue, execute work: @escaping () -> Void) {
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
    public func notify(execute work: @escaping () -> Void) {
        notify(qos: queue.qos, queue: queue, execute: work)
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
        notify(queue: queue, work: work)
    }
}
