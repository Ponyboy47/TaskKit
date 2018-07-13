public enum TaskState: CustomStringConvertible, Equatable, Comparable {
    private var rawValue: UInt16 {
        switch self {
        case .failed(let state): return state.rawValue << 1
        case .dependency(let task): return task.state.rawValue << 2
        case .currently(let state): return state.rawValue << 4
        case .done(let state): return state.rawValue << 8
        case .cancelling: return 1
        case .ready: return 2
        case .pausing: return 3
        case .beginning: return 4
        case .preparing: return 5
        case .waiting: return 6
        case .configuring: return 7
        case .resuming: return 8
        case .executing: return 9
        }
    }

    case ready
    case beginning
    case preparing
    case configuring
    case executing
    case cancelling
    case resuming
    case pausing
    case waiting
    indirect case done(TaskState)
    indirect case currently(TaskState)
    indirect case dependency(Task)
    indirect case failed(TaskState)

    public static let running: TaskState = .currently(.executing)
    public static let paused: TaskState = .done(.pausing)
    public static let cancelled: TaskState = .done(.cancelling)
    public static let succeeded: TaskState = .done(.executing)
    public static let prepared: TaskState = .done(.preparing)
    public static let configured: TaskState = .done(.configuring)
    public static let waited: TaskState = .done(.waiting)

    public var description: String {
        switch self {
        case .ready: return "ready"
        case .beginning: return "beginning"
        case .preparing: return "preparing"
        case .configuring: return "configuring"
        case .executing: return "executing"
        case .cancelling: return "cancelling"
        case .resuming: return "resuming"
        case .pausing: return "pausing"
        case .waiting: return "waiting"
        case .currently(.executing): return "running"
        case .currently(let state): return "currently(\(state))"
        case .done(.executing): return "succeeded"
        case .done(let state): return "done(\(state))"
        case .failed(let state): return "failed(\(state))"
        case .dependency(let task): return "dependency(\(task), state: \(task.status.state))"
        }
    }

    public static func == (lhs: TaskState, rhs: TaskState) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }

    public static func < (lhs: TaskState, rhs: TaskState) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}
