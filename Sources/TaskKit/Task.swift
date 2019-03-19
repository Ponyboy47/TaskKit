/// A Type that performs work on a TaskQueue
public protocol Task: class, Codable {
    var priority: TaskPriority { get }
    var state: TaskState { get set }
    func execute() -> Bool
}

/// A Task that can be paused and resumed
public protocol PausableTask: Task {
    func pause() -> Bool
    func resume() -> Bool
}

/// A Task that can track its progress on a scale from 0.0 to 1.0
public protocol ProgressableTask: Task {
    var progress: Double { get }
}

// I don't care how you store/add your dependencies, just how I retrieve them
/// A Task that depends on other tasks
public protocol DependentTask: Task {
    func nextDependency() -> Task?
}

/**
How important a Task is. Higher priorities generally mean that a task is more
likely to be executed sooner
**/
public enum TaskPriority: RawRepresentable, ExpressibleByIntegerLiteral, Hashable, Comparable, Codable {
    public typealias RawValue = UInt8
    public typealias IntegerLiteralType = RawValue

    public var rawValue: RawValue {
        switch self {
        case .unimportant: return 0
        case .low: return 64
        case .medium: return 128
        case .high: return 192
        case .critical: return 255
        case .custom(let value): return value
        }
    }

    /// It doesn't matter when the task is ran and so it will always be picked last
    case unimportant
    /// The task is of minor importance. Executing it can be deferred for a while, but not forever
    case low
    /// The task is neither important nor worthless. Its right in the middle of the road
    case medium
    /// The task is very important and will be executed before most other tasks
    case high
    /// The task performs something of the utmost importance. These tasks will be executed first
    case critical
    /// Your task doesn't fall into the predefined categories so you can place it in between any of the other ones
    case custom(UInt8)

    public static let `default`: TaskPriority = .medium

    public init(rawValue: RawValue) {
        switch rawValue {
        case 0: self = .unimportant
        case 64: self = .low
        case 128: self = .medium
        case 192: self = .high
        case 255: self = .critical
        default: self = .custom(rawValue)
        }
    }

    public init(integerLiteral value: IntegerLiteralType) {
        self.init(rawValue: value)
    }

    public static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

/**
The current state of your task. Tasks will only be executed if they are in the
ready state. Upon completion, a task will be in either the succeeded or failed
states
**/
public enum TaskState: Int8, Hashable, Codable {
    /// The task is not ready to execute
    case notReady
    /// The task is prepared for execution
    case ready
    /// The task is currently executing
    case executing
    /// The task has been paused
    case paused
    /// The task was cancelled
    case cancelled
    /// The task completed its execution successfully
    case succeeded
    /// The task failed to execute to completion
    case failed
}
