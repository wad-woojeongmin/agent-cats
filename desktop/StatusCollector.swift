// 고양이 팀 상태 수집기. 수집.py 를 그대로 옮긴 것 (AppKit 없이, tests/collector_parity.sh 로 수집.py 와 결과를 맞춰 본다).
// 읽는 것: 세션 제목, 작업 폴더 경로, 마지막 활동 시각, 마지막 도구 이름과 대상, 마지막 보고의 첫 문장. 저장하거나 밖으로 보내지 않는다.
//  - 글자 수는 파이썬처럼 코드 포인트로 센다 (Character 가 아니라 unicodeScalars)
//  - 공백·줄바꿈은 파이썬 str.isspace / str.splitlines 와 같은 글자로 본다
//  - 부분 일치는 바이트(UTF-8)로 본다. Swift 문자열 비교는 정규화(NFC/NFD)를 같게 봐서 파이썬과 달라진다
//  - 디렉터리는 readdir 순서 그대로 (파이썬 glob 과 같은 순서라야 동점일 때 같은 세션을 고른다)
import Foundation

final class StatusCollector {
    static let runningWithin = 300.0     // 초. 턴을 모를 때만: 이 안에 기록이 움직였으면 일하는 중
    static let openTurnMax = 45.0 * 60   // 초. 턴이 안 끝났으면 기록이 조용해도 이만큼은 일하는 중. 끝난 턴은 바로 쉼
    static let tail = 900_000

    private let teamURL: URL
    private let meta: String
    private let projects: String
    private var cwdCache: [String: String] = [:]   // 작업 폴더는 세션 동안 안 바뀐다. 한 번 찾으면 기억. collect() 는 StatusFeed 직렬 큐에서만 불려 잠금 없음

    init(teamURL: URL) {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()   // expanduser 처럼 HOME 먼저
        self.teamURL = teamURL
        self.meta = home + "/Library/Application Support/Claude/claude-code-sessions"
        self.projects = home + "/.claude/projects"
    }

    /// 시험용: 세션 폴더를 바꿔 끼운다
    init(teamURL: URL, metaDir: String, projectsDir: String) {
        self.teamURL = teamURL
        self.meta = metaDir
        self.projects = projectsDir
    }

    /// 팀.json 을 읽어 한 번 수집한다. 반환값은 수집.py 가 status.js 에 window.CATTEAM 으로 쓰는 객체와 같은 모양:
    /// ["title", "catWidth", "columns", "staleSec", "updated", "cats" (match 를 뺀 고양이 설정들), "status" ([key: 상태])]
    /// 팀.json 을 못 읽으면 throw.
    func collect() throws -> [String: Any] { try collectAll().data }

