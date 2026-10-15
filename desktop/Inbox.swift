// 고양이 추가 요청함. Claude Code 의 cat-add 스킬이 inbox/ 에 {"folder", "name", "role"} JSON 을 넣으면 읽고 지운다.
// 폴더가 바뀔 때마다(파일이 들어오거나 나갈 때) 한 번씩, 그리고 켤 때 한 번 훑는다.
import Foundation

final class Inbox {
    private let dir: URL
    private let onRequest: (_ folder: String, _ name: String, _ role: String) -> Void   // 메인 스레드에서 부른다
    private let queue = DispatchQueue(label: "local.catteam.inbox")
    private var source: DispatchSourceFileSystemObject?

    init(dir: URL, onRequest: @escaping (_ folder: String, _ name: String, _ role: String) -> Void) {
        self.dir = dir
        self.onRequest = onRequest
    }

    func start() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: queue)
        src.setEventHandler { [weak self] in self?.drain() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
        queue.async { [weak self] in self?.drain() }
    }

    /// *.json 만 본다. 숨김 파일(스킬이 쓰는 중인 임시 파일)은 건너뛴다. 읽은 파일은 맞든 틀리든 지운다
    private func drain() {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        for n in names.sorted() where !n.hasPrefix(".") && n.hasSuffix(".json") {
            let url = dir.appendingPathComponent(n)
            defer { try? fm.removeItem(at: url) }
            guard let data = try? Data(contentsOf: url),
                  let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let raw = d["folder"] as? String else { NSLog("고양이팀: 읽지 못한 추가 요청을 버렸어요"); continue }
            var folder = raw
            while folder.count > 1 && folder.hasSuffix("/") { folder.removeLast() }
            guard folder.hasPrefix("/"), folder != "/" else { NSLog("고양이팀: 폴더가 절대 경로가 아닌 추가 요청을 버렸어요"); continue }
            let name = (d["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let role = (d["role"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async { [weak self] in self?.onRequest(folder, name, role) }
        }
    }
}
