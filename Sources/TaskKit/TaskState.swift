public enum TaskState: CustomStringConvertible {
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
}