    /// collect() 에 더해 고양이마다 따라간 세션 (key → 세션 id, 작업 폴더). 세션을 못 찾은 고양이는 없다.
    /// 세션은 앱 안(우클릭 "작업 열기")에서만 쓰고 화면(JS)으로는 보내지 않는다.
    /// attention: 사용자 차례인 고양이 (key → 종류 "reply"|"question", 그 일을 가리키는 stamp). 화면에는 종류만 간다
    func collectAll() throws -> (data: [String: Any], sessions: [String: (id: String, cwd: String)],
                                 attention: [String: (kind: String, stamp: String)]) {
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: teamURL))
        guard let cfg = obj as? [String: Any], let rawCats = cfg["cats"] as? [Any] else { throw CocoaError(.fileReadCorruptFile) }
        let cats = try rawCats.map { c -> [String: Any] in
            guard let d = c as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
            return d
        }
        let logs = projectLogs()
        let sessions = allSessions(logs)
        var status: [String: Any] = [:]
        var following: [String: (id: String, cwd: String)] = [:]
        var attention: [String: (kind: String, stamp: String)] = [:]
        for c in cats where truthy(c["match"]) {
            guard let key = c["key"] as? String else { throw CocoaError(.fileReadCorruptFile) }   // 파이썬도 key 가 없으면 멈춘다
            let r = build(c, sessions, logs)
            status[key] = r.status
            if let s = r.session, !s.cli.isEmpty { following[key] = (s.cli, s.cwd) }
            if r.session != nil, let a = r.attention { attention[key] = a }
        }
        let pub = cats.map { $0.filter { $0.key != "match" } }
        func get(_ k: String, _ def: Any) -> Any { cfg.index(forKey: k).map { cfg[$0].value } ?? def }   // 있으면 null 이어도 그대로
        return (["title": get("title", ""), "catWidth": get("catWidth", 166), "columns": get("columns", 3),
                 "staleSec": get("staleSec", 60), "updated": nowMs(), "cats": pub, "status": status], following, attention)
    }

    /// "작업 열기" 용 .command 내용: 작업 폴더로 가서 세션을 이어 연다. id 는 [A-Za-z0-9-] 만, 폴더는 zsh 작은따옴표로 감싼다
    static func resumeScript(cwd: String, id: String) -> String? {
        guard !id.isEmpty, id.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-") }),
              cwd.hasPrefix("/") else { return nil }
        let quoted = "'" + cwd.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "#!/bin/zsh -il\ncd \(quoted) && exec claude --resume \(id)\n"
    }

    // MARK: 세션 찾기

    private struct Session {
        let title: String
        let cwd: String
        let cli: String
        let last: NSNumber
        let titleL: [UInt8]
        let cwdL: [UInt8]
        init(title: String, cwd: String, cli: String, last: NSNumber) {
            self.title = title; self.cwd = cwd; self.cli = cli; self.last = last
            titleL = Array(title.lowercased().utf8)
            cwdL = Array(cwd.lowercased().utf8)
        }
    }

    /// projects/*/*.jsonl. first: 파일 이름 → 처음 나온 (있는) 경로. find_log 의 glob 과 같은 순서
    private struct Logs {
        var files: [(path: String, stem: String)] = []
        var first: [String: String] = [:]
    }

    private func projectLogs() -> Logs {
        var logs = Logs()
        for d in listDir(projects) where isDir(projects + "/" + d) {
            for n in listDir(projects + "/" + d) where endsWith(n, ".jsonl") {
                let path = projects + "/" + d + "/" + n
                logs.files.append((path, pyStem(n)))
                if logs.first[n] == nil && statOf(path) != nil { logs.first[n] = path }
            }
        }
        return logs
    }

    private func allSessions(_ logs: Logs) -> [Session] {
        var metas: [[String: Any]] = []
        for a in listDir(meta) where isDir(meta + "/" + a) {
            for b in listDir(meta + "/" + a) where isDir(meta + "/" + a + "/" + b) {
                for n in listDir(meta + "/" + a + "/" + b) where n.utf8.count >= 11 && startsWith(n, "local_") && endsWith(n, ".json") {
                    guard let data = try? Data(contentsOf: URL(fileURLWithPath: meta + "/" + a + "/" + b + "/" + n)),
                          let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
                    metas.append(d)
                }
            }
        }
        let known = Set(metas.compactMap { $0["cliSessionId"] as? String })
        var out = metas.filter { !truthy($0["isArchived"]) }.map {
            Session(title: str($0["title"]), cwd: str($0["cwd"]), cli: str($0["cliSessionId"]), last: num($0["lastActivityAt"]))
        }
        // 앱 목록에 없는 세션(터미널 등)도 기록 파일에서 찾는다. 최근 이틀 안에 움직인 것만
        for f in logs.files where !known.contains(f.stem) {
            guard let st = statOf(f.path) else { continue }
            let mt = mtime(st)
            if Date().timeIntervalSince1970 - mt > 2 * 86400 { continue }
            guard let cwd = try? findCwd(f.path, Int(st.st_size)), !cwd.isEmpty else { continue }
            out.append(Session(title: "", cwd: cwd, cli: f.stem, last: NSNumber(value: Int64(mt * 1000))))
        }
        return out
    }

    /// 끝부분에 없으면 앞부분을 읽는다. 끝에서 찾으면 마지막 것, 앞에서 찾으면 첫 것
    private func findCwd(_ path: String, _ size: Int) throws -> String {
        if let cached = cwdCache[path] { return cached }
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { throw CocoaError(.fileReadUnknown) }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) != S_IFDIR else { throw CocoaError(.fileReadUnknown) }
        for offset in [max(0, size - 60_000), 0] {
            let chunk = cleanUTF8(try readFD(fd, offset: offset, max: 200_000))
            let hits = cwdHits(chunk)
            if !hits.isEmpty {
                let v = offset != 0 ? hits.last! : hits[0]
                cwdCache[path] = v
                return v
            }
        }
        return ""
    }

    /// 정규식 "cwd":"([^"]+)" 의 findall
    private func cwdHits(_ b: [UInt8]) -> [String] {
        let pat = Array("\"cwd\":\"".utf8)
        var out: [String] = []
        var i = 0
        while i + pat.count <= b.count {
            if b[i] == 0x22 && b[i ..< i + pat.count].elementsEqual(pat) {
                let j = i + pat.count
                guard let k = b[j...].firstIndex(of: 0x22) else { break }
                if k > j {
                    out.append(String(decoding: b[j ..< k], as: UTF8.self))
                    i = k + 1
                    continue
                }
            }
            i += 1
        }
        return out
    }

    private func findSessions(_ sessions: [Session], _ needles: [String]) -> [Session] {
        let ns = needles.map { Array($0.lowercased().utf8) }
        return sessions.filter { s in ns.contains { contains(s.titleL, $0) || contains(s.cwdL, $0) } }
    }

    private func activity(_ s: Session, _ logs: Logs) -> (log: String?, last: NSNumber) {
        let log = logs.first[s.cli + ".jsonl"]
        var last = s.last
        if let log, let st = statOf(log) {
            let ms = Int64(mtime(st) * 1000)
            if Double(ms) > last.doubleValue { last = NSNumber(value: ms) }   // max(a, b): 같으면 a
        }
        return (log, last)
    }

    // MARK: 상태 만들기

    static let askTools: Set<String> = ["AskUserQuestion", "ExitPlanMode"]   // 사용자 답을 기다리는 도구

    /// 상태, 고른 세션 (못 찾으면 nil), 사용자 차례인지 (status 에는 넣지 않는다. 수집.py 와 같아야 해서)
    private func build(_ cat: [String: Any], _ sessions: [Session], _ logs: Logs)
        -> (status: [String: Any], session: Session?, attention: (kind: String, stamp: String)?) {
        let now = nowMs()
        let found = findSessions(sessions, needles(cat["match"]))
        guard var s = found.first else { return (["state": "missing", "now": now], nil, nil) }
        var act = activity(s, logs)
        for d in found.dropFirst() {
            let a = activity(d, logs)
            if a.last.doubleValue > act.last.doubleValue { s = d; act = a }
        }
        var tool = "", tinp: Any? = nil, said = "", turnOpen: Bool? = nil
        var reply: String?, question: String?, answered = Set<String>(), prompted = false   // 뒤에서부터: 답한 도구 id, 그 뒤 새 질문을 했는지
        var seen = false, done = false   // seen: 마지막 대화 줄을 봤는지. done: 수집.py 가 멈추는 곳을 지났는지 (그 뒤로는 "!" 만 찾는다)
        if let log = act.log {
            tailEvents(log) { ev in
                let type = ev["type"] as? String
                let main = (type == "user" || type == "assistant") && !truthy(ev["isMeta"]) && !truthy(ev["isSidechain"])
                let msg = ev["message"] as? [String: Any] ?? [:]
                if !seen, main {
                    seen = true
                    let open = type == "user" ? !Self.interrupted(msg) : msg["stop_reason"] as? String != "end_turn"
                    if !done { turnOpen = open }
                    if !open, type == "assistant" { reply = Self.stamp(ev) }   // 끊어서 닫힌 턴은 답이 아님
                }
                if main, type == "user" {
                    let parts = msg["content"] as? [Any] ?? [msg["content"] as Any]
                    for p in parts {
                        if let d = p as? [String: Any], d["type"] as? String == "tool_result" { answered.insert(str(d["tool_use_id"])) } else { prompted = true }
                    }
                }
                guard type == "assistant", let content = msg["content"] as? [Any] else { return done && seen }
                for case let part as [String: Any] in content {
                    let ptype = part["type"] as? String
                    if question == nil, main, !prompted, ptype == "tool_use", Self.askTools.contains(str(part["name"])),
                       !answered.contains(str(part["id"])) { question = Self.stamp(ev) }
                    if tool.isEmpty && ptype == "tool_use" {
                        tool = part["name"] as? String ?? ""
                        tinp = part["input"]
                    }
                    if said.isEmpty && ptype == "text" { said = Self.firstLine(part["text"] as? String ?? "") }
                }
                done = done || (!tool.isEmpty && !said.isEmpty)
                return done && seen
            }
        }
        let age = (Double(now) - act.last.doubleValue) / 1000
        // 턴을 알면 턴만 본다 (막 끝난 턴은 기록이 새것이어도 쉼). 모르면 (기록 없음 등) 최근에 움직였는지로
        let running = turnOpen.map { $0 && age < Self.openTurnMax } ?? (age < Self.runningWithin)
        var out: [String: Any] = ["state": running ? "working" : "idle", "title": s.title,
                                  "folder": basename(rstrip(s.cwd, "/")),
                                  "doing": tool.isEmpty ? "" : Self.describe(tool, tinp), "step": Self.firstSentence(said),
                                  "last": act.last, "now": now]
        if truthy(cat["private"]) {
            // 민감한 정보가 오갈 수 있는 팀: 보고 문장, 폴더 이름, 파일 이름은 싣지 않고 일반적인 말만 싣는다
            out["step"] = ""
            out["folder"] = ""
            out["title"] = ""
            out["doing"] = tool.isEmpty ? "" : Self.phrase(tool)
        }
        return (out, s, question.map { ("question", $0) } ?? reply.map { ("reply", $0) })
    }

    /// 사용자가 끊은 줄 (Esc): "[Request interrupted by user]", "... for tool use]"
    private static func interrupted(_ msg: [String: Any]) -> Bool {
        let c = msg["content"]
        let text = (c as? [Any]).map { parts in
            parts.compactMap { ($0 as? [String: Any]).flatMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil } }.joined()
        } ?? c as? String
        return text?.hasPrefix("[Request interrupted by user") ?? false
    }

    /// 기록 한 줄을 가리키는 값: uuid, 없으면 timestamp
    private static func stamp(_ ev: [String: Any]) -> String { [str(ev["uuid"]), str(ev["timestamp"])].first { !$0.isEmpty } ?? "" }

    /// match 가 문자열이면 파이썬처럼 한 글자씩 본다
    private func needles(_ m: Any?) -> [String] {
        guard truthy(m) else { return [] }
        if let s = m as? String { return s.unicodeScalars.map { String($0) } }
        return (m as? [Any] ?? []).compactMap { $0 as? String }
    }

    /// 기록 끝 TAIL 바이트를 거꾸로 한 줄씩. 잘라 읽었으면 첫 줄(조각)은 버린다. visit 가 true 면 멈춘다
    private func tailEvents(_ path: String, _ visit: ([String: Any]) -> Bool) {
        guard let st = statOf(path) else { return }
        let size = Int(st.st_size)
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return }
        let raw = cleanUTF8((try? readFD(fd, offset: max(0, size - Self.tail), max: nil)) ?? [])
        close(fd)
        var lines = byteLines(raw)
        if size > Self.tail && !lines.isEmpty { lines.removeFirst() }
        for r in lines.reversed() {
            guard let ev = (try? JSONSerialization.jsonObject(with: Data(raw[r]), options: .fragmentsAllowed)) as? [String: Any] else { continue }
            if visit(ev) { return }
        }
    }

    // MARK: 말 만들기

    static let toolPhrase: [(NSRegularExpression, String)] = [
        ("figma", "피그마에서 작업하는 중"),
        ("^(Edit|Write|NotebookEdit)$", "파일을 고치는 중"),
        ("^(Read|Grep|Glob)$", "자료를 읽는 중"),
        ("^Bash$", "명령을 돌리는 중"),
        ("WebSearch|WebFetch|browser|playwright|chrome", "웹에서 찾아보는 중"),
        ("^(Agent|Workflow|Task)$", "다른 에이전트에게 일 시키는 중"),
        ("Artifact", "아티팩트를 올리는 중"),
        ("slack|gmail|calendar|drive", "연결된 앱을 보는 중"),
    ].map { pat, text in
        // 파이썬 $ 는 끝 또는 끝의 \n 앞에서만 맞는다
        (try! NSRegularExpression(pattern: pat.replacingOccurrences(of: "$", with: "(?=\\n?\\z)"), options: .caseInsensitive), text)
    }

    static let bashWords = ["ls": "폴더를 살펴보는 중", "find": "파일을 찾는 중", "grep": "내용을 찾는 중", "cat": "파일을 읽는 중",
                            "sed": "파일을 훑는 중", "curl": "요청을 보내는 중", "open": "앱을 여는 중", "sleep": "잠깐 기다리는 중",
                            "npm": "패키지 명령을 돌리는 중", "node": "스크립트를 돌리는 중", "mkdir": "폴더를 만드는 중",
                            "cp": "파일을 복사하는 중", "mv": "파일을 옮기는 중"]

    static func phrase(_ tool: String) -> String {
        let r = NSRange(tool.startIndex..., in: tool)
        for (re, text) in toolPhrase where re.firstMatch(in: tool, range: r) != nil { return text }
        return "작업을 이어가는 중"
    }

    /// 도구 이름에 대상까지 붙여서 지금 뭘 하는지 말한다
    static func describe(_ tool: String, _ input: Any?) -> String {
        let inp = input as? [String: Any] ?? [:]
        let path = [str(inp["file_path"]), str(inp["notebook_path"])].first { !$0.isEmpty } ?? ""
        let base = basename(path)
        if !base.isEmpty && ["Read", "Edit", "Write", "NotebookEdit"].contains(tool) {
            return base + (tool == "Read" ? " 읽는 중" : " 고치는 중")
        }
        if tool == "Bash" {
            let cmd = str(inp["command"])
            if contains(Array(cmd.utf8), Array("osascript".utf8)) { return "브라우저 화면을 조작하는 중" }
            if startsWithGit(cmd) { return "git 작업을 하는 중" }
            let desc = str(inp["description"])
            if hasHangul(desc) { return prefix(desc, 40) }
            if let script = pythonScript(cmd) { return basename(script) + " 돌리는 중" }
            if let first = firstToken(stripCd(strip(cmd))), let w = bashWords[first] { return w }
        }
        if tool == "Agent" || tool == "Task" {
            let desc = str(inp["description"])
            if hasHangul(desc) { return prefix(desc, 40) + " 맡기는 중" }
        }
        return phrase(tool)
    }

    /// 마크다운 기호([`*#>|_])를 빼고 [글](링크) 는 글만 남긴 첫 줄 (4글자 이상, 70글자까지)
    static func firstLine(_ text: String) -> String {
        let marks = "`*#>|_".unicodeScalars
        for line in splitLines(text) {
            let u = Array(line.unicodeScalars)
            var out = String.UnicodeScalarView()
            var i = 0
            while i < u.count {
                let c = u[i]
                if marks.contains(c) { i += 1; continue }
                if c == "[", let j = u[(i + 1)...].firstIndex(of: "]"), j + 1 < u.count, u[j + 1] == "(",
                   let k = u[(j + 2)...].firstIndex(of: ")") {
                    out.append(contentsOf: u[(i + 1) ..< j])
                    i = k + 1
                    continue
                }
                out.append(c)
                i += 1
            }
            let t = strip(String(out))
            if t.unicodeScalars.count >= 4 { return prefix(t, 70) }
        }
        return ""
    }

    /// re.split(r"(?<=[다요음임죠])\.\s|(?<=\.)\s", line, maxsplit=1)[0].rstrip(".") 를 cap 글자로 자른다
    static func firstSentence(_ line: String, cap: Int = 48) -> String {
        let u = Array(line.unicodeScalars)
        let ends = "다요음임죠".unicodeScalars
        var cut = u.count
        for i in 1 ..< max(1, u.count) {
            if ends.contains(u[i - 1]) && u[i] == "." && i + 1 < u.count && isSpace(u[i + 1]) { cut = i; break }
            if u[i - 1] == "." && isSpace(u[i]) { cut = i; break }
        }
        var sent = Array(u[0 ..< cut])
        while sent.last == "." { sent.removeLast() }
        if sent.count <= cap { return scalars(sent) }
        var head = Array(sent[0 ..< cap - 1])
        while let l = head.last, isSpace(l) { head.removeLast() }
        return scalars(head) + "…"
    }

    /// re.search(r"python3?\s+(?:-\w+\s+)*([^\s|;&<>]+\.py)", cmd) 의 group(1)
    static func pythonScript(_ cmd: String) -> String? {
        let u = Array(cmd.unicodeScalars), n = u.count
        let word = Array("python".unicodeScalars), dotPy = Array(".py".unicodeScalars)
        let stop = "|;&<>".unicodeScalars
        func capture(_ st: Int) -> String? {
            var r = st
            while r < n && !isSpace(u[r]) && !stop.contains(u[r]) { r += 1 }
            var e = r
            while e >= st + 4 {           // 가장 길게, 앞에 한 글자 이상
                if u[(e - 3) ..< e].elementsEqual(dotPy) { return scalars(Array(u[st ..< e])) }
                e -= 1
            }
            return nil
        }
        var s = 0
        while s + word.count <= n {
            defer { s += 1 }
            guard u[s ..< s + word.count].elementsEqual(word) else { continue }
            var p = s + word.count
            if p < n && u[p] == "3" { p += 1 }
            var q = p
            while q < n && isSpace(u[q]) { q += 1 }
            guard q > p else { continue }
            var stops = [q]                // (?:-\w+\s+)* 를 몇 번 먹었는지마다 시작점. 많이 먹은 것부터 시도
            var r = q
            while r < n && u[r] == "-" {
                var t = r + 1
                while t < n && isWord(u[t]) { t += 1 }
                guard t > r + 1 else { break }
                var v = t
                while v < n && isSpace(u[v]) { v += 1 }
                guard v > t else { break }
                r = v
                stops.append(r)
            }
            for st in stops.reversed() { if let c = capture(st) { return c } }
        }
        return nil
    }

    /// re.sub(r"^(cd [^;&|]+(;|&&)\s*)+", "", cmd)
    static func stripCd(_ cmd: String) -> String {
        let u = Array(cmd.unicodeScalars), n = u.count
        let cd = Array("cd ".unicodeScalars), stop = ";&|".unicodeScalars
        var p = 0
        while p + 3 <= n && u[p ..< p + 3].elementsEqual(cd) {
            var q = p + 3
            while q < n && !stop.contains(u[q]) { q += 1 }
            guard q > p + 3, q < n else { break }
            if u[q] == ";" { q += 1 } else if u[q] == "&" && q + 1 < n && u[q + 1] == "&" { q += 2 } else { break }
            while q < n && isSpace(u[q]) { q += 1 }
            p = q
        }
        return scalars(Array(u[p...]))
    }

    /// re.match(r"\s*git ", cmd)
    static func startsWithGit(_ cmd: String) -> Bool {
        Array(cmd.unicodeScalars.drop { isSpace($0) }.prefix(4)) == Array("git ".unicodeScalars)
    }

    static func firstToken(_ s: String) -> String? {
        let t = s.unicodeScalars.drop { isSpace($0) }.prefix { !isSpace($0) }
        return t.isEmpty ? nil : String(String.UnicodeScalarView(t))
    }
}

