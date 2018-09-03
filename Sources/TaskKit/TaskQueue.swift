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
    var _tasksQueue = DispatchQueue(label: "com.TaskKit.tasks", qos: .userInteractive, attributes: .concurrent)

    public var waiting: [Task] {
        return _tasksQueue.sync {
            return tasks.filter {
                return $0.isReady
            }
        }
    }
    var upNext: Task? {
        return _tasksQueue.sync {
            return tasks.first(where: {
                return $0.isReady
            })
        }
    }

    private static let beginningStates: [TaskState] = {
        let waiting: [TaskState] = [TaskState(rawValue: .wait | .execute)]
        let active: [TaskState] = [.prepare, .configure].map { TaskState(rawValue: $0 | TaskState.start) }
        let done: [TaskState] = [.prepare, .configure].map { TaskState(rawValue: $0 | TaskState.done) }

        return waiting + active + done
    }()
    public var beginning: [Task] {
        return _tasksQueue.sync {
            return tasks.filter {
                return TaskQueue.beginningStates.contains($0.state)
            }
        }
    }

    private static let runningStates: [TaskState] = {
        return [.execute, .pause, .cancel].map { TaskState(rawValue: $0 | TaskState.start) }
    }()
    public var running: [Task] {
        return _tasksQueue.sync {
            return tasks.filter {
                return TaskQueue.runningStates.contains($0.state)
            }
        }
    }

    public var failed: [Task] {
        return _tasksQueue.sync {
            return tasks.filter {
                return $0.didFail
            }
        }
    }

    public var succeeded: [Task] {
        return _tasksQueue.sync {
            return tasks.filter {
                $0.didSucceed
            }
        }
    }

    public var paused: [Task] {
        return _tasksQueue.sync {
            return tasks.filter {
                return $0.isPaused
            }
        }
    }

    public var cancelled: [Task] {
        return _tasksQueue.sync {
            return tasks.filter {
                return $0.wasCancelled
            }
        }
    }

    static let _activeStates: [TaskState] = {
        return TaskQueue.beginningStates + TaskQueue.runningStates
    }()
    /// The number of tasks that are currently running or beginning
    var _active: Int {
        return _tasksQueue.sync {
            return tasks.reduce(0) {
                if TaskQueue._activeStates.contains($1.state) {
                    return $0 + 1
                }

                return $0
            }
        }
    }
    /// The number of tasks that are currently running
    public var active: Int {
        return _tasksQueue.sync {
            return tasks.reduce(0) {
                return TaskQueue.runningStates.contains($1.state) ? $0 + 1 : $0
            }
        }
    }
    /// The total number of tasks left (excluding dependencies)
    public var remaining: Int {
        return _tasksQueue.sync {
            return tasks.reduce(0) {
                if $1.state.isReady {
                    return $0 + 1
                } else if TaskQueue._activeStates.contains($1.state) {
                    return $0 + 1
                }

                return $0
            }
        }
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
    var _groupsQueue = DispatchQueue(label: "com.TaskKit.groups", qos: .utility, attributes: .concurrent)

    /// When set to true, will grab the next task and begin executing it
    private var __getNext: Bool = false
    var _getNext: Bool {
        get { return __getNextQueue.sync { return __getNext } }
        set {
            if newValue {
                _getNextQueue.sync {
                    __getNextQueue.async(flags: .barrier) {
                        self.__getNext = newValue
                    }

                    if upNext != nil {
                        queue.async(qos: .userInteractive) {
                            self.startNext()
                            self._getNext = false
                        }
                    } else {
                        __getNextQueue.async(flags: .barrier) {
                            self.__getNext = false
                        }
                    }
                }
            } else if _active < maxSimultaneous {
                self._getNext = true
            } else {
                __getNextQueue.async(flags: .barrier) {
                    self.__getNext = false
                }
            }
        }
    }

    /// A semaphore to use for preventing simultaneous access to the _getNext boolean
    private var _getNextQueue = DispatchQueue(label: "com.TaskKit.next", qos: .userInitiated)
    /// A semaphore to use for preventing simultaneous access to the _getNext boolean
    private var __getNextQueue = DispatchQueue(label: "com.TaskKit._next", qos: .userInteractive, attributes: .concurrent)

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
        _tasksQueue.async(flags: .barrier) {
            self.tasks.append(task)
            type(of: self).sort(&self.tasks)
            self.queue.async(qos: .userInteractive) {
                if self._isActive && !self._getNext && self._active < self.maxSimultaneous {
                    self._getNext = true
                }
            }
        }
    }

    /**
    Adds an array of tasks to the existing task array, then sorts the task array based on its tasks' priorities

    - Parameter tasks: The tasks to add
    */
    public func addTasks(_ tasks: [Task]) {
        _tasksQueue.async(flags: .barrier) {
            self.tasks += tasks
            type(of: self).sort(&self.tasks)
            self.queue.async(qos: .userInteractive) {
                if self._isActive && !self._getNext && self._active < self.maxSimultaneous {
                    self._getNext = true
                }
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
        var dependency: Task? = nil
        while let dep = task.upNext {
            task.state.dependency()
            start(dep, autostart: false, dependent: task)
            _groupsQueue.sync { _groups[dep.id]!.wait() }

            dependency = failed.first(where: { $0.id == dep.id })
            guard dependency == nil else { break }
        }

        guard dependency == nil else {
            failed(task)
            return nil
        }

        task.state.finish()
        return task
    }

    /**
    Configures the task before executing it

    - Parameter task: The task to configure

    - Returns: The task, if it was configured properly, or nil otherwise
    */
    private func configure(_ task: ConfigurableTask) -> Task? {
        task.state.start(to: .configure)
        guard task.configure() else {
            failed(task)
            return nil
        }

        task.state.finish()
        return task
    }

    /**
    Executes the task

    - Parameter task: The task to execute

    - Returns: Whether or not the task executed successfully
    */
    private func execute(_ task: Task) -> Bool {
        task.state.start(to: .execute)

        guard task.execute() else {
            failed(task)
            return false
        }

        task.state.finish()
        return true
    }

    /**
    Called when the task failed at some stage
    Sets the task to the failed state and places it in the errored dict

    - Parameter task: The task to configure
    */
    func failed(_ task: Task) {
        precondition(task.state.isStarted || task.state.contains(.dependency))
        task.state.fail()
    }

    /// Begins execution of the next task in the waiting list
    func startNext() {
        guard _active < maxSimultaneous else { return }

        _tasksQueue.sync {
            guard let upNext = upNext else { return }
            start(upNext)
        }
    }

    /**
    Begins execution of the specified task and can set it to automatically start the next task once it finished

    - Parameter task: The task to start
    - Parameter autostart: Whether or not the current task should automatically start the next task in the waiting array upon completion
    */
    func start(_ task: Task, autostart: Bool = true, dependent: DependentTask? = nil) {
        task.state.start(to: .prepare)

        let group = DispatchGroup()

        _groupsQueue.async(flags: .barrier) {
            self._groups[task.id] = group
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

            task.finish()

            if let dependent = dependent {
                dependent.finish(dependency: task)
            }
            self._groupsQueue.async(flags: .barrier) {
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
                assert(task.isPaused)
                task.state.start(to: .resume)
                guard task.resume() else {
                    failed(task as Task)
                    _getNext = true
                    continue
                }
                task.state.start(to: .execute)
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
                assert(task.isExecuting)
                task.state.start(to: .pause)
                guard task.pause() else {
                    failed(task as Task)
                    continue
                }
                task.state.pause()
            }
        }
    }

    /**
    Cancel execution of all currently running tasks

    - Parameter pause: Whether or not to prevent execution of any remaining tasks. If true, the queue must be resumed with `.start()`
    - Returns: The tasks that were cancelled. This may be useful to verify your tasks were all successfully cancelled
    */
    @discardableResult
    public func cancel(pause: Bool = false) -> [Task] {
        if pause {
            queue.suspend()
            _isActive = false
        }

        return cancelAllTasks()
    }

    public func cancelEverything() {
        while !cancel().isEmpty {}
    }

    private func cancelAllTasks() -> [Task] {
        var cancelled: [Task] = []
        for task in running {
            // Look at stopping the dispatch queue/group for other ones (or both)
            if task is CancellableTask {
                let task: CancellableTask! = task as? CancellableTask
                assert(task.isExecuting)
                task.state.start(to: .cancel)
                guard task.cancel() else {
                    failed(task as Task)
                    continue
                }
                task.state.finish()
            }
            cancelled.append(task)
        }

        return cancelled
    }

    /// Blocks execution until all tasks have finished executing (including the tasks not currently running)
    public func wait() {
		if let (key, group) = _groupsQueue.sync(execute: { return _groups.first }) {
            _groupsQueue.async(flags: .barrier) {
                self._groups.removeValue(forKey: key)
            }
            group.wait()
            self.wait()
        }
    }
    /**
    Blocks execution until either all tasks have finished executing (including the tasks not currently running) or the timeout has been reached

    - Parameter timeout: The latest time to wait for the tasks to finish executing
    - Returns: Whether the tasks finished executing or the wait timed out
    */
    public func wait(timeout: DispatchTime) -> DispatchTimeoutResult {
        var results = [DispatchTimeoutResult]()

        for (_, group) in _groupsQueue.sync(execute: { return _groups }) {
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

        for (_, group) in _groupsQueue.sync(execute: { return _groups }) {
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
