public enum TaskState {
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
}