// MARK: 파이썬과 같게 보는 글자 규칙

/// str.isspace
private func isSpace(_ c: Unicode.Scalar) -> Bool {
    switch c.value {
    case 0x09 ... 0x0D, 0x1C ... 0x20, 0x85, 0xA0, 0x1680, 0x2000 ... 0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000: return true
    default: return false
    }
}

/// str.splitlines 의 줄 끝 (\r\n 은 하나)
private func isBreak(_ c: Unicode.Scalar) -> Bool {
    switch c.value {
    case 0x0A ... 0x0D, 0x1C ... 0x1E, 0x85, 0x2028, 0x2029: return true
    default: return false
    }
}

/// 정규식 \w (str): isalnum() 또는 _
private func isWord(_ c: Unicode.Scalar) -> Bool {
    if c == "_" || c.properties.numericType != nil { return true }
    switch c.properties.generalCategory {
    case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: return true
    default: return false
    }
}

private func hasHangul(_ s: String) -> Bool { s.unicodeScalars.contains { (0xAC00 ... 0xD7A3).contains($0.value) } }

private func scalars(_ u: [Unicode.Scalar]) -> String { String(String.UnicodeScalarView(u)) }

/// s[:n] (코드 포인트)
private func prefix(_ s: String, _ n: Int) -> String { String(String.UnicodeScalarView(s.unicodeScalars.prefix(n))) }

