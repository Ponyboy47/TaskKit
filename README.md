# TaskKit

AKA Task It

This framework is intended to replace the Standard Library's OperationQueue & Operation classes.
I've ran into a number of issues when using OperationQueue where it can't handle more than 100
tasks (at least on Linux) and a number of other intricacies that I found frustrating or just
down right annoying. So I built this! I tried to make it thread-safe with similar APIs, but more
protocol oriented than the Standard Library counterpart.


## Installation (SPM)
Add this to your Package.swift
```swift
.package(url: https://github.com/Ponyboy47/TaskKit.git", from: "0.3.1")
```

## Usage
The basis of TaskKit is (you guessed it) Tasks.

There are a number of Task protocols you can opt to conform to:
### Task
This is the base protocol and source of the basic Task functionality.
These are the variables/functions you must implement to conform to the Task protocol:

```swift
var status: TaskStatus { get set }
```
This contains information about the current execution progress of the task and may also contain an array of log messages (you would have to add log messages in your object that conforms to Task).
It is recomended that you begin by assigning this to .ready, otherwise, be sure that the status.state value is .ready before your task is added to the TaskQueue or else it will fail to execute.

```swift
var priority: TaskPriority { get }
```
Each task's priority determines when the task will be executed. Pretty self explanatory. High priority tasks are executed before lower priority tasks.

```swift
var qos: DispatchQoS { get }
```
This will be the Quality of Service that is used to execute your task

```swift
var completionBlock: (TaskStatus) -> Void { get }
```
A closure that will be executed when your task completes, whether or not it completed successfully. This is why the TaskStatus is passed to the completion block, so you can have different logic depending on whether it failed or succeeded. This is useful for any clean up code you may need to run.

```swift
func execute() -> Bool
```
This is the function that will be called to run your task. The return value should be true if your task completed its execution successfully, otherwise return false.

### ConfigurableTask
A Task that depends on some external source to configure itself properly (ie: a script to validate a configuration file before execution)

```swift
func configure() -> Bool
```
The configure function will be ran before your task can be executed. It is expected that while configuring your task, it will be mutated. Otherwise, what is it even configuring? This function should return true if it succeeded or false if it failed.

### PausableTask
A Task that can be stopped mid-execution and resumed at a later time.

```swift
func pause() -> Bool
```
The function used to stop execution. Return true if the task is successfully paused, otherwise return false.

```swift
func resume() -> Bool
```
The function used to resume previously stopped execution. Return true if the task is successfully resumed, otherwise return false.

### CancellableTask
A Task that can be cancelled mid-execution, but cannot (or will not) be resumed at a later time.

```swift
func cancel() -> Bool
```
The function used to cancel execution. Return true if the task is sucessfully cancelled, otherwise return false.

### DependentTask
A Task that cannot be executed until one or more other Tasks have successfully been executed

```swift
var dependencies: [Task] { get set }
```
An array of the tasks that must execute successfully before this task can begin its execution.

```swift
var dependencyCompletionBlock: (Task) -> Void { get }
```
A closure that is ran whenever a dependency finishes executing. The DependentTask is passed as the Task in the closure

## License
MIT
