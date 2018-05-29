public enum TaskPriority: RawRepresentable, Comparable {
    public var rawValue: UInt8 {
        get {
            switch self {
            case .custom(let value): return value
            case .minimal: return 0
            case .low: return 63
            case .medium: return 127
            case .high: return 191
            case .critical: return 255
            }
        }
        set {
            if (newValue == TaskPriority.minimal) {
                self = .minimal
            } else if (newValue == TaskPriority.low) {
                self = .low
            } else if (newValue == TaskPriority.medium) {
                self = .medium
            } else if (newValue == TaskPriority.high) {
                self = .high
            } else if (newValue == TaskPriority.critical) {
                self = .critical
            } else {
                self = .custom(newValue)
            }
        }
    }

    case minimal
    case low
    case medium
    case high
    case critical
    case custom(UInt8)

    public init(rawValue: UInt8) {
        if (rawValue == TaskPriority.minimal) {
            self = .minimal
        } else if (rawValue == TaskPriority.low) {
            self = .low
        } else if (rawValue == TaskPriority.medium) {
            self = .medium
        } else if (rawValue == TaskPriority.high) {
            self = .high
        } else if (rawValue == TaskPriority.critical) {
            self = .critical
        } else {
            self = .custom(rawValue)
        }
    }

    public mutating func increase() {
        switch self {
        case .minimal: self = .low
        case .low: self = .medium
        case .medium: self = .high
        case .high: self = .critical
        case .custom(let value):
            if value < .low {
                self = .low
            } else if value < .medium {
                self = .medium
            } else if value < .high {
                self = .high
            } else {
                self = .critical
            }
        default: break
        }
    }

    public mutating func decrease() {
        switch self {
        case .low: self = .minimal
        case .medium: self = .low
        case .high: self = .medium
        case .critical: self = .high
        case .custom(let value):
            if value > .high {
                self = .high
            } else if value > .medium {
                self = .medium
            } else if value > .low {
                self = .low
            } else {
                self = .minimal
            }
        default: break
        }
    }

    public static func == (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }
    public static func == (lhs: UInt8, rhs: TaskPriority) -> Bool {
        return lhs == rhs.rawValue
    }
    public static func == (lhs: TaskPriority, rhs: UInt8) -> Bool {
        return lhs.rawValue == rhs
    }

    public static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
    public static func < (lhs: UInt8, rhs: TaskPriority) -> Bool {
        return lhs < rhs.rawValue
    }
    public static func < (lhs: TaskPriority, rhs: UInt8) -> Bool {
        return lhs.rawValue < rhs
    }

    public static func > (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        return lhs.rawValue > rhs.rawValue
    }
    public static func > (lhs: UInt8, rhs: TaskPriority) -> Bool {
        return lhs > rhs.rawValue
    }
    public static func > (lhs: TaskPriority, rhs: UInt8) -> Bool {
        return lhs.rawValue > rhs
    }

    public static func += (lhs: inout TaskPriority, rhs: TaskPriority) {
        lhs.rawValue += rhs.rawValue
    }
    public static func += (lhs: inout TaskPriority, rhs: UInt8) {
        lhs.rawValue += rhs
    }
}