private func strip(_ s: String) -> String {
    var u = Array(s.unicodeScalars)
    while let l = u.last, isSpace(l) { u.removeLast() }
    return scalars(Array(u.drop { isSpace($0) }))
}

private func rstrip(_ s: String, _ ch: Unicode.Scalar) -> String {
    var u = Array(s.unicodeScalars)
    while u.last == ch { u.removeLast() }
    return scalars(u)
}

private func splitLines(_ s: String) -> [String] {
    let u = Array(s.unicodeScalars)
    var out: [String] = []
    var start = 0, i = 0
    while i < u.count {
        if isBreak(u[i]) {
            out.append(scalars(Array(u[start ..< i])))
            if u[i] == "\r" && i + 1 < u.count && u[i + 1] == "\n" { i += 1 }
            i += 1
            start = i
        } else {
            i += 1
        }
    }
    if start < u.count { out.append(scalars(Array(u[start...]))) }
    return out
}

/// splitlines 를 UTF-8 바이트에서 (올바른 UTF-8 이라야 한다)
private func byteLines(_ b: [UInt8]) -> [Range<Int>] {
    var out: [Range<Int>] = []
    var start = 0, i = 0
    let n = b.count
    while i < n {
        var w = 0
        switch b[i] {
        case 0x0A, 0x0B, 0x0C, 0x1C, 0x1D, 0x1E: w = 1
        case 0x0D: w = i + 1 < n && b[i + 1] == 0x0A ? 2 : 1
        case 0xC2: if i + 1 < n && b[i + 1] == 0x85 { w = 2 }
        case 0xE2: if i + 2 < n && b[i + 1] == 0x80 && (b[i + 2] == 0xA8 || b[i + 2] == 0xA9) { w = 3 }
        default: break
        }
        if w > 0 {
            out.append(start ..< i)
            i += w
            start = i
        } else {
            i += 1
        }
    }
    if start < n { out.append(start ..< n) }
    return out
}

