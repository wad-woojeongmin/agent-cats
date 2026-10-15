// 메뉴 막대 아이콘과 설정 팝오버.
// 홈(펫 활성화) → 팀원 관리 / 행동 설정 / 기타 설정
import Cocoa
import SwiftUI

enum Page: Hashable {
    case team, behavior, other, edit(String)
}

final class Router: ObservableObject {
    @Published var path: [Page] = []
}

final class StatusMenu: NSObject {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let popover = NSPopover()
    let router = Router()
    let store: TeamStore

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
        popover.contentSize = NSSize(width: 380, height: 470)
        popover.behavior = .transient
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
    }
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
        .frame(width: 380, height: 470)
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
