public protocol Task: class {
    var priority: TaskPriority { get }
    var state: TaskState { get set }
    var dependencies: [Task] { get }
    func execute() -> Bool
}

extension Task {
    var priority: TaskPriority { return .default }
    var dependencies: [Task] { return [] }
}

public enum TaskPriority: RawRepresentable, Hashable, Comparable {
    public typealias RawValue = UInt8

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

    case unimportant
    case low
    case medium
    case high
    case critical
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

    public static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

public enum TaskState: Hashable {
    case ready
    case executing
    case cancelled
    case succeeded
    case failed
}
