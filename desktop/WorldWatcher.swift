// 고양이가 사는 세계를 지켜보고 디스플레이(무대)별 화면(JS)에 알려 준다.
//  - 마우스: 30Hz. 고양이 위인지 보고 클릭 통과를 켜고 끈다. 마우스가 있는 디스플레이에만 위치를 보낸다(커서 쫓기)
//  - 창 목록: 1초. 창 윗변은 횃대가 된다. 창 경계는 화면 기록 권한 없이 읽을 수 있다
//  - 화면: 메뉴 막대 높이와 Dock 을 뺀 바닥 영역
//  - 바탕화면 아이콘: 10초. Finder 에 물어본다(자동화 권한)
// 창과 아이콘 좌표는 주 화면 왼쪽 위가 원점인 전역 좌표로 오므로, 디스플레이마다 그 화면 기준으로 옮겨서 보낸다.
import Cocoa

final class WorldWatcher {
    let hub: Stages
    let settings: PetSettings
    private var timers: [Timer] = []
    private var lastMouse = CGPoint(x: -1, y: -1)
    private var lastMouseSent = Date.distantPast
    private var lastWindows: [String: String] = [:]
    private var lastIcons: [String: String] = [:]
    private var icons: [CGRect] = []
    private var askingIcons = false

    init(hub: Stages, settings: PetSettings) {
        self.hub = hub
        self.settings = settings
        hub.onStageReady = { [weak self] stage in self?.sendAll(stage) }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.hub.stages.forEach { self?.sendAll($0) }
        }
    }

    func start() {
        timers = [
            Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tickMouse() },
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.tickWindows() },
            Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.tickIcons() },
        ]
        timers.forEach { RunLoop.main.add($0, forMode: .common) }        // 메뉴가 열려 있어도 돈다
    }

    func sendAll(_ stage: Stage) {
        lastWindows[stage.display.id] = nil
        lastIcons[stage.display.id] = nil
        stage.bridge.pushWorld(screenInfo(stage))
        tickWindows()
        sendIcons()
    }

    private func screenInfo(_ stage: Stage) -> [String: Any] {
        guard let screen = stage.screen else { return [:] }
        let f = screen.frame, v = screen.visibleFrame
        return [
            "screen": ["w": f.width, "h": f.height],
            "menubar": max(0, f.maxY - v.maxY),
            "floor": ["top": f.maxY - v.maxY, "bottom": f.maxY - v.minY, "left": v.minX - f.minX, "right": v.maxX - f.minX],
        ]
    }

    /// 이 디스플레이의 전역 좌표(주 화면 왼쪽 위 원점, 아래로 +) 사각형
    private func globalRect(_ stage: Stage) -> CGRect? {
        guard let f = stage.screen?.frame, let main = NSScreen.screens.first?.frame else { return nil }
        return CGRect(x: f.minX, y: main.maxY - f.maxY, width: f.width, height: f.height)
    }

    private func tickMouse() {
        let loc = NSEvent.mouseLocation
        let released = NSEvent.pressedMouseButtons == 0
        for stage in hub.stages {
            if stage.panel.dragging && released {                            // 드래그 끝을 놓친 화면이 클릭을 계속 막지 않게
                stage.panel.dragging = false
                stage.bridge.call("desk.cancelDrag")
            }
            stage.panel.updatePassThrough(mouse: stage.panel.local(loc))
        }
        guard settings.enabled, hypot(loc.x - lastMouse.x, loc.y - lastMouse.y) > 1,
              Date().timeIntervalSince(lastMouseSent) > 1.0 / 15,
              let stage = hub.stages.first(where: { $0.panel.frame.contains(loc) }) else { return }
        lastMouse = loc
        lastMouseSent = Date()
        let m = stage.panel.local(loc)
        stage.bridge.pushWorld(["mouse": ["x": m.x, "y": m.y]])
    }

    /// 디스플레이마다 그 화면에 걸친 일반 앱 창들 (앞에서 뒤 순서)
    private func tickWindows() {
        guard settings.enabled,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        var all: [(Int, CGRect)] = []
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? Int32) != me,
                  ((w[kCGWindowAlpha as String] as? Double) ?? 1) > 0.1,
                  let b = w[kCGWindowBounds as String] as? [String: Double],
                  let width = b["Width"], let height = b["Height"], width >= 120, height >= 80
            else { continue }
            all.append((w[kCGWindowNumber as String] as? Int ?? 0, CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: width, height: height)))
        }
        for stage in hub.stages {
            guard let g = globalRect(stage) else { continue }
            let wins: [[String: Any]] = all.filter { $0.1.intersects(g) }.map { id, r in
                ["id": id, "x": r.minX - g.minX, "y": r.minY - g.minY, "w": r.width, "h": r.height]
            }
            let s = Bridge.json(wins)
            guard s != lastWindows[stage.display.id] else { continue }
            lastWindows[stage.display.id] = s
            stage.bridge.pushWorld(["windows": wins])
        }
    }

    private func sendIcons() {
        for stage in hub.stages {
            guard let g = globalRect(stage) else { continue }
            let mine: [[String: Double]] = icons.filter { g.contains(CGPoint(x: $0.midX, y: $0.midY)) }.map {
                ["x": $0.minX - g.minX, "y": $0.minY - g.minY, "w": $0.width, "h": $0.height]
            }
            let s = Bridge.json(mine)
            guard s != lastIcons[stage.display.id] else { continue }
            lastIcons[stage.display.id] = s
            stage.bridge.pushWorld(["icons": mine])
        }
    }

    /// Finder 에게 바탕화면 아이콘 위치를 묻는다. 거부되면 "폴더와 놀기"를 끈 상태로 둔다
    private func tickIcons() {
        guard settings.enabled, settings.isOn("icons"), !settings.iconsDenied, !askingIcons else { return }
        askingIcons = true
        let script = """
        tell application "Finder"
          set out to ""
          repeat with p in (get desktop position of every item of desktop)
            set out to out & (item 1 of p) & "," & (item 2 of p) & ";"
          end repeat
          return out
        end tell
        """
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", script]
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            var text = "", error = ""
            do {
                try p.run()
                // 기다리기 전에 읽는다 (stderr 는 한두 줄이라 stdout 다음에 읽어도 막히지 않는다)
                text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                error = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                p.waitUntilExit()
            } catch { }
            DispatchQueue.main.async {
                guard let self else { return }
                self.askingIcons = false
                if error.contains("-1743") || error.contains("-1744") {                 // 자동화 권한 거부
                    self.settings.iconsDenied = true
                    return
                }
                let showsIcons = UserDefaults(suiteName: "com.apple.finder")?.object(forKey: "CreateDesktop") as? Bool ?? true
                self.icons = showsIcons ? text.split(separator: ";").compactMap { pair in
                    let xy = pair.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    guard xy.count == 2 else { return nil }
                    return CGRect(x: xy[0] - 32, y: xy[1] - 32, width: 64, height: 64)   // desktop position 은 아이콘 가운데
                } : []
                self.sendIcons()
            }
        }
    }
}
