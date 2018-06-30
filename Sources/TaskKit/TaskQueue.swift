import Foundation
import Dispatch

// swiftlint:disable identifier_name
// swiftlint:disable file_length
// swiftlint:disable type_body_length

open class TaskQueue: Hashable {
    /// The name of the TaskQueue
    public private(set) var name: String

    public var hashValue: Int {
        return queue.label.hashValue
    }

    /// The tasks that are/have been executed
    public internal(set) var tasks: [Task] = []
    /// A semaphore to use for preventing simultaneous write access to the array
    var _tasksSemaphore = DispatchSemaphore(value: 1)

    var waiting: [Task] {
        return tasks.filter {
            switch $0.state {
            case .ready: return true
            default: return false
            }
        }
    }
    var beginning: [Task] {
        return tasks.filter {
            switch $0.state {
            case .done(let state), .currently(let state):
                switch state {
                    case .beginning, .preparing, .configuring: return true
                    default: return false
                }
            default: return false
            }
        }
    }
    var running: [Task] {
        return tasks.filter {
            switch $0.state {
            case .currently(let state):
                switch state {
                case .executing, .pausing, .cancelling: return true
                default: return false
                }
            default: return false
            }
        }
    }
    var failed: [Task] {
        return tasks.filter {
            switch $0.state {
            case .failed: return true
            default: return false
            }
        }
    }
    var succeeded: [Task] {
        return tasks.filter {
            switch $0.state {
            case .done(.executing): return true
            default: return false
            }
        }
    }
    var paused: [Task] {
        return tasks.filter {
            switch $0.state {
            case .done(.pausing): return true
            default: return false
            }
        }
    }
    var cancelled: [Task] {
        return tasks.filter {
            switch $0.state {
            case .done(.cancelling): return true
            default: return false
            }
        }
    }

    /// The number of tasks that are currently running or beginning
    var _active: Int {
        return running.count + beginning.count
    }
    /// The number of tasks that are currently running
    public var active: Int { return running.count }
    /// The total number of tasks left (excluding dependencies)
    public var remaining: Int {
        return waiting.count + running.count + beginning.count + paused.count
    }
    public var isDone: Bool {
        return remaining == 0
    }

    /// Tracks whether the DispatchQueue is currently running or if it is suspended
    var _isActive: Bool = false
    /// Whether or not the queue is currently running any tasks
    public var isRunning: Bool { return _isActive && _active > 0 }

    /// The maximum number of tasks that can run simultaneously
    public var maxSimultaneous: Int

    /// The underlying DispatchQueue used to run the tasks
    public private(set) var queue: DispatchQueue
    /// The underlying DispatchGroups that tasks are added to when running
    var _groups: [UUID: DispatchGroup] = [:]
    /// A semaphore to use for preventing simultaneous access to the _groups dictionary
    private var _groupsSemaphore = DispatchSemaphore(value: 1)

