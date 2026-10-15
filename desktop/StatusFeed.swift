// 세션 상태를 앱 안에서 모아(StatusCollector) 모든 화면에 desk.status 로 보낸다.
// 10초마다, 그리고 refresh() 를 부르면 바로 (켤 때, 화면이 준비됐을 때, 팀.json 을 고쳤을 때).
// 사용자 차례인 고양이(아직 클릭해 확인하지 않은 것)는 desk.attention 으로 따로 보낸다. 바뀔 때만.
import Foundation

final class StatusFeed: ObservableObject {
    @Published private(set) var lastError: String?
    @Published private(set) var lastRun: Date?
    /// 고양이 key → 따라가는 세션, 일하는 중인 고양이. 우클릭 메뉴가 쓴다 (화면으로는 보내지 않는다)
    private(set) var sessions: [String: (id: String, cwd: String)] = [:]
    private(set) var working: Set<String> = []
    private var pending: [String: (kind: String, stamp: String)] = [:]   // 사용자 차례인 고양이 (확인 여부와 상관없이)
    private var shown: [String: String]?                                 // 마지막으로 보낸 desk.attention
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
                    self.pending = r.attention
                    self.pushAttention()
                case .failure(let error):
                    self.lastError = "팀.json 을 읽지 못했어요: \(error.localizedDescription)"
                }
            }
        }
    }

    /// 화면이 (다시) 준비됐을 때: 보낸 적 있는 "!" 를 그 화면에도 주고 새로 모은다
    func ready(_ stage: Stage) {
        if let shown { stage.bridge.call("desk.attention", shown) }
        refresh()
    }

    /// 고양이를 클릭했을 때: 지금 일을 확인한 것으로 적고 바로 다시 보낸다. 새 일(새 stamp)이 생기면 다시 뜬다
    func ack(_ key: String) {
        guard let a = pending[key] else { return }
        var acks = stages.settings.acks ?? [:]
        acks[key] = a.stamp
        stages.settings.acks = acks
        pushAttention()
    }

    private func pushAttention() {
        if stages.settings.acks == nil { stages.settings.acks = pending.mapValues(\.stamp) }   // 처음 켰을 때는 모든 고양이에 뜨지 않게
        let acks = stages.settings.acks ?? [:]
        let map = pending.filter { acks[$0.key] != $0.value.stamp }.mapValues(\.kind)
        guard map != shown else { return }
        shown = map
        stages.call("desk.attention", map)
    }
}
