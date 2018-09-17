# TaskKit AKA "Task It"

This framework is my attempt at replacing the Standard Library's [OperationQueue](https://developer.apple.com/documentation/foundation/operationqueue) & [Operation](https://developer.apple.com/documentation/foundation/operation) classes.<br />
I've ran into a number of issues when using an `OperationQueue` in the past, like when it can't handle more than 100 `Operation`s and freezes indefinitely (at least on Linux), as well as a number of other intricacies that I found frustrating or just down right annoying.<br />
So I built this! I tried to make it equally thread-safe with similar APIs, but more protocol oriented than the Standard Library counterpart.

## Installation (SPM)
Add this to your Package.swift
```swift
.package(url: "https://github.com/Ponyboy47/TaskKit.git", from: "0.6.0")
```
Supports Swift 4.x (Including 4.2)

## The Task Protocols
The basis of TaskKit is (you guessed it) Tasks.

There are a number of Task protocols you can conform to:
### Task
This is the base protocol that all the subsequent `*Task` protocols also conform to.<br />
In order to conform to any `Task` protocol, you must implement the following protocol requirements:<br />

```swift
var state: TaskState { get set }
```
This contains information about the current execution progress of the task and may also contain an array of log messages (you would have to add log messages in your object that conforms to `Task`).<br />
It is recomended that you begin by assigning this to `.ready`, otherwise, be sure that the `status.state` value is `.ready` before your task is added to the TaskQueue or else it will fail to execute.<br /><br />

```swift
var priority: TaskPriority { get set }
```
A task's priority determines when it will be executed relative to other tasks in the queue.<br />
High priority tasks are executed before lower priority tasks.<br /><br />

```swift
var qos: DispatchQoS { get }
```
This will be the [Quality of Service](https://developer.apple.com/documentation/dispatch/dispatchqos) that is used to execute your task.<br /><br />

```swift
func finish()
```
A function that will be executed when your task completes, regardless of whether or not it completed successfully.<br />
Check your task's state so that you can have different logic depending on whether it failed or succeeded.<br /><br />

```swift
func execute() -> Bool
```
This is the function that will be called to run your task.<br />
This function should return whether or not your task completed its execution successfully.<br /><br />

### ConfigurableTask
A `Task` that depends on some external source to configure itself properly (ie: a script to validate a configuration file before execution).

```swift
func configure() -> Bool
```
The function that must run successfully before your task can be executed.<br />
This function should return whether or not it configured your task properly.<br /><br />

### PausableTask
A `Task` that can be stopped mid-execution and resumed at a later time.

```swift
func pause() -> Bool
```
The function used to stop execution.<br />
Return whether or not your task's execution was successfully paused.<br /><br />

```swift
func resume() -> Bool
```
The function used to resume previously stopped execution.<br />
Return whether or not your task's execution was successfully resumed.<br /><br />

### CancellableTask
A `Task` that can be cancelled mid-execution, but cannot (or will not) be resumed at a later time.

```swift
func cancel()
```
The function used to cancel execution.<br />

### DependentTask
A `Task` that cannot be executed until one or more other `Task`s have successfully been executed.

```swift
var dependencies: [Task] { get set }
```
An array of the tasks that must execute successfully before this task can begin its execution.<br /><br />

```swift
func finish(dependency: Task)
```
A function that is ran whenever a dependency finishes executing.<br />
The dependency that just completed is passed as the `dependency` parameter.<br /><br />

## Basic Usage

After you have at least one type conforming to any of the `Task` protocols, you can create a `TaskQueue` and add tasks to it:
```swift
// Create a queue (maxSimultaneous defaults to 1)
let queue = TaskQueue(name: "com.example.taskqueue", maxSimultaneous: 2)

// Add a task to the queue
queue.add(task: myTask)

// Start the queue's execution
queue.start()
```

If you have a task with dependencies, then you don't need to add the dependencies to the task.
They'll automatically be ran before the task that they depend on is run.
```swift
// Add a dependency to your task
myTask.add(dependency: dependencyTask)

// Add the base task to the queue
queue.add(task: myTask)

// Start the queue
queue.start()
```

## Linked Queues

Sometimes, you might want to separate tasks into different queues even when the tasks in the separate queues may depend on each other.
This is where you may use a LinkedTaskQueue instead.
```swift
// Let's start with two queues:
// 1. For moving media files
// 2. For converting the media
let moveQueue = LinkedTaskQueue(name: "com.example.linked.move", maxSimultaneous: 5)
let conversionQueue = LinkedTaskQueue(name: "com.example.linked.conversion", linkedTo: moveQueue)

// Add our move tasks
moveQueue.add(tasks: moveTasks)

// One of the move tasks shouldn't happen until after it has been converted
moveTasks[0].add(dependency: conversionTask)

// Add that conversion task to its queue
conversionQueue.add(task: conversionTask)

// Start both the queues
moveQueue.start()
conversionQueue.start()
```
NOTE: Any dependency tasks must exist in one of the linked queues or there will be a fatal error

## TODO

- [ ] Investigate ARC best-practices and see if memory usage/performance/correctness can be improved
  - https://docs.swift.org/swift-book/LanguageGuide/AutomaticReferenceCounting.html
- [x] Investigate improved Hashable conformances
  - https://developer.apple.com/documentation/swift/adopting_common_protocols

## License
MIT
