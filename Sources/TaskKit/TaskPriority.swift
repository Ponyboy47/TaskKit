public enum TaskPriority: RawRepresentable, Comparable, ExpressibleByIntegerLiteral {
    public typealias IntegerLiteralType = UInt8

    public var rawValue: IntegerLiteralType {
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
            if (newValue == .minimal) {
                self = .minimal
            } else if (newValue == .low) {
                self = .low
            } else if (newValue == .medium) {
                self = .medium
            } else if (newValue == .high) {
                self = .high
            } else if (newValue == .critical) {
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
    case custom(IntegerLiteralType)

    public init(rawValue: IntegerLiteralType) {
        if (rawValue == .minimal) {
            self = .minimal
        } else if (rawValue == .low) {
            self = .low
        } else if (rawValue == .medium) {
            self = .medium
        } else if (rawValue == .high) {
            self = .high
        } else if (rawValue == .critical) {
            self = .critical
        } else {
            self = .custom(rawValue)
        }
    }

    public init(integerLiteral value: IntegerLiteralType) {
        self.init(rawValue: value)
    }

    @discardableResult
    public mutating func increase() -> Bool {
        if rawValue < .low {
            self = .low
        } else if rawValue < .medium {
            self = .medium
        } else if rawValue < .high {
            self = .high
        } else if rawValue < .critical {
            self = .critical
        } else { return false }

        return true
    }

    @discardableResult
    public mutating func decrease() -> Bool {
        if rawValue > .high {
            self = .high
        } else if rawValue > .medium {
            self = .medium
        } else if rawValue > .low {
            self = .low
        } else if rawValue > .minimal {
            self = .minimal
        } else { return false }

        return true
    }

    public static func == (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }
    public static func == (lhs: TaskPriority, rhs: IntegerLiteralType) -> Bool {
        return lhs.rawValue == rhs
    }

    public static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
    public static func < (lhs: TaskPriority, rhs: IntegerLiteralType) -> Bool {
        return lhs.rawValue < rhs
    }

    public static func > (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        return lhs.rawValue > rhs.rawValue
    }
    public static func > (lhs: TaskPriority, rhs: IntegerLiteralType) -> Bool {
        return lhs.rawValue > rhs
    }

    public static func += (lhs: inout TaskPriority, rhs: TaskPriority) {
        lhs.rawValue += rhs.rawValue
    }
    public static func += (lhs: inout TaskPriority, rhs: IntegerLiteralType) {
        lhs.rawValue += rhs
    }
}

extension TaskPriority.IntegerLiteralType {
    public static func == (lhs: TaskPriority.IntegerLiteralType, rhs: TaskPriority) -> Bool {
        return lhs == rhs.rawValue
    }
    public static func > (lhs: TaskPriority.IntegerLiteralType, rhs: TaskPriority) -> Bool {
        return lhs > rhs.rawValue
    }
    public static func < (lhs: TaskPriority.IntegerLiteralType, rhs: TaskPriority) -> Bool {
        return lhs < rhs.rawValue
    }
}
