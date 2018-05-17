import Dispatch

public protocol Task {
    /// The current execution status of the task
    var status: TaskStatus { get set }
    /// How important is it that this task be run sooner rather than later (Tasks with higher priority are executed first)
    /// The default implementation uses the minimal priority.
    var priority: TaskPriority { get }
    /// The Dispatch Quality of Service the task should use to execute
    var qos: DispatchQoS { get }
    /// A block to execute once the task finishes
    var completionBlock: (TaskStatus) -> () { get }

    /**
    The code that will be ran when your task is performed

    - Returns: Whether or not the task finished execution successfully
    */
    func execute() -> Bool
    func main() -> Bool

    /**
    This is run after the task completes its execution. Any clean up code should go here

    - Returns: Whether or not the task cleaned up properly
    */
    func finish() -> Bool
}

public extension Task {
    @available(*, renamed: "execute")
    public func main() -> Bool { return execute() }
}

public protocol ConfigurableTask: Task {
    /**
    Configures the task to be run

    - Returns: Whether or not the task was configured properly
    */
    mutating func configure() -> Bool
}

public protocol PausableTask: Task {
    /**
    Used to resume execution of your paused task

    - Returns: Whether or not the task was successfully resumed
    */
    func resume() -> Bool

    /**
    Used to pause execution of your task mid-run

    - Returns: Whether or not the task was successfully paused
    */
    func pause() -> Bool
}

public protocol CancellableTask: Task {
    /**
    Used to cancel execution of your task mid-run

    - Returns: Whether or not the task was successfully cancelled
    */
    func cancel() -> Bool
}

public protocol DependentTask: Task {
    /// The tasks that must complete successfully before this task can run
    var dependencies: [Task] { get set }
}

public extension DependentTask {
    public mutating func addDependency(_ task: Task) {
        dependencies.append(task)
    }

    public mutating func add(dependency task: Task) {
        dependencies.append(task)
    }
}