/// decode("utf-8", "ignore"): 틀린 바이트는 가장 긴 올바른 앞부분 단위로 버린다 (파이썬과 같은 방식)
private func cleanUTF8(_ b: [UInt8]) -> [UInt8] {
    var out: [UInt8] = []
    out.reserveCapacity(b.count)
    let n = b.count
    var i = 0
    while i < n {
        let c = b[i]
        if c < 0x80 { out.append(c); i += 1; continue }
        var need = 0, lo: UInt8 = 0x80, hi: UInt8 = 0xBF
        switch c {
        case 0xC2 ... 0xDF: need = 1
        case 0xE0: need = 2; lo = 0xA0
        case 0xE1 ... 0xEC, 0xEE ... 0xEF: need = 2
        case 0xED: need = 2; hi = 0x9F
        case 0xF0: need = 3; lo = 0x90
        case 0xF1 ... 0xF3: need = 3
        case 0xF4: need = 3; hi = 0x8F
        default: i += 1; continue
        }
        var j = i + 1, ok = true
        for k in 0 ..< need {
            guard j < n else { ok = false; break }
            let d = b[j]
            if d < (k == 0 ? lo : 0x80) || d > (k == 0 ? hi : 0xBF) { ok = false; break }
            j += 1
        }
        if ok { out.append(contentsOf: b[i ..< j]) }
        i = j
    }
    return out
}

