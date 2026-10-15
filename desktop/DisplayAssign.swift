// 고양이를 디스플레이에 나누는 규칙 (AppKit 없이, tests/assign_test.swift 에서 시험한다).
//  - 자리를 고른 고양이는 그 디스플레이로. 그 디스플레이가 지금 없으면 주 화면에 두되 고른 값은 그대로 둔다
//  - 자리가 없는 고양이만 고양이가 가장 적은 디스플레이에 둔다 (동점이면 앞, 주 화면부터)
//  - 새로 정한 자리(placed)는 부르는 쪽이 저장해서 다시 섞지 않는다

enum DisplayAssign {
    /// cats: 보이는 고양이 key (순서대로), chosen: 저장된 자리, displays: 디스플레이 id (주 화면이 처음)
    static func run(cats: [String], chosen: [String: String], displays: [String]) -> (assign: [String: String], placed: [String: String]) {
        guard let main = displays.first else { return ([:], [:]) }
        var assign: [String: String] = [:]
        var count: [String: Int] = Dictionary(uniqueKeysWithValues: displays.map { ($0, 0) })
        for key in cats {
            guard let want = chosen[key] else { continue }
            let id = count[want] != nil ? want : main
            assign[key] = id
            count[id, default: 0] += 1
        }
        var placed: [String: String] = [:]
        for key in cats where assign[key] == nil {
            let id = displays.min { count[$0, default: 0] < count[$1, default: 0] }!   // 동점이면 앞(주 화면)부터
            assign[key] = id
            placed[key] = id
            count[id, default: 0] += 1
        }
        return (assign, placed)
    }
}
