// 사용자 차례("!") 찾기 시험. 프로젝트 폴더에서:
//   tests/collector_parity.sh 가 함께 돌린다
import Foundation

@main
enum AttentionTest {
    static func jl(_ o: [String: Any]) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]), encoding: .utf8)!
    }
    static func user(_ id: String, _ content: Any = "x", _ extra: [String: Any] = [:]) -> String {
        jl(["type": "user", "uuid": id, "message": ["content": content]].merging(extra) { $1 })
    }
    static func asst(_ id: String, _ parts: [[String: Any]], stop: String = "tool_use", _ extra: [String: Any] = [:]) -> String {
        jl(["type": "assistant", "uuid": id, "message": ["content": parts, "stop_reason": stop]].merging(extra) { $1 })
    }
    static func ask(_ id: String, _ name: String = "AskUserQuestion") -> [String: Any] { ["type": "tool_use", "id": id, "name": name, "input": [:]] }
    static func result(_ id: String) -> [[String: Any]] { [["type": "tool_result", "tool_use_id": id, "content": "ok"]] }
    static let text: [String: Any] = ["type": "text", "text": "끝났어요"]

    static func main() throws {
        let cases: [(String, [String], String?)] = [            // 이름, 기록, 기대 ("종류:stamp" 또는 없음)
            ("end_turn", [user("u1"), asst("a1", [text], stop: "end_turn")], "reply:a1"),
            ("질문 대기", [user("u1"), asst("a1", [text]), asst("a2", [ask("t1")])], "question:a2"),
            ("계획 승인 대기", [user("u1"), asst("a1", [ask("t1", "ExitPlanMode")])], "question:a1"),
            ("질문에 답함 → 일하는 중", [user("u1"), asst("a1", [ask("t1")]), user("u2", result("t1"))], nil),
            ("질문에 답하고 끝남", [user("u1"), asst("a1", [ask("t1")]), user("u2", result("t1")), asst("a2", [text], stop: "end_turn")], "reply:a2"),
            ("다른 도구 결과만", [user("u1"), asst("a1", [ask("t1")]), asst("a2", [["type": "tool_use", "id": "t2", "name": "Read", "input": [:]]]),
                            user("u2", result("t2"))], "question:a1"),
            ("새로 물어봄 (답 없는 옛 질문)", [user("u1"), asst("a1", [ask("t1")]), user("u2", "새 질문")], nil),
            ("열린 턴", [asst("a1", [text], stop: "end_turn"), user("u1")], nil),
            ("도구 쓰는 중", [user("u1"), asst("a1", [["type": "tool_use", "id": "t1", "name": "Bash", "input": [:]]])], nil),
            ("메타·곁가지는 안 봄", [user("u1"), asst("a1", [text], stop: "end_turn"), user("m1", "x", ["isMeta": true]),
                              asst("s1", [ask("t9")], ["isSidechain": true]), asst("s2", [text], stop: "end_turn", ["isSidechain": true])], "reply:a1"),
            ("곁가지 질문만", [user("u1"), asst("s1", [ask("t9")], ["isSidechain": true])], nil),
            ("uuid 없으면 timestamp", [user("u1"), jl(["type": "assistant", "timestamp": "2026-01-01T00:00:00Z",
                                                    "message": ["content": [text], "stop_reason": "end_turn"]])], "reply:2026-01-01T00:00:00Z"),
            ("끊음 → 답 안 함", [user("u1"), asst("a1", [text]), user("u2", "[Request interrupted by user]")], nil),
            ("질문 중 끊음", [user("u1"), asst("a1", [ask("t1")]), user("u2", [["type": "text", "text": "[Request interrupted by user for tool use]"]])], nil),
        ]
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("attention-\(getpid())").path
        defer { try? FileManager.default.removeItem(atPath: root) }
        try FileManager.default.createDirectory(atPath: root + "/meta", withIntermediateDirectories: true)
        var cats: [[String: Any]] = []
        for (i, c) in cases.enumerated() {
            let dir = root + "/projects/-w-case\(i)"
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let lines = [jl(["type": "system", "cwd": "/w/case\(i)-x"])] + c.1
            try (lines.joined(separator: "\n") + "\n").write(toFile: dir + "/s\(i).jsonl", atomically: true, encoding: .utf8)
            cats.append(["key": "k\(i)", "match": ["case\(i)-"], "private": i % 2 == 0])
        }
        let team = root + "/team.json"
        try JSONSerialization.data(withJSONObject: ["cats": cats]).write(to: URL(fileURLWithPath: team))
        let r = try StatusCollector(teamURL: URL(fileURLWithPath: team), metaDir: root + "/meta", projectsDir: root + "/projects").collectAll()
        var fail = 0
        for (i, c) in cases.enumerated() {
            let got = r.attention["k\(i)"].map { $0.kind + ":" + $0.stamp }
            let ok = got == c.2 && r.sessions["k\(i)"] != nil
            if !ok { fail += 1 }
            print((ok ? "  ok   " : "  틀림 ") + c.0 + (ok ? "" : " — 기대 \(c.2 ?? "없음"), 받음 \(got ?? "없음")"))
        }
        print(fail == 0 ? "통과" : "틀림 \(fail)")
        exit(fail == 0 ? 0 : 1)
    }
}