    /// When set to true, will grab the next task and begin executing it
    private var __getNext: Bool = false
    var _getNext: Bool {
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
    public init(name: String, maxSimultaneous: Int = TaskQueue.defaultMaxSimultaneous) {
        self.name = name
        self.maxSimultaneous = maxSimultaneous

        // If the queue doesn't run concurrently then this causes issues (especially with dependent tasks)
        self.queue = DispatchQueue(label: "com.taskqueue.\(UUID().description)", attributes: .concurrent)

        self.queue.suspend()
    }

    /**
    Initialize a TaskQueue

    - Parameter:
        - name: The name of the TaskQueue
        - maxSimultaneous: The maximum number of tasks that can run simultaneously
        - tasks: An array of tasks to add to the queue
    */
    public convenience init(name: String, maxSimultaneous: Int = TaskQueue.defaultMaxSimultaneous, tasks: [Task]) {
        self.init(name: name, maxSimultaneous: maxSimultaneous)
        self.add(tasks: tasks)
    }

    /**
    Initialize a TaskQueue

    - Parameter:
        - name: The name of the TaskQueue
        - maxSimultaneous: The maximum number of tasks that can run simultaneously
        - tasks: An array of tasks to add to the queue
    */
    public convenience init(name: String, maxSimultaneous: Int = TaskQueue.defaultMaxSimultaneous, tasks: Task...) {
        self.init(name: name, maxSimultaneous: maxSimultaneous)
        self.add(tasks: tasks)
    }

    /**
    Sorts the array of Tasks by priority

    - Parameter array: The array of tasks to sort in execution order
    */
    class func sort(_ array: inout [Task]) {
        array.sort { $0.priority > $1.priority }
    }

    /**
    Adds a task to the task array, then sorts the task array based on its tasks' priorities

    - Parameter task: The task to add
    */
    public func addTask(_ task: Task) {
        guard tasks.index(where: { $0.id == task.id }) == nil else { return }
        _tasksSemaphore.waitAndRun {
            tasks.append(task)
            type(of: self).sort(&tasks)
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
        let new: [Task] = tasks.compactMap { task in
            guard self.tasks.index(where: { $0.id == task.id }) == nil else { return nil }
            return task
        }
        _tasksSemaphore.waitAndRun {
            self.tasks += new
            type(of: self).sort(&self.tasks)
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

    - Returns: The task, if it was configured properly, or nil otherwise
    */
    func prepare(_ task: DependentTask) -> Task? {
        task.state = .currently(.preparing)

        var dependency: Task? = nil
        while !task.waiting.isEmpty {
            let dep = task.waiting.first!
            start(dep, autostart: false, dependent: task)
            _groups[dep.id]!.wait()

            dependency = failed.first(where: { $0.id == dep.id })
            guard dependency == nil else { break }
        }

        guard dependency == nil else {
            task.state = .dependency(dependency!)
            failed(task)
            return nil
        }

        task.state = .done(.preparing)
        return task
    }

    /**
    Configures the task before executing it

    - Parameter task: The task to configure

    - Returns: The task, if it was configured properly, or nil otherwise
    */
    private func configure(_ task: ConfigurableTask) -> Task? {
        task.state = .currently(.configuring)
        guard task.configure() else {
            failed(task)
            return nil
        }

        task.state = .done(.configuring)
        return task
    }

    /**
    Executes the task

    - Parameter task: The task to execute

    - Returns: Whether or not the task executed successfully
    */
    private func execute(_ task: Task) -> Bool {
        task.state = .running

        guard task.execute() else {
            failed(task)
            return false
        }

        task.state = .succeeded
        return true
    }

    /**
    Called when the task failed at some stage
    Sets the task to the failed state and places it in the errored dict

    - Parameter task: The task to configure
    */
    func failed(_ task: Task) {
        let state = task.state
        switch state {
        case .dependency: task.state = .failed(state)
        case .currently(let current): task.state = .failed(current)
        default:
            fatalError("We can only fail on a dependency or on states that are currently running. Something went awry and \(task) failed during a supposedly impossible state. \(state)")
        }
    }

    /// Begins execution of the next task in the waiting list
    func startNext() {
        guard _active < maxSimultaneous else { return }

        guard let upNext = waiting.first else { return }
        start(upNext)
    }

    /**
    Begins execution of the specified task and can set it to automatically start the next task once it finished

    - Parameter task: The task to start
    - Parameter autostart: Whether or not the current task should automatically start the next task in the waiting array upon completion
    */
    func start(_ task: Task, autostart: Bool = true, dependent: DependentTask? = nil) {
        task.state = .currently(.beginning)
        let group = DispatchGroup()

        _groupsSemaphore.waitAndRun {
            _groups[task.id] = group
        }

        queue.async(group: group, qos: task.qos) {
            var _task: Task?
            if let task = task as? DependentTask {
                _task = self.prepare(task)
            } else {
                _task = task
            }
            guard _task != nil else { return }

            if let task = _task as? ConfigurableTask {
                _task = self.configure(task)
                guard _task != nil else { return }
            }

            guard self.execute(_task!) else { return }
        }

        setupNotify(using: group, uniqueKey: task.id, autostart: autostart, dependent: dependent)
    }

    private func setupNotify(using group: DispatchGroup, uniqueKey: UUID, autostart: Bool, dependent: DependentTask? = nil) {
        group.notify(qos: queue.qos, queue: queue) {
            let task: Task
            if let index = self.succeeded.index(where: { $0.id == uniqueKey }) {
                task = self.succeeded[index]
            } else if let index = self.failed.index(where: { $0.id == uniqueKey }) {
                task = self.failed[index]
            } else { return }

            task.completionBlock(task.status)

            if let dependent = dependent {
                dependent.dependencyCompletionBlock(task)
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
        resumeAllTasks()

        queue.resume()
        _isActive = true
    }

    private func resumeAllTasks() {
        for task in paused {
            // Look at stopping the dispatch queue/group for other ones (or both)
            if task is PausableTask {
                let task: PausableTask! = task as? PausableTask
                task.state = .currently(.resuming)
                guard task.resume() else {
                    failed(task as Task)
                    _getNext = true
                    continue
                }
                task.state = .running
            }
        }
    }

    /// Pauses (AKA suspends) current execution of the running tasks and does not begin to run any new tasks
    public func pause() {
        pauseAllTasks()

        queue.suspend()
        _isActive = false
    }

    @available(*, renamed: "pause")
    public func suspend() { pause() }

    private func pauseAllTasks() {
        for task in running {
            // Look at stopping the dispatch queue/group for other ones (or both)
            if task is PausableTask {
                let task: PausableTask! = task as? PausableTask
                task.state = .currently(.pausing)
                guard task.pause() else {
                    failed(task as Task)
                    continue
                }
                task.state = .paused
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

        return cancelAllTasks()
    }

    private func cancelAllTasks() -> [Task] {
        var cancelled: [Task] = []
        for task in running {
            // Look at stopping the dispatch queue/group for other ones (or both)
            if task is CancellableTask {
                let task: CancellableTask! = task as? CancellableTask
                task.state = .currently(.cancelling)
                guard task.cancel() else {
                    failed(task as Task)
                    continue
                }
            }
            task.state = .cancelled
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

    public static func == (lhs: TaskQueue, rhs: TaskQueue) -> Bool {
        return lhs.queue.label == rhs.queue.label && lhs.name == rhs.name
    }
}
