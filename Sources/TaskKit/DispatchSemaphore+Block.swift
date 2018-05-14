import Dispatch

extension DispatchSemaphore {
    func waitAndRun(execute work: () -> ())  {
        self.wait()
        work()
        self.signal()
    }
}
