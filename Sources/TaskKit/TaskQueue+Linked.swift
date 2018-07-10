import Foundation
import Dispatch

/// A class very similar to a TaskQueue, except this queue makes the assumption that any dependent tasks are added to either this queue or one of the linked queues
open class LinkedTaskQueue: TaskQueue {
    public private(set) var linkedQueues: Set<LinkedTaskQueue> = Set()
    private let _linkedQueuesSemaphore = DispatchSemaphore(value: 1)

    public var dependentTaskOptions: DependentTaskOption = []

    private var _waitingForDependency: [UUID: [DispatchGroup]] = [:]
    private var _waitingForDependencySemaphore = DispatchSemaphore(value: 1)

    override var _active: Int {
        return super._active + _waitingForDependency.count
    }

    override var waiting: [Task] {
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
                return ($0 as! DependentTask).waiting.count == 0
            }
            return ($0 as! DependentTask).waiting.count < ($1 as! DependentTask).waiting.count
        }
    }

    private enum DependencyState {
        case waiting
        case beginning
        case running
        case failed
        case notFound
    }

    private func find(task: Task) -> (DependencyState, SetIndex<LinkedTaskQueue>?) {
        for queue in linkedQueues {
            if queue.waiting.first(where: { $0.id == task.id }) != nil {
                return (.waiting, linkedQueues.index(of: queue))
            } else if queue.beginning.first(where: { $0.id == task.id }) != nil {
                return (.beginning, linkedQueues.index(of: queue))
            } else if queue.running.first(where: { $0.id == task.id }) != nil {
                return (.running, linkedQueues.index(of: queue))
            } else if queue.failed.first(where: { $0.id == task.id }) != nil {
                return (.failed, linkedQueues.index(of: queue))
            }
        }
        return (.notFound, nil)
    }

    func increasePriority(_ task: Task) {
        guard let index = waiting.index(where: { $0.id == task.id }) else { return }
        waiting[index].priority.increase()
        type(of: self).sort(&tasks)
    }

    override func prepare(_ task: DependentTask) -> Task? {
        task.state = .currently(.preparing)

        guard task.waiting.isEmpty else {
            var groups: [DispatchGroup] = []
            for dep in task.waiting {
                let (depState, queueIndex) = find(task: dep)
                switch depState {
                case .waiting:
                    if dependentTaskOptions.contains(.increaseDependencyPriority), let index = queueIndex {
                        linkedQueues[index].increasePriority(dep)
                    }
                    if dependentTaskOptions.contains(.decreaseDependentTaskPriority) {
                        task.priority.decrease()
                        type(of: self).sort(&tasks)
                    }
                case .failed:
                    task.state = .dependency(dep)
                    failed(task)
                    return nil
                case .notFound:
                    fatalError("Could not find dependency task \(dep) in any of the linked queues. Task \(task) will never be able to execute!")
                default:
                    guard let index = queueIndex else { break }
                    guard let group = linkedQueues[index]._groups[dep.id] else { break }
                    groups.append(group)
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
            } else if let ready = waiting.first {
                upNext = ready
            } else { return }

            _waitingForDependencySemaphore.waitAndRun {
                if let groups = _waitingForDependency[upNext.id] {
                    queue.async(qos: .background) {
                        for group in groups {
                            group.wait()
                        }
                        upNext.state = .done(.waiting)
                        self._getNext = true
                    }

                    _waitingForDependency.removeValue(forKey: upNext.id)

                    return
                } else if case .currently(.waiting) = upNext.state { return }
            }

            start(upNext)
        }
    }
}
