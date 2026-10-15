// 디스플레이 하나를 덮는 투명 패널 (디스플레이마다 하나씩, Stages.swift). 메뉴 막대보다 위에 떠서 고양이가 창 위와 메뉴 막대에도 올라갈 수 있다.
// 고양이(와 말풍선)가 있는 곳만 마우스를 받고, 나머지 클릭은 모두 아래로 통과시킨다.
import Cocoa
import WebKit

final class PetWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }   // 다른 앱을 쓰는 중에도 첫 클릭으로 바로 집는다
}

final class PetPanel: NSPanel {
    let web: PetWebView
    /// JS 가 보낸 고양이·말풍선 사각형 (패널 왼쪽 위 기준 px)
    var hitRects: [CGRect] = []
    var dragging = false
    var menuOpen = false

    init(screen: NSScreen) {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        web = PetWebView(frame: .zero, configuration: config)
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isMovable = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        web.setValue(false, forKey: "drawsBackground")
        web.autoresizingMask = [.width, .height]
        contentView = web
        fit(screen)
    }

    override var canBecomeKey: Bool { true }

    /// 디스플레이 전체(메뉴 막대 포함)에 맞춘다
    func fit(_ screen: NSScreen) {
        setFrame(screen.frame, display: true)
    }

    func load() {
        web.loadFileURL(Paths.page, allowingReadAccessTo: Paths.web)
    }

    /// 화면 좌표(왼쪽 아래 원점)의 점을 패널 왼쪽 위 기준 px 로
    func local(_ p: NSPoint) -> CGPoint {
        CGPoint(x: p.x - frame.minX, y: frame.maxY - p.y)
    }

    /// 마우스가 고양이 위에 있을 때만 클릭을 받는다
    func updatePassThrough(mouse: CGPoint) {
        let hit = dragging || menuOpen || hitRects.contains { $0.insetBy(dx: -2, dy: -2).contains(mouse) }
        if ignoresMouseEvents == hit { ignoresMouseEvents = !hit }
    }
}
