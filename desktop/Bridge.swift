// 화면(JS)과 앱 사이의 말 전달. 디스플레이(무대)마다 하나씩 있다.
// JS → 앱: window.webkit.messageHandlers.cat.postMessage({type, ...})
// 앱 → JS: desk.settings / desk.world / desk.pin / desk.unpinAll / desk.status / desk.attention / desk.greet
import Cocoa
import WebKit

final class Bridge: NSObject, WKScriptMessageHandler {
    let panel: PetPanel
    unowned let hub: Stages
    let screenID: String
    var ready = false
    var onReady: (() -> Void)?

    init(panel: PetPanel, hub: Stages, screenID: String) {
        self.panel = panel
        self.hub = hub
        self.screenID = screenID
        super.init()
        panel.web.configuration.userContentController.add(self, name: "cat")
        addBootScript()
    }

    static func json(_ obj: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes, .fragmentsAllowed]),
              let s = String(data: data, encoding: .utf8) else { return "null" }
        return s
    }

    /// fn(인자, ...) 를 부른다. 인자는 하나씩 JSON 으로 바꿔 넣는다
    func call(_ fn: String, _ args: Any...) { call(fn, args: args) }
    func call(_ fn: String, args: [Any]) {
        guard ready else { return }
        panel.web.evaluateJavaScript(fn + "(" + args.map(Bridge.json).joined(separator: ",") + ")", completionHandler: nil)
    }

    func pushSettings() { call("desk.settings", hub.js(for: screenID)) }
    func pushWorld(_ world: [String: Any]) { call("desk.world", world) }

    func reload() {
        ready = false
        panel.hitRects = []
        panel.web.configuration.userContentController.removeAllUserScripts()
        addBootScript()                                         // 다시 읽을 때도 지금 위치와 설정을 쓴다
        panel.load()
    }

    /// 저장해 둔 위치·고정과 설정을 페이지 스크립트보다 먼저 넣는다
    private func addBootScript() {
        let boot = "window.DESKTOP_SAVED=" + Bridge.json(["cats": hub.settings.savedCats]) + ";" +
                   "window.DESKTOP_SETTINGS=" + Bridge.json(hub.js(for: screenID)) + ";"
        panel.web.configuration.userContentController.addUserScript(
            WKUserScript(source: boot, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    // MARK: JS → 앱

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            ready = true
            pushSettings()
            onReady?()
        case "rects":
            let rects = (body["rects"] as? [[Double]]) ?? []
            panel.hitRects = rects.filter { $0.count == 4 }.map { CGRect(x: $0[0], y: $0[1], width: $0[2] - $0[0], height: $0[3] - $0[1]) }
        case "drag":
            panel.dragging = (body["on"] as? Bool) ?? false
        case "save":                                            // 이 화면에 있는 고양이 것만 온다
            if let cats = body["cats"] as? [String: Any] {
                hub.settings.savedCats = hub.settings.savedCats.merging(cats) { $1 }
            }
        case "ack":
            if let key = body["key"] as? String { hub.onAck?(key) }
        case "menu":
            if let key = body["key"] as? String {
                hub.menu.show(from: self, key: key, name: body["name"] as? String ?? key, pinned: body["pinned"] as? Bool ?? false)
            }
        case "thumbs":
            if let items = body["items"] as? [String: Any] { hub.store.setThumbs(items) }
        case "lines":
            if let items = body["items"] as? [String: Any] { hub.store.setLines(items) }
        case "action":
            if let key = body["key"] as? String, let act = body["act"] as? String {
                let name = hub.store.cats.first { $0.key == key }?.name ?? key
                Bridge.logAction(name: name.isEmpty ? key : name, key: key, act: act)
            }
        default:
            break
        }
    }

    /// 행동 기록 한 줄: ~/Library/Logs/고양이팀/actions.log
    private static let actionLog: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/고양이팀")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("actions.log")
    }()
    private static let iso = ISO8601DateFormatter()

    static func logAction(name: String, key: String, act: String) {
        let line = Data([iso.string(from: Date()), name, key, act].joined(separator: "\t").appending("\n").utf8)
        if let h = try? FileHandle(forWritingTo: actionLog) {
            h.seekToEndOfFile(); h.write(line); h.closeFile()
        } else {
            try? line.write(to: actionLog)
        }
    }
}
