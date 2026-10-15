// 고양이 팀 데스크톱 앱의 시작점.
// 메뉴 막대에만 나타나는 앱(.accessory)으로 뜨고, 디스플레이마다 화면 전체를 덮는 투명 패널에 desktop.html 을 띄운다.
// 수집기(수집.py --loop)도 함께 켜고, 앱을 끌 때 같이 끈다.
import Cocoa
import Combine

enum Paths {
    /// 프로젝트 폴더: 앱 번들이 놓인 폴더. 시험할 때는 CATTEAM_DIR 로 바꿀 수 있다.
    static let project: URL = {
        if let dir = ProcessInfo.processInfo.environment["CATTEAM_DIR"] { return URL(fileURLWithPath: dir) }
        return Bundle.main.bundleURL.deletingLastPathComponent()
    }()
    static var team: URL { project.appendingPathComponent("팀.json") }
    static var example: URL { project.appendingPathComponent("팀.example.json") }
    static var page: URL { project.appendingPathComponent("desktop.html") }
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
    let collector = Collector()
    var store: TeamStore!
    var stages: Stages!
    var watcher: WorldWatcher!
    var statusMenu: StatusMenu!
    var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ note: Notification) {
        guard FileManager.default.fileExists(atPath: Paths.page.path) else {
            let alert = NSAlert()
            alert.messageText = "고양이 팀 폴더를 찾지 못했어요"
            alert.informativeText = "고양이팀.app 은 desktop.html 과 팀.json 이 있는 폴더 안에 두어야 해요.\n지금 위치: \(Paths.project.path)"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        if !FileManager.default.fileExists(atPath: Paths.team.path) {      // 처음 실행이면 예시를 복사해 팀.json 을 만든다
            try? FileManager.default.copyItem(at: Paths.example, to: Paths.team)
        }
        store = TeamStore(url: Paths.team)
        collector.start()
        stages = Stages(store: store, settings: settings)
        watcher = WorldWatcher(hub: stages, settings: settings)
        statusMenu = StatusMenu(store: store, settings: settings, collector: collector, stages: stages)
        stages.onOpenTeam = { [weak self] in self?.statusMenu.open(.team) }
        store.onSaved = { [weak self] in
            self?.collector.runOnce { self?.stages.call("desk.poll") }      // 팀.json 을 고치면 바로 다시 수집해 반영
        }

        watchSettings()
        stages.syncScreens()                                                   // 디스플레이마다 패널을 띄운다 (투명도·켜짐도 여기서)
        watcher.start()
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

    func applicationWillTerminate(_ note: Notification) {
        collector.stop()
    }
}