/// 코드 포인트 부분 문자열 (UTF-8 바이트로 보면 같다). 빈 needle 은 늘 맞는다
private func contains(_ h: [UInt8], _ n: [UInt8]) -> Bool {
    if n.isEmpty { return true }
    if n.count > h.count { return false }
    return h.withUnsafeBufferPointer { hb in n.withUnsafeBufferPointer { nb in memmem(hb.baseAddress!, hb.count, nb.baseAddress!, nb.count) != nil } }
}

private func startsWith(_ s: String, _ p: String) -> Bool { s.utf8.starts(with: p.utf8) }
private func endsWith(_ s: String, _ p: String) -> Bool { s.utf8.reversed().starts(with: p.utf8.reversed()) }

/// os.path.basename
private func basename(_ s: String) -> String {
    guard let i = s.utf8.lastIndex(of: 0x2F) else { return s }
    return String(s[s.utf8.index(after: i)...])
}

/// PurePath.stem (".jsonl" 처럼 점으로 시작하는 이름은 그대로)
private func pyStem(_ name: String) -> String {
    let u = Array(name.utf8)
    guard let i = u.lastIndex(of: 0x2E), i > 0, i < u.count - 1 else { return name }
    return String(decoding: u[..<i], as: UTF8.self)
}

/// 파이썬 참/거짓
private func truthy(_ v: Any?) -> Bool {
    guard let v, !(v is NSNull) else { return false }
    if let n = v as? NSNumber { return n.doubleValue != 0 }
    if let s = v as? String { return !s.isEmpty }
    if let a = v as? [Any] { return !a.isEmpty }
    if let d = v as? [String: Any] { return !d.isEmpty }
    return true
}

