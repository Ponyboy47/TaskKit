import Foundation
import Dispatch

/// A class very similar to a TaskQueue, except this queue makes the assumption that any dependent tasks are added to either this queue or one of the linked queues
open class LinkedTaskQueue: TaskQueue {
    public private(set) var linkedQueues: Set<LinkedTaskQueue> = Set()
    private let _linkedQueuesQueue = DispatchQueue(label: "com.TaskKit.linked", qos: .userInitiated, attributes: .concurrent)

    public var dependentTaskOptions: DependentTaskOption = []

    private var _waitingForDependency: [UUID: [DispatchGroup]] = [:]
    private var _waitingForDependencyQueue = DispatchQueue(label: "com.TaskKit.waiting", qos: .userInitiated, attributes: .concurrent)

    private static let _waitingStates: [TaskState] = [.ready, TaskState(rawValue: .execute | .wait)]
    override public var waiting: [Task] {
        return _tasksQueue.sync {
            return tasks.filter {
                return LinkedTaskQueue._waitingStates.contains($0.state)
            }
        }
    }
    override var upNext: Task? {
        return _tasksQueue.sync {
            return tasks.first(where: {
                return LinkedTaskQueue._waitingStates.contains($0.state)
            })
        }
    }

    private var _waitedForDependencies: [Task] {
        return _tasksQueue.sync {
            return tasks.filter {
                return $0.state == .waited
            }
        }
    }

    private static let _linkedActiveStates: [TaskState] = {
        var states = LinkedTaskQueue._activeStates
        states.append(.waited)
        return states
    }()
    override var _active: Int {
        return _tasksQueue.sync {
            return tasks.reduce(0) {
                if LinkedTaskQueue._linkedActiveStates.contains($1.state) {
                    return $0 + 1
                }

                return $0
            }
        }
    }
    /// The total number of tasks left (excluding dependencies)
    override public var remaining: Int {
        return _tasksQueue.sync {
            return tasks.reduce(0) {
                if $1.state == .ready {
                    return $0 + 1
                } else if LinkedTaskQueue._linkedActiveStates.contains($1.state) {
                    return $0 + 1
                }

                return $0
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
        _linkedQueuesQueue.async(flags: .barrier) {
            self.linkedQueues.insert(queue)

            let hasLink: Bool = queue._linkedQueuesQueue.sync {
                return queue.linkedQueues.contains(self)
            }
            if !hasLink {
                queue.addLink(to: self)
            }
        }
    }

    public func addLinks(to queues: [LinkedTaskQueue]) {
        _linkedQueuesQueue.async(flags: .barrier) {
            self.linkedQueues.formUnion(queues)

            queues.forEach { queue in
                let hasLink: Bool = queue._linkedQueuesQueue.sync {
                    return queue.linkedQueues.contains(self)
                }
                if !hasLink {
                    queue.addLink(to: self)
                }
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
        var index: SetIndex<LinkedTaskQueue>? = nil

        _linkedQueuesQueue.sync {
            for queue in linkedQueues {
                let breakOut: Bool = queue._tasksQueue.sync {
                    if queue.tasks.first(where: { $0.id == task.id }) != nil {
                        index = linkedQueues.index(of: queue)
                        return true
                    }
                    return false
                }
                guard !breakOut else { break }
            }
        }

        return index
    }

    private static let failingStates: [TaskState] = {
        return [.start, .done].map { TaskState(rawValue: $0 | .cancel) }
    }()
    override func prepare(_ task: DependentTask) -> Task? {
        let incompleteDependencies = task.incompleteDependencies
        guard incompleteDependencies.isEmpty else {
            var groups: [DispatchGroup] = []

            for dep in incompleteDependencies {
                task.state.dependency()
                guard !( dep.didFail || LinkedTaskQueue.failingStates.contains(dep.state)) else {
                    failed(task)
                    return nil
                }

                var changed = false
                if dependentTaskOptions.contains(.increaseDependencyPriority) {
                    changed = dep.priority.increase()
                }
                if dependentTaskOptions.contains(.decreaseDependentTaskPriority) {
                    changed = task.priority.decrease() || changed
                }

                if let index = find(task: dep) {
                    if changed {
                        linkedQueues[index]._tasksQueue.async(flags: .barrier) {
                            type(of: self).sort(&self.linkedQueues[index].tasks)
                        }
                    }

                    let group = linkedQueues[index]._groupsQueue.sync { return linkedQueues[index]._groups[dep.id] }
                    guard group != nil else { continue }
                    groups.append(group!)
                } else if tasks.index(where: { $0.id == dep.id }) != nil {
                    if changed {
                        _tasksQueue.async(flags: .barrier) {
                            type(of: self).sort(&self.tasks)
                        }
                    }
                    guard let group = _groupsQueue.sync(execute: { return _groups[dep.id] }) else { continue }
                    groups.append(group)
                } else {
                    fatalError("Could not find dependency task \(dep) in any of the linked queues. Task \(task) will never be able to execute!")
                }
            }

            task.state.wait(to: .execute)
            _waitingForDependencyQueue.async(flags: .barrier) {
                self._waitingForDependency[task.id] = groups
            }
            self._getNext = true
            return nil
        }

        return task
    }

    /// Begins execution of the next task in the waiting list
    override func startNext() {
        guard _active < maxSimultaneous else { return }

       let upNext: Task

        if let waited = _waitedForDependencies.first {
            upNext = waited
        } else if let ready = self.upNext {
            upNext = ready
        } else { return }

        if let groups: [DispatchGroup] = _waitingForDependencyQueue.sync(execute: { return _waitingForDependency[upNext.id] }) {
            DispatchQueue.global(qos: .unspecified).async {
                for group in groups {
                    group.wait()
                }
                upNext.state.finish()
                self._getNext = true
            }

            _waitingForDependencyQueue.async(flags: .barrier) {
                self._waitingForDependency.removeValue(forKey: upNext.id)
            }

            return
        } else if upNext.isWaiting { return }

        start(upNext)
    }
}
