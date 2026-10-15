// 수집기(desktop/StatusCollector.swift) 결과를 JSON 으로 찍는다. tests/collector_parity.sh 가 수집.py 결과와 비교한다.
//   swiftc -swift-version 5 -parse-as-library desktop/StatusCollector.swift tests/collector_parity.swift -o /tmp/collector_parity
//   /tmp/collector_parity 팀.json [메타폴더 기록폴더]
// 걸린 시간은 stderr 로 (처음 한 번, 그다음 캐시가 찬 뒤 두 번).
import Foundation

@main
enum CollectorParity {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 2 || args.count == 4 else {
            FileHandle.standardError.write("쓰는 법: collector_parity 팀.json [메타폴더 기록폴더]\n".data(using: .utf8)!)
            exit(2)
        }
        let team = URL(fileURLWithPath: args[1])
        let c = args.count == 4 ? StatusCollector(teamURL: team, metaDir: args[2], projectsDir: args[3]) : StatusCollector(teamURL: team)
        var first: [String: Any] = [:]
        var times: [String] = []
        for i in 0 ..< 3 {
            let t = Date()
            let r = try c.collect()
            times.append(String(format: "%.0fms", Date().timeIntervalSince(t) * 1000))
            if i == 0 { first = r }
        }
        FileHandle.standardError.write("collect(): \(times.joined(separator: ", "))\n".data(using: .utf8)!)
        let data = try JSONSerialization.data(withJSONObject: first, options: [.sortedKeys, .withoutEscapingSlashes])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
    }
}
