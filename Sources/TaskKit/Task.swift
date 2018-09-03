import Dispatch
import Foundation

public protocol Task: class {
    var state: TaskState { get set }
    /// How important is it that this task be run sooner rather than later (Tasks with higher priority are executed first)
    var priority: TaskPriority { get set }
    /// The Dispatch Quality of Service the task should use to execute
    var qos: DispatchQoS { get }

    /**
    The code that will be ran when your task is performed

    - Returns: Whether or not the task finished execution successfully
    */
    func execute() -> Bool

    func finish()
}

private let _taskStateQueue = DispatchQueue(label: "com.TaskKit.task.state", qos: .userInteractive, attributes: .concurrent)

public extension Task {
    public var isReady: Bool { return state.isReady }
    public var isExecuting: Bool { return state.isExecuting }
    public var isWaiting: Bool { return state.isWaiting }
    public var isPaused: Bool { return state.isPaused }
    public var wasCancelled: Bool { return state.wasCancelled }
    public var didSucceed: Bool { return state.didSucceed }
    public var didFail: Bool { return state.didFail }

    var id: UUID { return state.id }

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
    func finish(dependency: Task)
}

public extension DependentTask {
    public func add(dependency task: Task) {
        dependencies.append(task)
    }

    var incompleteDependencies: [Task] {
        return dependencies.filter {
            return !$0.state.didSucceed
        }
    }
    var upNext: Task? {
        return dependencies.first(where: {
            return !$0.state.didSucceed && !$0.state.didFail
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
