// 세션 상태를 앱 안에서 모아(StatusCollector) 모든 화면에 desk.status 로 보낸다.
// 10초마다, 그리고 refresh() 를 부르면 바로 (켤 때, 화면이 준비됐을 때, 팀.json 을 고쳤을 때).
import Foundation

final class StatusFeed: ObservableObject {
    @Published private(set) var lastError: String?
    @Published private(set) var lastRun: Date?
    /// 고양이 key → 따라가는 세션, 일하는 중인 고양이. 우클릭 메뉴가 쓴다 (화면으로는 보내지 않는다)
    private(set) var sessions: [String: (id: String, cwd: String)] = [:]
    private(set) var working: Set<String> = []
    private let collector: StatusCollector
    private unowned let stages: Stages
    private let queue = DispatchQueue(label: "local.catteam.status")     // 수집은 한 번에 하나씩, 뒤에서
    private var timer: Timer?

    init(teamURL: URL, stages: Stages) {
        collector = StatusCollector(teamURL: teamURL)
        self.stages = stages
    }

    func start() {
        refresh()
        let t = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)                                // 메뉴가 열려 있어도 돈다
        timer = t
    }

    func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            let result = Result { try self.collector.collectAll() }
            DispatchQueue.main.async {
                switch result {
                case .success(let r):
                    self.lastError = nil
                    self.lastRun = Date()
                    self.sessions = r.sessions
                    self.working = Set((r.data["status"] as? [String: Any] ?? [:]).compactMap { key, v in
                        (v as? [String: Any])?["state"] as? String == "working" ? key : nil
                    })
                    self.stages.call("desk.status", r.data)
                case .failure(let error):
                    self.lastError = "팀.json 을 읽지 못했어요: \(error.localizedDescription)"
                }
            }
        }
    }
}
