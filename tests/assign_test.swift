// 고양이 디스플레이 나누기 규칙(desktop/DisplayAssign.swift) 시험. 프로젝트 폴더에서:
//   swiftc -swift-version 5 -parse-as-library desktop/DisplayAssign.swift tests/assign_test.swift -o /tmp/assign_test && /tmp/assign_test
// (파일이 둘이면 맨 위 코드는 main.swift 에서만 되므로 @main 으로 감쌌다)

let cats = ["a", "b", "c", "d", "e"]

func check(_ ok: Bool, _ msg: String) { precondition(ok, msg) }

/// 앱처럼 placed 를 저장해 가며 한 번 돌린다
func step(_ cats: [String], _ chosen: inout [String: String], _ displays: [String]) -> [String: String] {
    let r = DisplayAssign.run(cats: cats, chosen: chosen, displays: displays)
    chosen.merge(r.placed) { $1 }
    return r.assign
}

@main
enum AssignTest {
    static func main() {
        // (a) 아무도 고르지 않음, 화면 3개 → 2/2/1, 첫 고양이는 주 화면
        var chosen: [String: String] = [:]
        let first = DisplayAssign.run(cats: cats, chosen: chosen, displays: ["M", "X", "Y"])
        check(first.assign == ["a": "M", "b": "X", "c": "Y", "d": "M", "e": "X"], "(a) 2/2/1 로 나뉘어야 함: \(first.assign)")
        check(first.placed == first.assign, "(a) 모두 새로 정한 자리여야 함")
        chosen = first.placed

        // (b) 한 마리를 옮겨도 다른 고양이는 그대로
        var moved = chosen
        moved["a"] = "Y"
        let b = DisplayAssign.run(cats: cats, chosen: moved, displays: ["M", "X", "Y"])
        check(b.placed.isEmpty, "(b) 새로 정할 고양이가 없어야 함: \(b.placed)")
        for k in cats where k != "a" { check(b.assign[k] == first.assign[k], "(b) \(k) 가 움직이면 안 됨") }
        check(b.assign["a"] == "Y", "(b) a 는 Y 로")

        // (c) X 를 빼면 X 고양이는 주 화면에, 저장값은 그대로. 다시 꽂으면 돌아간다
        var c = chosen
        let unplugged = step(cats, &c, ["M", "Y"])
        check(unplugged["b"] == "M" && unplugged["e"] == "M", "(c) X 고양이는 주 화면으로: \(unplugged)")
        check(unplugged["a"] == "M" && unplugged["c"] == "Y" && unplugged["d"] == "M", "(c) 나머지는 그대로")
        check(c == chosen, "(c) 저장값이 바뀌면 안 됨: \(c)")
        let replugged = step(cats, &c, ["M", "X", "Y"])
        check(replugged == first.assign, "(c) 다시 꽂으면 원래대로: \(replugged)")

        // (d) 한 마리의 선택을 지우면 그 고양이만 가장 적은 화면으로
        var d = chosen
        d["d"] = nil                                        // M: a / X: b, e / Y: c → M 과 Y 가 1 로 동점, 앞인 M
        let dr = DisplayAssign.run(cats: cats, chosen: d, displays: ["M", "X", "Y"])
        check(dr.placed == ["d": "M"], "(d) d 만 새로 정해야 함: \(dr.placed)")
        d["b"] = nil
        d["d"] = "M"                                        // M: a, d / X: e / Y: c → X 와 Y 동점, 앞인 X
        let dr2 = DisplayAssign.run(cats: cats, chosen: d, displays: ["M", "X", "Y"])
        check(dr2.placed == ["b": "X"], "(d) b 만 X 로: \(dr2.placed)")
        d["e"] = nil
        d["b"] = "Y"                                        // M: a, d / X: 없음 / Y: b, c → X
        let dr3 = DisplayAssign.run(cats: cats, chosen: d, displays: ["M", "X", "Y"])
        check(dr3.placed == ["e": "X"], "(d) e 는 가장 적은 X 로: \(dr3.placed)")
        for k in ["a", "b", "c", "d"] { check(dr3.assign[k] == d[k], "(d) \(k) 는 그대로") }

        // (e) 새 화면을 꽂아도 아무도 움직이지 않는다
        let e = DisplayAssign.run(cats: cats, chosen: chosen, displays: ["M", "X", "Y", "Z"])
        check(e.assign == first.assign && e.placed.isEmpty, "(e) 새 화면에 아무도 옮겨지면 안 됨: \(e.assign)")

        // (f) 숨긴 고양이는 cats 에 없으니 배치되지 않는다
        let f = DisplayAssign.run(cats: ["a", "c"], chosen: [:], displays: ["M", "X"])
        check(f.assign == ["a": "M", "c": "X"] && f.placed == f.assign, "(f) 보이는 고양이만: \(f.assign)")

        // 저장된 값으로 다시 돌리면 정할 게 없다 (앱에서 되먹임이 멈추는 이유)
        var g = [String: String]()
        _ = step(cats, &g, ["M", "X", "Y"])
        check(DisplayAssign.run(cats: cats, chosen: g, displays: ["M", "X", "Y"]).placed.isEmpty, "두 번째엔 새로 정할 게 없어야 함")

        // 화면이 없으면 아무것도 하지 않는다
        check(DisplayAssign.run(cats: cats, chosen: [:], displays: []).assign.isEmpty, "화면이 없으면 빈 결과")

        print("통과")
    }
}
