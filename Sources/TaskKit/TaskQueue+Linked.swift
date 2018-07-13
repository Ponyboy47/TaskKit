import Foundation
import Dispatch

/// A class very similar to a TaskQueue, except this queue makes the assumption that any dependent tasks are added to either this queue or one of the linked queues
open class LinkedTaskQueue: TaskQueue {
    public private(set) var linkedQueues: Set<LinkedTaskQueue> = Set()
    private let _linkedQueuesSemaphore = DispatchSemaphore(value: 1)

    public var dependentTaskOptions: DependentTaskOption = []

    private var _waitingForDependency: [UUID: [DispatchGroup]] = [:]
    private var _waitingForDependencySemaphore = DispatchSemaphore(value: 1)

    override public var waiting: [Task] {
        return tasks.filter {
            switch $0.state {
            case .ready, .currently(.waiting): return true
            default: return false
            }
        }
    }
    private var _waitedForDependencies: [Task] {
        return tasks.filter { task in
            switch task.state {
            case .done(.waiting): return true
            default: return false
            }
        }
    }

    override var _active: Int {
        return tasks.reduce(0) {
            switch $1.state {
            case .currently(let state):
                switch state {
                case .beginning, .preparing, .configuring, .executing, .pausing, .cancelling: return $0 + 1
                default: return $0
                }
            case .done(let state):
                switch state {
                case .waiting, .beginning, .preparing, .configuring: return $0 + 1
                default: return $0
                }
            default: return $0
            }
        }
    }
    /// The total number of tasks left (excluding dependencies)
    override public var remaining: Int {
        return tasks.reduce(0) {
            switch $1.state {
            case .ready: return $0 + 1
            case .currently(let state):
                switch state {
                case .waiting, .beginning, .preparing, .configuring, .executing, .pausing, .cancelling: return $0 + 1
                default: return $0
                }
            case .done(let state):
                switch state {
                case .waiting, .beginning, .preparing, .configuring, .pausing: return $0 + 1
                default: return $0
                }
            default: return $0
            }
        }
    }

    public convenience init(name: String, maxSimultaneous: Int = LinkedTaskQueue.defaultMaxSimultaneous, linkedTo queue: LinkedTaskQueue, options: DependentTaskOption = []) {
        self.init(name: name, maxSimultaneous: maxSimultaneous)
        self.add(link: queue)
    }

    public convenience init(name: String, maxSimultaneous: Int = LinkedTaskQueue.defaultMaxSimultaneous, linkedTo queues: [LinkedTaskQueue], options: DependentTaskOption = []) {
        self.init(name: name, maxSimultaneous: maxSimultaneous)
        self.add(links: queues)
    }

    public convenience init(name: String, maxSimultaneous: Int = LinkedTaskQueue.defaultMaxSimultaneous, linkedTo queues: LinkedTaskQueue..., options: DependentTaskOption = []) {
        self.init(name: name, maxSimultaneous: maxSimultaneous)
        self.add(links: queues)
    }

    public convenience init(name: String, maxSimultaneous: Int = LinkedTaskQueue.defaultMaxSimultaneous, linkedTo queues: Set<LinkedTaskQueue>, options: DependentTaskOption = []) {
        self.init(name: name, maxSimultaneous: maxSimultaneous)
        self.add(links: queues)
    }

    public func addLink(to queue: LinkedTaskQueue) {
        _linkedQueuesSemaphore.waitAndRun {
            linkedQueues.insert(queue)
        }

        if !queue.linkedQueues.contains(self) {
            queue.addLink(to: self)
        }
    }

    public func addLinks(to queues: [LinkedTaskQueue]) {
        _linkedQueuesSemaphore.waitAndRun {
            linkedQueues.formUnion(queues)
        }

        queues.forEach { queue in
            if !queue.linkedQueues.contains(self) {
                queue.addLink(to: self)
            }
        }
    }

