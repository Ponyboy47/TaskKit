# TaskKit AKA "Task It"

This framework is my attempt at replacing the Standard Library's [OperationQueue](https://developer.apple.com/documentation/foundation/operationqueue) & [Operation](https://developer.apple.com/documentation/foundation/operation) classes.<br />
I've ran into a number of issues when using an `OperationQueue` in the past, like when it can't handle more than 100 `Operation`s and freezes indefinitely (at least on Linux), as well as a number of other intricacies that I found frustrating or just down right annoying.<br />
So I built this! I tried to make it equally thread-safe with similar APIs, but more protocol oriented than the Standard Library counterpart.

## Installation (SPM)
Add this to your Package.swift
```swift
.package(url: "https://github.com/Ponyboy47/TaskKit.git", from: "0.7.1")
```

## License
MIT
