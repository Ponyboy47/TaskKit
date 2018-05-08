public class TaskStatus {
    public internal(set) var state: TaskState
    public private(set) var messages: [String] = []

    public static let ready = TaskStatus(.ready)

    public init(_ state: TaskState) {
        self.state = state
    }

    public func append(_ message: String) {
        messages.append(message)
    }
}
