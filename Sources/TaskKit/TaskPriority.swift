public enum TaskPriority: RawRepresentable {
    public var rawValue: UInt8 {
        switch self {
        case .custom(let value): return value
        case .minimal: return 0
        case .low: return 63
        case .medium: return 127
        case .high: return 191
        case .critical: return 255
        }
    }

    case minimal
    case low
    case medium
    case high
    case critical
    case custom(UInt8)

    public init(rawValue: UInt8) {
        if (rawValue == TaskPriority.minimal.rawValue) {
            self = .minimal
        } else if (rawValue == TaskPriority.low.rawValue) {
            self = .low
        } else if (rawValue == TaskPriority.medium.rawValue) {
            self = .medium
        } else if (rawValue == TaskPriority.high.rawValue) {
            self = .high
        } else if (rawValue == TaskPriority.critical.rawValue) {
            self = .critical
        } else {
            self = .custom(rawValue)
        }
    }
}
