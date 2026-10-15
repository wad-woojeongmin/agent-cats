// 수집기(수집.py --loop)를 앱의 자식 프로세스로 돌린다. 앱이 꺼지면 함께 끈다.
import Foundation

final class Collector: ObservableObject {
    @Published private(set) var running = false
    private var process: Process?
    private let python = URL(fileURLWithPath: "/usr/bin/python3")

    private func make(_ args: [String]) -> Process {
        let p = Process()
        p.executableURL = python
        p.arguments = [Paths.project.appendingPathComponent("수집.py").path] + args
        p.currentDirectoryURL = Paths.project
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        return p
    }

    func start() {
        guard process?.isRunning != true else { return }
        let p = make(["--loop"])
        p.terminationHandler = { [weak self] _ in DispatchQueue.main.async { self?.running = false } }
        do {
            try p.run()
            process = p
            running = true
        } catch {
            running = false
        }
    }

    func stop() {
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        running = false
    }

    func restart() {
        stop()
        start()
    }

    /// 한 번만 수집해서 status.js 를 바로 새로 쓴다 (팀.json 을 고친 직후)
    func runOnce(then done: @escaping () -> Void) {
        let p = make([])
        p.terminationHandler = { _ in DispatchQueue.main.async(execute: done) }
        do { try p.run() } catch { done() }
    }
}
