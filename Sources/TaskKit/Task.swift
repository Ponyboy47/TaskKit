import Dispatch

public protocol Task {
    var status: TaskStatus { get set }
    var priority: TaskPriority { get }
    var qos: DispatchQoS { get }

    mutating func configure()

    func execute()
    func main()

    func finish()
}

public extension Task {
    public mutating func configure() {}

    @available(*, renamed: "execute")
    public func main() { execute() }

    public func finish() {}
}

public protocol PausableTask: Task {
    func pause()
}

public protocol CancellableTask: Task {
    func cancel()
}
