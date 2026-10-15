// 고양이 팀 데스크톱 앱의 시작점.
// 메뉴 막대에만 나타나는 앱(.accessory)으로 뜨고, 디스플레이마다 화면 전체를 덮는 투명 패널에 desktop.html 을 띄운다.
// 세션 상태는 앱 안에서 모은다 (StatusFeed).
import Cocoa
import Combine

enum Paths {
    /// 웹 파일: 앱 번들 안 Resources/web (build.sh 가 복사한다)
    static let web = Bundle.main.resourceURL!.appendingPathComponent("web")
    static var page: URL { web.appendingPathComponent("desktop.html") }
    static var example: URL { Bundle.main.resourceURL!.appendingPathComponent("팀.example.json") }
    /// 설정 폴더: ~/Library/Application Support/고양이팀
    static let data = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("고양이팀")
    static var team: URL { data.appendingPathComponent("팀.json") }
    /// cat-add 스킬이 고양이 추가 요청을 넣는 폴더
    static var inbox: URL { data.appendingPathComponent("inbox") }
    /// 앱 번들이 놓인 폴더의 팀.json (저장소에서 빌드해 쓰던 것)
    static var oldTeam: URL { Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("팀.json") }

    /// 팀.json 이 없으면 만든다: 예전 팀.json 이 있으면 그것을, 없으면 예시를 복사한다. 있는 파일은 덮어쓰지 않는다
    static func prepareTeam() {
        let fm = FileManager.default
        try? fm.createDirectory(at: data, withIntermediateDirectories: true)
        guard !fm.fileExists(atPath: team.path) else { return }
        try? fm.copyItem(at: fm.fileExists(atPath: oldTeam.path) ? oldTeam : example, to: team)
    }
}

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    let settings = PetSettings.shared
    var store: TeamStore!
    var stages: Stages!
    var feed: StatusFeed!
    var watcher: WorldWatcher!
    var inbox: Inbox!
    var statusMenu: StatusMenu!
    var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ note: Notification) {
        guard FileManager.default.fileExists(atPath: Paths.page.path) else {
            let alert = NSAlert()
            alert.messageText = "앱 파일이 빠져 있어요"
            alert.informativeText = "고양이팀.app 을 다시 내려받아 주세요."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        Paths.prepareTeam()
        store = TeamStore(url: Paths.team)
        stages = Stages(store: store, settings: settings)
        feed = StatusFeed(teamURL: Paths.team, stages: stages)
        watcher = WorldWatcher(hub: stages, settings: settings)
        stages.onStageReady = { [weak self] stage in self?.watcher.sendAll(stage); self?.feed.ready(stage) }   // 새 화면도 바로 세상 정보와 상태를 받는다
        stages.onAck = { [weak self] key in self?.feed.ack(key) }
        statusMenu = StatusMenu(store: store, settings: settings, feed: feed, stages: stages)
        stages.onOpenTeam = { [weak self] in self?.statusMenu.open(.team) }
        store.onSaved = { [weak self] in self?.feed.refresh() }               // 팀.json 을 고치면 바로 다시 수집해 반영
        stages.menu.feed = feed
        inbox = Inbox(dir: Paths.inbox) { [weak self] folder, name, role in   // 새 고양이는 나타날 때 한 번 인사한다
            guard let self, let r = self.store.adopt(folder: folder, name: name, role: role) else { return }
            self.stages.call("desk.greet", r.key, r.isNew ? "새로 왔어요!" : "이미 있어요!")
        }

        watchSettings()
        stages.syncScreens()                                                   // 디스플레이마다 패널을 띄운다 (투명도·켜짐도 여기서)
        watcher.start()
        feed.start()
        inbox.start()
    }

    /// 설정이 바뀌면 필요한 만큼만 반영한다. 처음 값은 syncScreens 와 "ready" 때 넘어간다
    private func watchSettings() {
        let wait = RunLoop.SchedulerTimeType.Stride.milliseconds(30)
        // 투명도: 패널만 바꾼다 (슬라이더를 끄는 동안 JS 로 보내지 않는다)
        settings.$opacity.dropFirst()
            .sink { [weak self] in self?.stages.applyOpacity($0) }
            .store(in: &bag)
        // 켜기/끄기: 패널을 띄우거나 내리고, JS 도 멈추거나 다시 돈다
        settings.$enabled.dropFirst()
            .debounce(for: wait, scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.stages.applyEnabled(); self?.stages.pushSettings() }
            .store(in: &bag)
        // 고른 디스플레이: 배치가 바뀐 때만 JS 로 보낸다 (reassign 이 자리를 저장해도 두 번째엔 바뀐 게 없어 멈춘다)
        settings.$displays.dropFirst()
            .debounce(for: wait, scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.stages.reassign() }
            .store(in: &bag)
        // 나머지 (크기·활동량·말풍선·행동·아이콘 권한): 배치를 확인하고 설정을 한 번 보낸다
        Publishers.Merge5(settings.$size.dropFirst().map { _ in () },
                          settings.$activity.dropFirst().map { _ in () },
                          settings.$bubbleSec.dropFirst().map { _ in () },
                          settings.$behaviors.dropFirst().map { _ in () },
                          settings.$iconsDenied.dropFirst().map { _ in () })
            .debounce(for: wait, scheduler: RunLoop.main)
            .sink { [weak self] in self?.stages.reassign(force: true) }
            .store(in: &bag)
    }
}
