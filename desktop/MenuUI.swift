// 메뉴 막대 아이콘과 설정 팝오버.
// 홈(펫 활성화·투명도·크기) → 팀원 관리 / 행동 설정 / 기타 설정
import Cocoa
import SwiftUI

enum Page: Hashable {
    case team, behavior, other, edit(String)
}

final class Router: ObservableObject {
    @Published var path: [Page] = []
    func pop() { if !path.isEmpty { path.removeLast() } }
}

final class StatusMenu: NSObject, NSPopoverDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let popover = NSPopover()
    let router = Router()
    let store: TeamStore
    private var monitors: [Any] = []                             // 팝오버 떠 있는 동안만 바깥 클릭 감시

    init(store: TeamStore, settings: PetSettings, feed: StatusFeed, stages: Stages) {
        self.store = store
        super.init()
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "cat.fill", accessibilityDescription: "고양이 팀")
            if button.image == nil { button.title = "🐱" }
            button.target = self
            button.action = #selector(toggle)
        }
        let root = MenuRoot(router: router)
            .environmentObject(router)
            .environmentObject(store)
            .environmentObject(settings)
            .environmentObject(feed)
            .environmentObject(stages)
        popover.contentViewController = NSHostingController(rootView: root)
        popover.contentSize = NSSize(width: 380, height: 520)
        popover.behavior = .transient
        popover.delegate = self
    }

    @objc func toggle() {
        if popover.isShown { popover.performClose(nil) } else { open(nil) }
    }

    func open(_ page: Page?) {
        store.load()                                             // 손으로 고친 팀.json 도 바로 보이게
        router.path = page.map { [$0] } ?? []
        guard let button = item.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        watchOutsideClicks()
    }

    // 액세서리 앱이라 .transient 만으로는 바탕화면·다른 앱·고양이 패널 클릭에 안 닫힐 때가 있어 직접 닫는다
    private func watchOutsideClicks() {
        removeMonitors()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            self?.popover.performClose(nil)                      // 다른 앱·바탕화면
        }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            if let self, self.isOutside(event.window) { self.popover.performClose(nil) }
            return event
        }) { monitors.append(l) }
    }

    // 팝오버 자신과 거기서 뜬 창(시트·확인 대화상자·Picker/Menu 팝업)은 안쪽으로 친다.
    // 팝업 메뉴 창은 부모 연결이 없어 클래스 이름("Menu")으로 거른다.
    // 메뉴 막대 버튼 클릭은 toggle() 이 닫게 둔다 (여기서 닫으면 toggle 이 다시 연다).
    private func isOutside(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        let pop = popover.contentViewController?.view.window
        if window === pop || window === item.button?.window { return false }
        if let pop, window.parent === pop || window.sheetParent === pop
            || pop.childWindows?.contains(where: { $0 === window }) == true { return false }
        if NSStringFromClass(type(of: window)).contains("Menu") { return false }
        return true                                              // 고양이 패널 등 우리 앱의 다른 창
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    func popoverDidClose(_ notification: Notification) { removeMonitors() }
}

// MARK: - 화면들

struct MenuRoot: View {
    @ObservedObject var router: Router

    var body: some View {
        NavigationStack(path: $router.path) {
            HomeView()
                .navigationDestination(for: Page.self) { page in
                    switch page {
                    case .team: TeamView()
                    case .behavior: BehaviorView()
                    case .other: OtherView()
                    case .edit(let key): CatEditor(key: key)
                    }
                }
        }
        .frame(width: 380, height: 520)
    }
}

struct HomeView: View {
    @EnvironmentObject var store: TeamStore
    @EnvironmentObject var settings: PetSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Thumb(image: store.cats.first.flatMap { store.thumbs[$0.key] }, size: 34)
                Text("우리 팀 고양이들").font(.title3.weight(.semibold))
                Spacer()
            }
            GroupBox {
                VStack(spacing: 0) {
                    HStack {
                        Label("펫 활성화", systemImage: "pawprint.fill")
                        Spacer()
                        Toggle("", isOn: $settings.enabled).toggleStyle(.switch).labelsHidden()
                    }
                    .padding(.vertical, 6)
                    Divider()
                    SliderRow(title: "투명도", symbol: "circle.lefthalf.filled", value: $settings.opacity, range: 0.2...1,
                              text: "\(Int(settings.opacity * 100))%")
                    SliderRow(title: "크기", symbol: "arrow.up.left.and.arrow.down.right", value: $settings.size, range: 64...166,
                              step: 2, text: "\(Int(settings.size))px")
                    Divider()
                    NavRow(title: "팀원 관리", symbol: "person.2", page: .team)
                    Divider()
                    NavRow(title: "행동 설정", symbol: "figure.walk", page: .behavior)
                    Divider()
                    NavRow(title: "기타 설정", symbol: "gearshape", page: .other)
                }
                .padding(.horizontal, 4)
            }
            if let error = store.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Spacer()
            HStack {
                Text("\(store.cats.filter { !$0.hidden }.count)마리가 데스크톱에 있어요")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("종료") { NSApp.terminate(nil) }
            }
        }
        .padding(18)
    }
}

/// 홈의 슬라이더 한 줄 (투명도·크기)
struct SliderRow: View {
    let title: String
    let symbol: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    let text: String

    var body: some View {
        HStack {
            Label(title, systemImage: symbol).frame(width: 90, alignment: .leading)
            if let step { Slider(value: $value, in: range, step: step) } else { Slider(value: $value, in: range) }
            Text(text).monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }
}

/// 하위 화면 머리줄. 팝오버엔 창 툴바가 없어 navigationTitle·toolbar 가 안 보여서 직접 그린다
struct PageHeader<Trailing: View>: View {
    @EnvironmentObject var router: Router
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack {
            Button { router.pop() } label: {
                HStack(spacing: 2) { Image(systemName: "chevron.left"); Text("뒤로") }
            }
            .buttonStyle(.borderless)
            Spacer()
            trailing()
        }
        .overlay(Text(title).font(.headline).lineLimit(1).padding(.horizontal, 70))
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String) { self.init(title: title) { EmptyView() } }
}

struct NavRow: View {
    let title: String
    let symbol: String
    let page: Page

    var body: some View {
        NavigationLink(value: page) {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

struct Thumb: View {
    let image: NSImage?
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).interpolation(.none).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "cat").foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}
