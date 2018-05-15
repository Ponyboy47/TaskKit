public enum TaskState {
    case ready
    case configured
    case executing
    case succeeded
    case finished
    case cancelled
    case resumed
    case paused
    indirect case dependency(Task)
    indirect case failed(TaskState)
}
