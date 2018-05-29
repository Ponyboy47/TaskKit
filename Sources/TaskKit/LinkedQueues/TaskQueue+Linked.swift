import Foundation
import Dispatch

/// A class very similar to a TaskQueue, except this queue makes the assumption that any dependent tasks are added to either this queue or one of the linked queues
open class LinkedTaskQueue: TaskQueue {
    public private(set) var linkedQueues: [LinkedTaskQueue] = []
    private let _linkedQueuesSemaphore = DispatchSemaphore(value: 1)

    public var dependentTaskOptions: DependentTaskOption = []

    override var _dependents: [DependentTask] {
        return waiting.compactMap { return $0 as? DependentTask }
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

    public func addLink(to queue: LinkedTaskQueue) {
        _linkedQueuesSemaphore.waitAndRun {
            linkedQueues.append(queue)
        }
        queue.addLink(to: self)
    }

    public func addLinks(to queues: [LinkedTaskQueue]) {
        _linkedQueuesSemaphore.waitAndRun {
            linkedQueues += queues
        }
        queues.forEach { $0.addLink(to: self) }
    }

    public func addLinks(to queues: LinkedTaskQueue...) {
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

    override class func sort(_ array: inout [Task]) {
        array.sort { 
            guard $0.priority <= $1.priority else { return true }
            guard $0.priority == $1.priority else { return false }
            guard $0 is DependentTask else { return true }
            guard $1 is DependentTask else {
                return ($0 as! DependentTask).waiting.count == 0
            }
            return ($0 as! DependentTask).waiting.count < ($1 as! DependentTask).waiting.count
        }
    }

    private enum DependencyState {
        case waiting
        case running
        case errored
        case notFound
    }

    private func find(task: Task) -> (DependencyState, Int) {
        for (index, queue) in linkedQueues.enumerated() {
            if queue.waiting.first(where: { $0.id == task.id }) != nil {
                return (.waiting, index)
            } else if queue.running.first(where: { $0.value.id == task.id }) != nil {
                return (.running, index)
            } else if queue.errored.first(where: { $0.id == task.id }) != nil {
                return (.errored, index)
            }
        }
        return (.notFound, -1)
    }

    func reAddDependent(_ task: DependentTask) -> Task? {
        self._getNext = true
        self.add(task: task)
        return nil
    }

    func increasePriority(_ task: Task) {
        guard let index = waiting.index(where: { $0.id == task.id }) else { return }
        waiting[index].priority.increase()
    }

    override func prepare(_ task: DependentTask, with taskKey: UUID) -> Task? {
        guard let task = prepare(task as Task, with: taskKey) as? DependentTask else { return nil }
        task.state = .currently(.preparing)

        guard task.waiting.isEmpty else {
            for dep in task.waiting {
                let (depState, queueIndex) = find(task: dep)
                switch depState {
                case .waiting:
                    if dependentTaskOptions.contains(.increaseDependencyPriority) {
                        linkedQueues[queueIndex].increasePriority(dep)
                    }
                    if dependentTaskOptions.contains(.decreaseDependentTaskPriority) {
                    }
                case .errored:
                    task.state = .dependency(dep)
                    failed(task, with: taskKey)
                    return nil
                case .notFound:
                    fatalError("Could not find dependency task \(dep) in any of the linked queues. Task \(task) will never be able to execute!")
                default: break
                }
            }
            return reAddDependent(task)
        }

        return task
    }
}