    public func addLinks(to queues: LinkedTaskQueue...) {
        addLinks(to: queues)
    }

    public func addLinks(to queues: Set<LinkedTaskQueue>) {
        addLinks(to: queues)
    }

    public func add(link queue: LinkedTaskQueue) {
        addLink(to: queue)
    }

    public func add(links queues: [LinkedTaskQueue]) {
        addLinks(to: queues)
    }

    public func add(links queues: LinkedTaskQueue...) {
        addLinks(to: queues)
    }

    public func add(links queues: Set<LinkedTaskQueue>) {
        addLinks(to: queues)
    }

    override class func sort(_ array: inout [Task]) {
        array.sort { 
            guard $0.priority <= $1.priority else { return true }
            guard $0.priority == $1.priority else { return false }
            guard $0 is DependentTask else { return true }
            guard $1 is DependentTask else {
                return ($0 as! DependentTask).incompleteDependencies.isEmpty
            }
            return ($0 as! DependentTask).incompleteDependencies.count < ($1 as! DependentTask).incompleteDependencies.count
        }
    }

    private func find(task: Task) -> SetIndex<LinkedTaskQueue>? {
        for queue in linkedQueues {
            queue._tasksSemaphore.wait()
            if queue.tasks.first(where: { $0.id == task.id }) != nil {
                return linkedQueues.index(of: queue)
            }
            queue._tasksSemaphore.signal()
        }
        return nil
    }

    override func prepare(_ task: DependentTask) -> Task? {
        task.state = .currently(.preparing)

        guard task.incompleteDependencies.isEmpty else {
            var groups: [DispatchGroup] = []
            for dep in task.incompleteDependencies {
                switch dep.state {
                case .failed, .done(.cancelling), .currently(.cancelling):
                    task.state = .dependency(dep)
                    failed(task)
                    return nil
                default:
                    var changed = !dependentTaskOptions.isEmpty
                    if dependentTaskOptions.contains(.increaseDependencyPriority) {
                        changed = dep.priority.increase()
                    }
                    if dependentTaskOptions.contains(.decreaseDependentTaskPriority) {
                        changed = task.priority.decrease()
                    }

                    if let index = find(task: dep) {
                        if changed {
                            type(of: self).sort(&linkedQueues[index].tasks)
                        }
                        linkedQueues[index]._tasksSemaphore.signal()
                        guard let group = linkedQueues[index]._groups[dep.id] else { continue }
                        groups.append(group)
                    } else if tasks.index(where: { $0.id == dep.id }) != nil {
                        if changed {
                            _tasksSemaphore.waitAndRun {
                                type(of: self).sort(&tasks)
                            }
                        }
                        guard let group = _groups[dep.id] else { continue }
                        groups.append(group)
                    } else {
                        fatalError("Could not find dependency task \(dep) in any of the linked queues. Task \(task) will never be able to execute!")
                    }
                }
            }

            task.state = .currently(.waiting)
            _waitingForDependencySemaphore.waitAndRun {
                _waitingForDependency[task.id] = groups
            }
            self._getNext = true
            return nil
        }

        return task
    }

    /// Begins execution of the next task in the waiting list
    override func startNext() {
        guard _active < maxSimultaneous else { return }

        _tasksSemaphore.waitAndRun {
            let upNext: Task

            if let waited = _waitedForDependencies.first {
                upNext = waited
            } else if let ready = self.upNext {
                upNext = ready
            } else { return }

            if let groups = _waitingForDependency[upNext.id] {
                queue.async(qos: .background) {
                    for group in groups {
                        group.wait()
                    }
                    upNext.state = .done(.waiting)
                    self._getNext = true
                }

                _waitingForDependencySemaphore.waitAndRun {
                    _waitingForDependency.removeValue(forKey: upNext.id)
                }

                return
            } else if case .currently(.waiting) = upNext.state { return }

            start(upNext)
        }
    }
}
