// 메뉴 막대에서 바꾸는 설정. UserDefaults 에 저장되고, 바뀌면 패널과 화면(JS)에 바로 반영된다.
import Foundation

struct Behavior: Identifiable {
    let id: String
    let title: String
    let symbol: String
}

final class PetSettings: ObservableObject {
    static let shared = PetSettings()
    private let d = UserDefaults.standard

    static let behaviors: [Behavior] = [
        Behavior(id: "walk", title: "걷기", symbol: "figure.walk"),
        Behavior(id: "run", title: "달리기", symbol: "hare"),
        Behavior(id: "jump", title: "점프", symbol: "arrow.up.forward"),
        Behavior(id: "stretch", title: "스트레칭", symbol: "figure.flexibility"),
        Behavior(id: "chase", title: "커서 쫓기", symbol: "cursorarrow.motionlines"),
        Behavior(id: "window", title: "창 위에 올라가기", symbol: "macwindow"),
        Behavior(id: "windowSide", title: "창 주변에서 놀기", symbol: "rectangle.portrait.and.arrow.right"),
        Behavior(id: "menubar", title: "메뉴 막대에 앉기", symbol: "menubar.rectangle"),
        Behavior(id: "icons", title: "파일/폴더와 놀기", symbol: "folder"),
        Behavior(id: "friends", title: "서로 놀기", symbol: "heart"),
    ]

    @Published var enabled: Bool { didSet { d.set(enabled, forKey: "enabled") } }
    @Published var opacity: Double { didSet { d.set(opacity, forKey: "opacity") } }
    @Published var size: Double { didSet { d.set(size, forKey: "size") } }
    @Published var activity: Double { didSet { d.set(activity, forKey: "activity") } }
    @Published var bubbleSec: Int { didSet { d.set(bubbleSec, forKey: "bubbleSec") } }
    @Published var behaviors: [String: Bool] { didSet { d.set(behaviors, forKey: "behaviors") } }
    /// 바탕화면 아이콘 위치를 읽을 자동화 권한이 거부됐는지 (설정이 아니라 상태)
    @Published var iconsDenied = false

    private init() {
        d.register(defaults: ["enabled": true, "opacity": 1.0, "size": 96.0, "activity": 0.5, "bubbleSec": 60])
        enabled = d.bool(forKey: "enabled")
        opacity = d.double(forKey: "opacity")
        size = d.double(forKey: "size")
        activity = d.double(forKey: "activity")
        bubbleSec = d.integer(forKey: "bubbleSec")
        behaviors = (d.dictionary(forKey: "behaviors") as? [String: Bool]) ?? [:]
        displays = (d.dictionary(forKey: "displays") as? [String: String]) ?? [:]
    }

    func isOn(_ id: String) -> Bool { behaviors[id] ?? true }

    /// desk.settings(...) 로 넘길 값
    var js: [String: Any] {
        var b: [String: Bool] = [:]
        PetSettings.behaviors.forEach { b[$0.id] = isOn($0.id) }
        if iconsDenied { b["icons"] = false }
        return ["enabled": enabled, "size": size, "activity": activity, "bubbleSec": bubbleSec, "behaviors": b]
    }

    /// 사용자가 고른 디스플레이 {고양이 key: 디스플레이 UUID}. 없는 고양이는 자동으로 나눈다
    @Published var displays: [String: String] { didSet { d.set(displays, forKey: "displays") } }

    /// 고양이 위치와 고정 여부 (desk-view.js 가 보내 준 그대로)
    var savedCats: [String: Any] {
        get { d.dictionary(forKey: "cats") ?? [:] }
        set { d.set(newValue, forKey: "cats") }
    }
}
