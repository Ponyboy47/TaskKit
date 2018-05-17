public class TaskStatus {
    /// The current state of the task
    public internal(set) var state: TaskState
    /// An array of log messages from the task's execution
    public private(set) var messages: [String] = []

    public static let ready = TaskStatus(.ready)

    public init(_ state: TaskState) {
        self.state = state
    }

    /**
    Appends a new log message to the status

    - Parameter message: The message to add
    */
    public func append(_ message: String) {
        messages.append(message)
    }
}
