public enum TaskState: CustomStringConvertible {
    case ready
    case configuring
    case executing
    case finishing
    case cancelling
    case resuming
    case pausing
    indirect case done(TaskState)
    indirect case currently(TaskState)
    indirect case dependency(Task)
    indirect case failed(TaskState)

    public static let running: TaskState = .currently(.executing)
    public static let paused: TaskState = .done(.pausing)
    public static let cancelled: TaskState = .done(.cancelling)
    public static let succeeded: TaskState = .done(.finishing)

    public var description: String {
        switch self {
        case .ready: return "ready"
        case .configuring: return "configuring"
        case .executing: return "executing"
        case .finishing: return "finishing"
        case .cancelling: return "cancelling"
        case .resuming: return "resuming"
        case .pausing: return "pausing"
        case .done(let state): return "done(\(state))"
        case .currently(let state): return "currently(\(state))"
        case .failed(let state): return "failed(\(state))"
        case .dependency(let task): return "dependency(\(task), state: \(task.status.state))"
        }
    }
}
