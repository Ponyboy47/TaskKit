import Foundation

public struct TaskState: RawRepresentable, ExpressibleByIntegerLiteral, Equatable {
    public typealias IntegerLiteralType = UInt16

    public private(set) var rawValue: IntegerLiteralType
    let id: UUID = UUID()

    public static let ready: TaskState       = 0b0000_00000_0000001
    static let prepare: TaskState            = 0b0000_00000_0000010
    static let configure: TaskState          = 0b0000_00000_0000100
    static let execute: TaskState            = 0b0000_00000_0001000
    static let pause: TaskState              = 0b0000_00000_0010000
    static let cancel: TaskState             = 0b0000_00000_0100000
    static let resume: TaskState             = 0b0000_00000_1000000
    private static let mask: TaskState       = 0b0000_00000_1111111

    static let start: TaskState              = 0b0000_00001_0000000
    static let fail: TaskState               = 0b0000_00010_0000000
    static let done: TaskState               = 0b0000_00100_0000000
    static let wait: TaskState               = 0b0000_01000_0000000
    static let dependency: TaskState         = 0b0000_11000_0000000

    public static let succeeded = TaskState(rawValue: .done | .execute)
    static let waited = TaskState(rawValue: .done | .wait)

    public var isReady: Bool {
        return self == .ready
    }
    public var isStarted: Bool {
        return contains(.start)
    }
    public var isDone: Bool {
        return contains(.done)
    }
    public var didFail: Bool {
        return contains(.fail)
    }
    public var didSucceed: Bool {
        return self == .succeeded
    }
    public var isWaiting: Bool {
        return contains(.wait)
    }
    public var isPaused: Bool {
        return isDone && contains(.pause)
    }
    public var wasCancelled: Bool {
        return isDone && contains(.cancel)
    }
    public var isExecuting: Bool {
        return isStarted && contains(.execute)
    }

    public func hasStarted(to state: TaskState) -> Bool {
        precondition(state.isRaw)

        return isStarted && contains(state)
    }
    public func hasFinished(_ state: TaskState) -> Bool {
        precondition(state.isRaw)

        return isDone && contains(state)
    }
    public func isWaiting(to state: TaskState) -> Bool {
        precondition(state.isRaw)

        return isWaiting && contains(state)
    }

    private var isRaw: Bool {
        return rawState == self
    }
    private var rawState: IntegerLiteralType {
        return rawValue & TaskState.mask
    }

    public init(rawValue: IntegerLiteralType) {
        self.rawValue = rawValue
    }

    public init(integerLiteral value: IntegerLiteralType) {
        rawValue = value
    }

    mutating func start(to state: TaskState) {
        rawValue = state.rawState | .start
    }

    mutating func start() {
        precondition(isReady)

        rawValue = rawState | TaskState.start
    }

    mutating func finish() {
        precondition(isStarted)

        rawValue = rawState | .done
    }

    mutating func fail() {
        precondition(isStarted)

        rawValue = rawState | .done
    }

    mutating func wait(to state: TaskState) {
        rawValue = state.rawState | .wait
    }

    mutating func pause() {
        precondition(isExecuting)

        rawValue = rawState | .pause
    }

    mutating func cancel() {
        precondition(isExecuting)

        rawValue = rawState | .cancel
    }

    mutating func dependency() {
        rawValue |= .dependency
    }

    public func contains(_ state: TaskState) -> Bool {
        return (rawValue & state) == state
    }

    public static func == (lhs: TaskState, rhs: TaskState) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }
    public static func == (lhs: TaskState, rhs: IntegerLiteralType) -> Bool {
        return lhs.rawValue == rhs
    }

    public static func & (lhs: TaskState, rhs: TaskState) -> IntegerLiteralType {
        return lhs.rawValue & rhs.rawValue
    }
    public static func & (lhs: TaskState, rhs: IntegerLiteralType) -> IntegerLiteralType {
        return lhs.rawValue & rhs
    }
    public static func &= (lhs: inout TaskState, rhs: TaskState) {
        lhs.rawValue = lhs & rhs.rawValue
    }
    public static func &= (lhs: inout TaskState, rhs: IntegerLiteralType) {
        lhs.rawValue = lhs & rhs
    }

    public static func | (lhs: TaskState, rhs: TaskState) -> IntegerLiteralType {
        return lhs.rawValue | rhs.rawValue
    }
    public static func | (lhs: TaskState, rhs: IntegerLiteralType) -> IntegerLiteralType {
        return lhs.rawValue | rhs
    }
    public static func |= (lhs: inout TaskState, rhs: TaskState) {
        lhs.rawValue = lhs | rhs.rawValue
    }
    public static func |= (lhs: inout TaskState, rhs: IntegerLiteralType) {
        lhs.rawValue = lhs | rhs
    }

    public static prefix func ~ (state: TaskState) -> IntegerLiteralType {
        return ~state.rawValue
    }
}

extension TaskState.IntegerLiteralType {
    public static func == (lhs: TaskState.IntegerLiteralType, rhs: TaskState) -> Bool {
        return lhs == rhs.rawValue
    }
    public static func & (lhs: TaskState.IntegerLiteralType, rhs: TaskState) -> TaskState.IntegerLiteralType {
        return lhs & rhs.rawValue
    }
    public static func &= (lhs: inout IntegerLiteralType, rhs: TaskState) {
        lhs = lhs & rhs.rawValue
    }
    public static func | (lhs: TaskState.IntegerLiteralType, rhs: TaskState) -> TaskState.IntegerLiteralType {
        return lhs | rhs.rawValue
    }
    public static func |= (lhs: inout IntegerLiteralType, rhs: TaskState) {
        lhs = lhs | rhs.rawValue
    }
}
