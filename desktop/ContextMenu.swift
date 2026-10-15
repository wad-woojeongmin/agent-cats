// 고양이 우클릭 메뉴. 메뉴를 띄운 무대(Bridge)와 고양이 key 를 기억했다가 고른 일을 한다.
import Cocoa

final class ContextMenu: NSObject {
    unowned let stages: Stages
    private var menuKey = ""
    private weak var menuStage: Bridge?

    init(stages: Stages) {
        self.stages = stages
    }

    func show(from bridge: Bridge, key: String, name: String, pinned: Bool) {
        menuKey = key
        menuStage = bridge
        let menu = NSMenu()
        let title = NSMenuItem(title: name, action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(item(pinned ? "고정 풀기" : "여기에 고정", "pin.fill", #selector(togglePin), tag: pinned ? 0 : 1))
        if stages.displays.count > 1 {
            let send = NSMenuItem(title: "다른 디스플레이로 보내기", action: nil, keyEquivalent: "")
            send.image = NSImage(systemSymbolName: "display.2", accessibilityDescription: nil)
            let sub = NSMenu()
            for (i, d) in stages.displays.enumerated() where d.id != stages.assign[key] {
                let it = item(d.name + (i == 0 ? " (주 화면)" : ""), "display", #selector(sendTo))
                it.representedObject = d.id
                sub.addItem(it)
            }
            send.submenu = sub
            menu.addItem(send)
        }
        menu.addItem(.separator())
        menu.addItem(item("이 고양이 숨기기", "eye.slash", #selector(hideCat)))
        menu.addItem(item("팀원 관리 열기", "person.2", #selector(openTeam)))
        bridge.panel.menuOpen = true                            // 메뉴가 떠 있는 동안 패널이 클릭을 놓치지 않게
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        bridge.panel.menuOpen = false
    }

    private func item(_ title: String, _ symbol: String, _ action: Selector, tag: Int = 0) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: "")
        it.target = self
        it.tag = tag
        it.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return it
    }

    @objc private func togglePin(_ sender: NSMenuItem) { menuStage?.call("desk.pin", menuKey, sender.tag == 1) }
    @objc private func sendTo(_ sender: NSMenuItem) { stages.choose(menuKey, display: sender.representedObject as? String) }
    @objc private func hideCat() { stages.store.setHidden(menuKey, true) }
    @objc private func openTeam() { stages.onOpenTeam?() }
}