/// d.get(k) or ""
private func str(_ v: Any?) -> String { v as? String ?? "" }

/// d.get(k) or 0
private func num(_ v: Any?) -> NSNumber {
    guard truthy(v), let n = v as? NSNumber else { return 0 }
    return n
}

private func nowMs() -> Int { Int(Date().timeIntervalSince1970 * 1000) }

// MARK: 파일

private func statOf(_ path: String) -> stat? {
    var st = stat()
    return stat(path, &st) == 0 ? st : nil
}

private func isDir(_ path: String) -> Bool { statOf(path).map { ($0.st_mode & S_IFMT) == S_IFDIR } ?? false }

/// st_mtime (파이썬과 같은 double 계산)
private func mtime(_ st: stat) -> Double { Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) * 1e-9 }

/// readdir 순서 그대로 (scandir 와 같다). 못 열면 빈 목록
private func listDir(_ path: String) -> [String] {
    guard let d = opendir(path) else { return [] }
    defer { closedir(d) }
    var out: [String] = []
    while let e = readdir(d) {
        let name = withUnsafeBytes(of: e.pointee.d_name) { raw in
            String(decoding: raw.prefix(Int(e.pointee.d_namlen)), as: UTF8.self)
        }
        if name != "." && name != ".." { out.append(name) }
    }
    return out
}

/// offset 부터 max 바이트까지 (nil 이면 끝까지)
private func readFD(_ fd: Int32, offset: Int, max: Int?) throws -> [UInt8] {
    guard lseek(fd, off_t(offset), SEEK_SET) >= 0 else { throw CocoaError(.fileReadUnknown) }
    var out: [UInt8] = []
    var buf = [UInt8](repeating: 0, count: 1 << 16)
    while max.map({ out.count < $0 }) ?? true {
        let want = Swift.min(buf.count, max.map { $0 - out.count } ?? buf.count)
        let got = buf.withUnsafeMutableBytes { read(fd, $0.baseAddress, want) }
        if got < 0 { throw CocoaError(.fileReadUnknown) }
        if got == 0 { break }
        out.append(contentsOf: buf[0 ..< got])
    }
    return out
}
