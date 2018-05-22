public class TaskStatus {
    /// The current state of the task
    public internal(set) var state: TaskState
    /// An array of log messages from the task's execution
    public private(set) var messages: [String] = []

    public static var ready: TaskStatus { return TaskStatus(.ready) }

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

    /**
    Splits the message based on a delimeter and appends the array of messages to the messages array

    - Parameter message: The message to split and add
    */
    public func append(_ message: String, separatedBy delimeter: String) {
        messages.append(contentsOf: message.components(separatedBy: delimeter))
    }

    /**
    Appends an array of messages to the messages array

    - Parameter message: The messages to add
    */
    public func append(_ messages: [String]) {
        self.messages.append(contentsOf: messages)
    }

    /**
    Appends a variadic of messages to the messages array

    - Parameter message: The messages to add
    */
    public func append(_ messages: String...) {
        self.messages.append(contentsOf: messages)
    }
}
