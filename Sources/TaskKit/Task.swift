import Dispatch
import Foundation

public protocol Task: class {
    /// The current execution status of the task
    var status: TaskStatus { get }
    /// How important is it that this task be run sooner rather than later (Tasks with higher priority are executed first)
    var priority: TaskPriority { get set }
    /// The Dispatch Quality of Service the task should use to execute
    var qos: DispatchQoS { get }
    /// A block to execute once the task finishes
    var completionBlock: (TaskStatus) -> Void { get }

    /**
    The code that will be ran when your task is performed

    - Returns: Whether or not the task finished execution successfully
    */
    func execute() -> Bool
    func main() -> Bool
}

private let _taskStateQueue = DispatchQueue(label: "com.TaskKit.task.state", qos: .userInteractive, attributes: .concurrent)

public extension Task {
    public var id: UUID { return status.id }
    public var state: TaskState {
        get { return _taskStateQueue.sync { return status.state } }
        set { _taskStateQueue.async(flags: .barrier) { self.status.state = newValue } }
    }

    /**
    Appends a new log message to the status

    - Parameter message: The message to add
    */
    public func append(_ message: String) {
        status.append(message)
    }

    /**
    Splits the message based on a delimeter and appends the array of messages to the messages array

    - Parameter message: The message to split and add
    */
    public func append(_ message: String, separatedBy delimeter: String) {
        status.append(message, separatedBy: delimeter)
    }

    /**
    Appends an array of messages to the messages array

    - Parameter message: The messages to add
    */
    public func append(_ messages: [String]) {
        status.append(messages)
    }

    /**
    Appends a variadic of messages to the messages array

    - Parameter message: The messages to add
    */
    public func append(_ messages: String...) {
        status.append(messages)
    }

    @available(*, renamed: "execute")
    public func main() -> Bool { return execute() }
}

public protocol ConfigurableTask: Task {
    /**
    Configures the task to be run

    - Returns: Whether or not the task was configured properly
    */
    func configure() -> Bool
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

    /// A block that will be executed when each dependency finishes executing
    var dependencyCompletionBlock: (Task) -> Void { get }
}

public extension DependentTask {
    public func addDependency(_ task: Task) {
        dependencies.append(task)
    }

    public func add(dependency task: Task) {
        dependencies.append(task)
    }

    public var incompleteDependencies: [Task] {
        return dependencies.filter {
            return $0.state != .succeeded
        }
    }
    var upNext: Task? {
        return dependencies.first(where: {
            return $0.state != .succeeded
        })
    }
}

public struct DependentTaskOption: OptionSet {
    public let rawValue: UInt8

    public static let increaseDependencyPriority = DependentTaskOption(rawValue: 1 << 0)
    public static let decreaseDependentTaskPriority = DependentTaskOption(rawValue: 1 << 1)

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }
}
