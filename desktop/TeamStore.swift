// 팀.json 읽기/쓰기. 팀원 관리 화면이 이 저장소를 고친다.
// 모르는 항목(fixed 등)은 그대로 두고, 사람이 직접 고치기 좋게 항목 순서와 들여쓰기를 지켜서 쓴다.
import Cocoa

struct CatEntry: Identifiable {
    var raw: [String: Any]
    var id: String { key }

    var key: String { raw["key"] as? String ?? "" }
    var name: String { get { raw["name"] as? String ?? "" } set { put("name", newValue) } }
    var role: String { get { raw["role"] as? String ?? "" } set { put("role", newValue) } }
    var variant: String { get { raw["variant"] as? String ?? "white" } set { raw["variant"] = newValue } }
    var prop: String { get { raw["prop"] as? String ?? "" } set { put("prop", newValue) } }
    var task: String { get { raw["task"] as? String ?? "" } set { put("task", newValue) } }
    var isPrivate: Bool { get { raw["private"] as? Bool ?? false } set { raw["private"] = newValue ? true : nil } }
    var hidden: Bool { get { raw["hidden"] as? Bool ?? false } set { raw["hidden"] = newValue ? true : nil } }
    var fixed: Bool { raw["fixed"] != nil }
    var match: String {
        get { (raw["match"] as? [String] ?? []).joined(separator: ", ") }
        set {
            let words = newValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            raw["match"] = words.isEmpty ? nil : words
        }
    }
    var label: String { [name, role].filter { !$0.isEmpty }.joined(separator: " ") }

    private mutating func put(_ k: String, _ v: String) { raw[k] = v.isEmpty ? nil : v }
}

struct CatLine {
    var short: String
    var state: String
}

final class TeamStore: ObservableObject {
    let url: URL
    @Published var cats: [CatEntry] = []
    @Published var thumbs: [String: NSImage] = [:]
    @Published var lines: [String: CatLine] = [:]
    @Published var error: String?
    private var root: [String: Any] = [:]
    private var loaded = false
    var onSaved: (() -> Void)?

    static let variants = [("white", "흰 고양이"), ("tabby", "줄무늬"), ("gray", "회색"), ("tux", "턱시도"), ("siamese", "샴")]
    static let props = [("", "컵만"), ("headphones", "헤드폰"), ("glasses", "안경"), ("postit", "포스트잇"), ("chart", "차트"), ("paper", "종이")]

    init(url: URL) {
        self.url = url
        load()
    }

    func load() {
        do {
            let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
            guard let dict = obj as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
            root = dict
            cats = (dict["cats"] as? [[String: Any]] ?? []).map { CatEntry(raw: $0) }
            loaded = true
            error = nil
        } catch {
            loaded = false
            self.error = "팀.json 을 읽지 못했어요: \(error.localizedDescription). 고치기 전까지는 저장하지 않아요."
        }
    }

    func save() {
        guard loaded else { return }                                 // 깨진 팀.json 을 빈 목록으로 덮어쓰지 않는다
        root["cats"] = cats.map { $0.raw }
        do {
            try TeamStore.pretty(root, order: ["title", "catWidth", "columns", "staleSec", "cats"], indent: "")
                .appending("\n").write(to: url, atomically: true, encoding: .utf8)
            error = nil
            onSaved?()
        } catch {
            self.error = "팀.json 을 저장하지 못했어요: \(error.localizedDescription)"
        }
    }

    func update(_ cat: CatEntry) {
        guard let i = cats.firstIndex(where: { $0.key == cat.key }) else { return }
        cats[i] = cat
        save()
    }

    func setHidden(_ key: String, _ hidden: Bool) {
        guard let i = cats.firstIndex(where: { $0.key == key }) else { return }
        cats[i].hidden = hidden
        save()
    }

    func move(from: IndexSet, to: Int) {
        cats.move(fromOffsets: from, toOffset: to)
        save()
    }

    func delete(_ key: String) {
        cats.removeAll { $0.key == key }
        save()
    }

    /// 새 고양이. key 는 겹치지 않게 cat1, cat2 ... 로 붙인다
    func add() -> CatEntry {
        var n = cats.count + 1
        while cats.contains(where: { $0.key == "cat\(n)" }) { n += 1 }
        let variant = TeamStore.variants[n % TeamStore.variants.count].0
        let cat = CatEntry(raw: ["key": "cat\(n)", "name": "새 고양이", "role": "", "variant": variant, "match": ["찾을-말"]])
        cats.append(cat)
        save()
        return cat
    }

    // MARK: 화면(JS)에서 받는 것

    /// 썸네일: {key: {w, h, px: ["#rrggbb" 또는 ""]}}
    func setThumbs(_ items: [String: Any]) {
        if Set(items.keys) != Set(cats.map(\.key)) { load() }      // 팀.json 을 손으로 고쳤으면 다시 읽는다
        var out: [String: NSImage] = [:]
        for (key, v) in items {
            guard let d = v as? [String: Any], let w = d["w"] as? Int, let h = d["h"] as? Int,
                  let px = d["px"] as? [String], w > 0, h > 0, px.count == w * h,
                  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
            else { continue }
            for y in 0..<h {
                for x in 0..<w {
                    rep.setColor(TeamStore.color(px[y * w + x]), atX: x, y: y)
                }
            }
            let img = NSImage(size: NSSize(width: w, height: h))
            img.addRepresentation(rep)
            out[key] = img
        }
        thumbs = out
    }

    /// 디스플레이마다 자기 고양이 것만 보내므로 합친다
    func setLines(_ items: [String: Any]) {
        var out = lines
        for (key, v) in items {
            guard let d = v as? [String: Any] else { continue }
            out[key] = CatLine(short: d["short"] as? String ?? "", state: d["state"] as? String ?? "")
        }
        lines = out
    }

    private static func color(_ hex: String) -> NSColor {
        guard hex.count == 7, let v = UInt32(hex.dropFirst(), radix: 16) else { return .clear }
        return NSColor(deviceRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                       blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }

    // MARK: 순서를 지키는 JSON 쓰기

    private static let catOrder = ["key", "name", "role", "variant", "prop", "task", "match", "fixed", "private", "hidden"]

    private static func pretty(_ v: Any, order: [String] = catOrder, indent: String) -> String {
        let inner = indent + "  "
        if let d = v as? [String: Any] {
            let keys = order.filter { d[$0] != nil } + d.keys.filter { !order.contains($0) }.sorted()
            if keys.isEmpty { return "{}" }
            let body = keys.map { inner + leaf($0) + ": " + pretty(d[$0]!, indent: inner) }
            return "{\n" + body.joined(separator: ",\n") + "\n" + indent + "}"
        }
        if let a = v as? [Any] {
            if a.isEmpty { return "[]" }
            if a.allSatisfy({ $0 is String || $0 is NSNumber }) {                 // 짧은 목록(match)은 한 줄씩
                return "[\n" + a.map { inner + leaf($0) }.joined(separator: ",\n") + "\n" + indent + "]"
            }
            return "[\n" + a.map { inner + pretty($0, indent: inner) }.joined(separator: ",\n") + "\n" + indent + "]"
        }
        return leaf(v)
    }

    private static func leaf(_ v: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed, .withoutEscapingSlashes]),
              let s = String(data: data, encoding: .utf8) else { return "null" }
        return s
    }
}
