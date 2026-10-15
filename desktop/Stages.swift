// 디스플레이마다 투명 패널(무대)을 하나씩 띄우고, 고양이를 디스플레이에 나눠 준다.
// 고양이는 정해진 디스플레이 안에서만 돌아다닌다.
//  - 한 번 정해진 자리는 PetSettings.displays 에 저장하고, 다른 고양이를 옮겨도 바꾸지 않는다
//  - 자리가 없는 고양이(새 고양이, "고양이가 적은 화면으로")만 고양이가 가장 적은 디스플레이에 둔다
//  - 자리의 디스플레이가 지금 없으면 그동안 주 화면에 두고, 다시 꽂으면 돌아간다
import Cocoa
import Combine

struct Display: Identifiable, Hashable {
    let id: String          // 재부팅해도 바뀌지 않는 디스플레이 UUID
    let name: String
}

final class Stage {
    let display: Display
    let panel: PetPanel
    let bridge: Bridge

    init(screen: NSScreen, display: Display, hub: Stages) {
        self.display = display
        panel = PetPanel(screen: screen)
        bridge = Bridge(panel: panel, hub: hub, screenID: display.id)
    }

    /// 지금 이 디스플레이에 해당하는 NSScreen
    var screen: NSScreen? { NSScreen.screens.first { $0.frame == panel.frame } ?? NSScreen.screens.first { Stages.id(of: $0) == display.id } }

    /// 디스플레이를 뺐을 때: 웹뷰가 뒤에서 계속 돌지 않게 멈추고 정리한다
    func close() {
        bridge.ready = false
        panel.web.configuration.userContentController.removeScriptMessageHandler(forName: "cat")
        panel.web.stopLoading()
        panel.web.loadHTMLString("", baseURL: nil)
        panel.orderOut(nil)
        panel.close()
    }
}

final class Stages: ObservableObject {
    let store: TeamStore
    let settings: PetSettings
    @Published private(set) var displays: [Display] = []
    /// 고양이 key → 지금 사는 디스플레이 id
    @Published private(set) var assign: [String: String] = [:]
    private(set) var stages: [Stage] = []
    var onOpenTeam: (() -> Void)?
    var onStageReady: ((Stage) -> Void)?
    private(set) lazy var menu = ContextMenu(stages: self)      // 고양이 우클릭 메뉴
    private var bag = Set<AnyCancellable>()

    init(store: TeamStore, settings: PetSettings) {
        self.store = store
        self.settings = settings
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.syncScreens() }
        store.$cats.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.reassign() }.store(in: &bag)
    }

    static func id(of screen: NSScreen) -> String {
        let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        if let uuid = CGDisplayCreateUUIDFromDisplayID(num)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return "display-\(num)"
    }

    var mainID: String { displays.first?.id ?? "" }

    /// 화면 구성에 맞게 무대를 만들고 없앤다. 주 화면이 항상 첫 번째다
    func syncScreens() {
        let screens = NSScreen.screens
        var seen: [String: Int] = [:]
        let now: [Display] = screens.map {
            let base = Stages.id(of: $0)
            seen[base, default: 0] += 1
            return Display(id: seen[base]! > 1 ? "\(base)#\(seen[base]!)" : base, name: $0.localizedName)
        }
        for stage in stages where !now.contains(where: { $0.id == stage.display.id }) {
            stage.close()
        }
        stages = zip(screens, now).map { screen, display in
            if let old = stages.first(where: { $0.display.id == display.id }) {
                old.panel.fit(screen)
                return old
            }
            let stage = Stage(screen: screen, display: display, hub: self)
            stage.bridge.onReady = { [weak self, weak stage] in if let stage { self?.onStageReady?(stage) } }
            stage.panel.alphaValue = CGFloat(settings.opacity)
            if settings.enabled { stage.panel.orderFrontRegardless() }
            stage.panel.load()
            return stage
        }
        displays = now
        reassign(force: true)
    }

    /// 고양이를 디스플레이에 나눈다 (규칙은 DisplayAssign.swift). 바뀌었으면 모든 무대에 알린다
    func reassign(force: Bool = false) {
        guard !displays.isEmpty else { return }
        let r = DisplayAssign.run(cats: store.cats.filter { !$0.hidden }.map(\.key),
                                  chosen: settings.displays, displays: displays.map(\.id))
        if !r.placed.isEmpty { settings.displays.merge(r.placed) { $1 } }   // 정한 자리는 기억해서 다시 섞지 않는다
        guard force || r.assign != assign else { return }
        assign = r.assign
        pushSettings()
    }

    /// 사용자가 고른 디스플레이. nil 이면 지금 고양이가 가장 적은 디스플레이로 옮긴다
    func choose(_ key: String, display: String?) {
        settings.displays[key] = display
        reassign()
    }

    // MARK: 모든 무대에

    func pushSettings() { stages.forEach { $0.bridge.pushSettings() } }
    func call(_ fn: String, _ args: Any...) { stages.forEach { $0.bridge.call(fn, args: args) } }
    func reload() { stages.forEach { $0.bridge.reload() } }

    func applyOpacity(_ opacity: Double) {
        stages.forEach { $0.panel.alphaValue = CGFloat(opacity) }
    }

    func applyEnabled() {
        for s in stages {
            if settings.enabled { s.panel.orderFrontRegardless() } else { s.panel.orderOut(nil) }
        }
    }

    /// 무대마다 넘길 설정: 공통 설정 + 이 화면 id + 고양이 배치
    func js(for screenID: String) -> [String: Any] {
        var o = settings.js
        o["screen"] = screenID
        o["main"] = screenID == mainID
        o["assign"] = assign
        o["saved"] = settings.savedCats
        return o
    }
}
