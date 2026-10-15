#!/bin/bash
# 수집기 Swift 판(desktop/StatusCollector.swift)과 수집.py 의 결과를 맞춰 본다. 프로젝트 폴더에서:
#   tests/collector_parity.sh
# 세 가지로 돌린다: (1) 팀.json (있으면) (2) 최근 세션 폴더마다 고양이를 하나씩 둔 넓은 설정 (3) 일부러 만든 시험 기록.
# 세션 내용은 찍지 않는다. 고양이 수, 같은 수, 다른 항목 이름만 찍는다. now/updated 는 빼고 비교한다.
set -euo pipefail
cd "$(dirname "$0")/.."
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

swiftc -swift-version 5 -parse-as-library desktop/StatusCollector.swift tests/collector_parity.swift -o "$T/parity"

# 수집.py 의 write() 를 그대로 부르고 status.js 를 읽어 JSON 으로
cat > "$T/py_collect.py" <<'PY'
import importlib.util, json, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("collect_py", "수집.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
if len(sys.argv) == 5:
    m.META, m.PROJECTS = Path(sys.argv[3]), Path(sys.argv[4])
m.OUT = Path(sys.argv[2])
m.write(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8")))
js = m.OUT.read_text(encoding="utf-8")
assert js.startswith("window.CATTEAM=") and js.endswith(";\n")
sys.stdout.write(json.dumps(json.loads(js[len("window.CATTEAM="):-2]), sort_keys=True, ensure_ascii=False) + "\n")
PY

# 비교: 0 같음, 1 살아 있는 기록에 따라 바뀌는 칸(state/last/doing/step)만 다름 (두 수집 사이에 기록이 바뀌었을 수 있어 다시 돌린다), 2 다름
cat > "$T/compare.py" <<'PY'
import json, sys
s, p = (json.load(open(f, encoding="utf-8")) for f in sys.argv[1:3])
label = sys.argv[3]
for d in (s, p):
    d.pop("updated", None)
    for v in d["status"].values(): v.pop("now", None)
diffs = [f"top.{k}" for k in sorted(set(s) | set(p)) if k != "status" and s.get(k) != p.get(k)]
keys = sorted(set(s["status"]) | set(p["status"]))
same = 0
for k in keys:
    a, b = s["status"].get(k), p["status"].get(k)
    if a == b: same += 1; continue
    if a is None or b is None: diffs.append(f"status[{k}] 한쪽에만 있음"); continue
    diffs += [f"status[{k}].{f}" for f in sorted(set(a) | set(b)) if a.get(f) != b.get(f)]
states = {}
for v in p["status"].values(): states[v["state"]] = states.get(v["state"], 0) + 1
print(f"{label}: 고양이 {len(p['cats'])}, 상태 {len(keys)} 중 같음 {same} {states}" + ("" if diffs else ", 모두 같음"))
for d in diffs: print("  다름:", d)
LIVE = (".state", ".last", ".doing", ".step")
sys.exit(0 if not diffs else 1 if all(d.startswith("status[") and d.endswith(LIVE) for d in diffs) else 2)
PY

run() {   # 이름 설정 [메타 기록]
    # 메타·기록을 따로 주면 일부러 만든 시험 기록이라 바뀔 일이 없다: 다시 돌리지 않는다
    local label=$1; shift
    local tries=3; [ $# -gt 1 ] && tries=1
    for try in $(seq 1 $tries); do
        "$T/parity" "$@" > "$T/s.json" 2> "$T/time.txt"
        python3 "$T/py_collect.py" "$1" "$T/out.js" "${@:2}" > "$T/p.json"
        rc=0; python3 "$T/compare.py" "$T/s.json" "$T/p.json" "$label" || rc=$?
        echo "  $(cat "$T/time.txt")"
        [ $rc -eq 0 ] && [ $try -gt 1 ] && echo "  살아 있는 세션이 그 사이 바뀌어 다시 맞춤 ($((try - 1))번)"
        [ $rc -eq 1 ] && [ $try -lt $tries ] && { echo "  살아 있는 기록에 따라 바뀌는 칸만 달라서 다시 돌림"; continue; }
        [ $rc -eq 0 ] || FAIL=1
        break
    done
}
FAIL=0

# (1) 실제 팀.json
[ -f 팀.json ] && run "팀.json" 팀.json

# (2) 최근 세션 폴더 이름마다 고양이 하나 + 비공개/고정/빈 찾을 말/없는 말/대문자/문자열 match
python3 - "$T/broad.json" <<'PY'
import importlib.util, json, os, sys
spec = importlib.util.spec_from_file_location("collect_py", "수집.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
names = sorted({os.path.basename((s.get("cwd") or "").rstrip("/")) for s in m.all_sessions()} - {""})
cats = [{"key": f"c{i}", "name": f"고양이{i}", "match": [n], "variant": "white", "extra": {"x": [1, None]}} for i, n in enumerate(names)]
if names:
    cats += [{"key": "priv", "match": [names[0].upper()], "private": True},
             {"key": "fixed", "match": [names[0]], "fixed": "중"},
             {"key": "all", "match": [""]},
             {"key": "none", "match": ["이런-폴더는-없다-zz"]},
             {"key": "chars", "match": "zq"},
             {"key": "nomatch", "name": "말만"},
             {"key": "empty", "match": []}]
json.dump({"title": "넓은 시험", "columns": 4, "cats": cats}, open(sys.argv[1], "w"), ensure_ascii=False)
PY
run "넓은 설정" "$T/broad.json"

# (3) 일부러 만든 시험 기록: 도구 설명, 첫 줄/첫 문장, 줄 끝 글자, 깨진 UTF-8, 900KB 넘는 기록, cwd 찾기, 정규화, 동점
python3 - "$T/fx" <<'PY'
import json, os, sys, time, unicodedata
R = sys.argv[1]; META = f"{R}/meta/acc/org"; P = f"{R}/projects"
os.makedirs(META); os.makedirs(P)
now = time.time()
def jl(o): return json.dumps(o, ensure_ascii=False, separators=(",", ":"))
def asst(parts, stop="tool_use", **kw): return jl({"type": "assistant", "message": {"content": parts, "stop_reason": stop}, **kw})
def user(**kw): return jl({"type": "user", "message": {"content": "x"}, **kw})
def tool(name, inp): return {"type": "tool_use", "name": name, "input": inp}
def text(t): return {"type": "text", "text": t}
def log(dirname, sid, lines, age, raw=None):
    os.makedirs(f"{P}/{dirname}", exist_ok=True)
    path = f"{P}/{dirname}/{sid}.jsonl"
    with open(path, "wb") as f: f.write(raw if raw is not None else ("\n".join(lines) + "\n").encode())
    os.utime(path, (now - age, now - age))
cats = []
def case(i, lines, age=60, cwd=None, cat=None):
    cwd = cwd or f"/w/case{i:02d}-x/"
    log(f"-w-case{i:02d}", f"s{i:02d}", [jl({"type": "system", "cwd": cwd})] + lines, age)
    cats.append({"key": f"k{i:02d}", "match": [f"case{i:02d}-"], **(cat or {})})
tools = [
    ("Read", {"file_path": "/a/b/c.txt"}), ("Edit", {"file_path": "/a/파일.swift"}), ("Write", {"file_path": "", "notebook_path": "/n/x.ipynb"}),
    ("NotebookEdit", {"notebook_path": "/n/y.ipynb"}), ("Read", {"file_path": "/a/b/"}), ("Read", "문자열 입력"), ("Read", None),
    ("Bash", {"command": "osascript -e 'x'"}), ("Bash", {"command": "  git status"}), ("Bash", {"command": "　git log"}),
    ("Bash", {"command": "\x1fgit log"}), ("Bash", {"command": "gitx status"}),
    ("Bash", {"command": "ls", "description": "아주 긴 설명입니다 👩‍👩‍👧‍👦 이모지와 결합 문자 é 가 섞여 있고 사십 글자를 넘어서 잘려야 합니다"}),
    ("Bash", {"command": "ls", "description": "한"}), ("Bash", {"command": "python3 -u -m x foo/bar.pyc arg", "description": "run it"}),
    ("Bash", {"command": "python script.py"}), ("Bash", {"command": "python3 -x² a.py"}), ("Bash", {"command": "python3 -c 'x' foo.py"}),
    ("Bash", {"command": "python3 -c 'x' é.py"}), ("Bash", {"command": "pythonista.py"}), ("Bash", {"command": "python3   -W  -q   .py x/.py"}),
    ("Bash", {"command": "cd a && cd b; ls -la"}), ("Bash", {"command": "cd a | ls"}), ("Bash", {"command": "cd x&ls"}),
    ("Bash", {"command": "cd a && npm i"}), ("Bash", {"command": "  ls  "}), ("Bash", {"command": "unknown cmd"}), ("Bash", {"command": ""}),
    ("Bash", {"command": "lś"}), ("Bash", {"command": "osascript́"}), ("Bash", {}),
    ("Agent", {"description": "한국어로 맡길 일"}), ("Task", {"description": "english"}), ("Workflow", {}),
    ("mcp__figma__get", {}), ("mcp__claude-in-chrome__navigate", {}), ("Artifact", {}), ("mcp__slack__send", {}), ("TodoWrite", {}),
    ("bash", {"command": "ls"}), ("Edit\n", {}), ("Edit\n\n", {}), ("EDIT", {"file_path": "/x"}), ("", {}), ("WebFetch", {}),
]
for i, (n, inp) in enumerate(tools):
    case(i, [user(), asst([tool(n, inp)]), asst([text("보고서를 정리했습니다. 다음")], stop="end_turn")], age=30)
texts = [
    "```\n\n# 제목입니다\n", "ab\nabcd", "가나다라마바사 " * 12, "버전 1.2 를 올렸어요. 다음", "Done... next", "Done.\tnext",
    "[링크 *굵게*](http://a) 와 `코드` 입니다", "[미완성 링크(http 입니다", "첫줄 둘째 줄입니다", "ab\r\ncdef", "ab\x85cdef", "ab\x1fcd",
    "a" * 47 + ". b", "가" * 48, "가" * 49, "가" * 46 + " " + "나" * 5, "👩‍👩‍👧‍👦" * 20, unicodedata.normalize("NFD", "한글 문장입니다. 다음"),
    "  abc d ", "끝났음.다음", "끝났음. 다음", "테스트임.　다음", "1. 첫째. 둘째", "|>_*#", "**", "",
    "[](x)abcd", "[a](b)(c)", "x. y", "줄\x1c나눔입니다",
]
for j, t in enumerate(texts):
    case(100 + j, [user(), asst([text(t), tool("Bash", {"command": "ls"})])], age=30)
# 글 안의 이스케이프된 줄 끝 (\u2028, \u0085): 줄은 읽히고 first_line 이 쪼갠다
for j, t in enumerate(["첫줄\u2028둘째 줄입니다", "ab\x85cdef", "ab\u2029cdefg", "x\x0bwxyz"]):
    case(150 + j, [user(), json.dumps({"type": "assistant", "message": {"content": [text(t)]}}, separators=(",", ":"))], age=30)
# 상태: 턴이 열려 있음/닫힘/메타/곁가지
case(200, [asst([text("끝")], stop="end_turn"), user()], age=600)
case(201, [user(), asst([text("끝냈어요")], stop="end_turn")], age=600)
case(202, [user(), asst([text("도구 쓰는 중")], stop="tool_use")], age=600)
case(203, [user(), asst([text("도구 쓰는 중")], stop="tool_use")], age=3000)
case(204, [user(), asst([text("끝냈어요")], stop="end_turn"), user(isMeta=True), asst([text("곁")], isSidechain=True)], age=600)
case(205, [user(), asst([text("끝냈어요")], stop="end_turn"), jl({"type": "assistant", "message": {"content": "문자열"}})], age=600)
case(206, [user(), asst([text("끝냈어요")], stop="end_turn"), jl({"type": "user", "isMeta": 0, "message": {}})], age=600)
case(207, [user(), asst([text("오래된 것")], stop="end_turn")], age=3 * 86400)   # 이틀 넘음 → 없음
case(208, [user(), asst([tool("Edit", {"file_path": "/비밀/파일.txt"}), text("비밀 보고입니다. 더")])], age=30, cat={"private": True})
case(209, [user(), asst([tool("Edit", {"file_path": "/a.txt"})])], age=30, cat={"fixed": True})
# 일하는 중 판단: 턴을 알면 턴만 본다 (막 끝난 턴은 바로 쉼), 모르면 300초 규칙
case(218, [user(), asst([text("방금 끝냈어요")], stop="end_turn")], age=30)               # 닫힘 + 최근 → 쉼
case(219, [user(), asst([text("도구 쓰는 중")], stop="tool_use")], age=30)               # 열림 + 최근 → 일함
case(220, [jl({"type": "progress"})], age=30)                                           # 모름 + 최근 → 일함
case(221, [jl({"type": "progress"})], age=600)                                          # 모름 + 오래됨 → 쉼
case(222, [user(isMeta=True), asst([text("곁")], isSidechain=True)], age=30)            # 메타·곁가지만 → 모름 + 최근 → 일함
# 원시 U+2028/U+0085 가 든 줄 (파이썬 splitlines 가 쪼개서 못 읽는 줄), 깨진 UTF-8, CRLF
raw = "\n".join([jl({"type": "system", "cwd": "/w/case210-x"}), user(), asst([tool("Read", {"file_path": "/ok.txt"}), text("읽을 수 있는 줄입니다")])]).encode()
raw += b"\r\n" + asst([tool("Edit", {"file_path": "/a b.txt"})]).encode() + b"\n"
raw += asst([tool("Write", {"file_path": "/a\u0085b.txt"})]).encode() + b"\r\n"
raw += b'{"type":"assistant","message":{"content":[{"type":"text","text":"\xff\xfe\xed\xa0\x80\xe0\x80\xf0\x9f\x98\xc3\xa9\xea\xb9\x8c\xeb\x82\x98 \xf4\x90\x80\x80\xc0\xafend"}],"stop_reason":"end_turn"}}\r\n'
log("-w-case210", "s210", None, 30, raw); cats.append({"key": "k210", "match": ["case210-"]})
# 900KB 넘는 기록: 앞의 도구는 창 밖, 첫 줄 조각은 버린다
big = [jl({"type": "system", "cwd": "/w/case211-x"}), asst([tool("Agent", {"description": "창 밖 일"})])]
big += [jl({"type": "progress", "pad": "가" * 3000}) for _ in range(120)]
big += [user(), asst([text("창 안의 보고입니다")], stop="end_turn")]
log("-w-case211", "s211", big, 30); cats.append({"key": "k211", "match": ["case211-"]})
# 900KB 창이 마침 한 줄의 처음에서 시작: 그 줄은 읽을 수 있어도 버린다
frag = asst([tool("Bash", {"command": "ls"})]).encode()
rest = b"\n" + user().encode() + b"\n"
pad = 900_000 - len(frag) - len(rest) - len(b'{"type":"progress","pad":""}\n')
rest += b'{"type":"progress","pad":"' + b"x" * pad + b'"}\n'
blob = jl({"type": "system", "cwd": "/w/case212-x"}).encode() + b"\n" + b"z" * 5000 + b"\n" + frag + rest
assert len(blob) - 900_000 == blob.index(frag)
log("-w-case212", "s212", None, 30, blob); cats.append({"key": "k212", "match": ["case212-"]})
# cwd 찾기: 앞에만 있음(끝 6만 바이트 밖), 끝에 여러 개(마지막), 작은 파일에 여러 개(첫째), 빈 cwd
log("-w-case213", "s213", [jl({"cwd": "/w/case213-head"})] + [jl({"pad": "p" * 1000}) for _ in range(300)] + [user()], 30)
log("-w-case214", "s214", [jl({"pad": "p" * 1000}) for _ in range(100)] + [jl({"cwd": "/w/case214-old"}), jl({"cwd": "/w/case214-new"}), user()], 30)
log("-w-case215", "s215", [jl({"cwd": "/w/case215-first"}), jl({"cwd": "/w/case215-second"}), user()], 30)
log("-w-case216", "s216", ['{"cwd":"","x":1}', jl({"cwd": "/w/case216-real/"}), user()], 30)
log("-w-case216", "s217", ['{"cwd":"/w/case217-unclosed'], 30)
cats += [{"key": f"k{n}", "match": [f"case{n}-"]} for n in (213, 214, 215, 216, 217)]
# 같은 세션 id 가 두 폴더에 (find_log 는 첫 폴더)
log("-w-dupA", "sdup", [jl({"cwd": "/w/casedup-a"}), user()], 100)
log("-w-dupB", "sdup", [jl({"cwd": "/w/casedup-b"}), asst([text("끝")], stop="end_turn")], 20)
cats.append({"key": "kdup", "match": ["casedup-"]})
# 앱 메타: 보관됨, 기록 없음, 깨진 JSON, 이름 안 맞음, NFD 폴더, 동점, null 제목
nowms = int(now * 1000)
metas = {
    "local_1.json": {"title": "알파 프로젝트", "cwd": "/w/Alpha/", "cliSessionId": "s000", "lastActivityAt": nowms - 3_600_000},
    "local_2.json": {"title": "보관된 일", "cwd": "/w/case001-x/", "cliSessionId": "s01", "isArchived": True, "lastActivityAt": nowms},
    "local_3.json": {"title": "베타", "cwd": "/w/beta", "cliSessionId": "nolog", "lastActivityAt": nowms - 10_000},
    "local_4.json": {"title": None, "cwd": unicodedata.normalize("NFD", "/w/한글폴더"), "cliSessionId": "x4", "lastActivityAt": nowms - 5000},
    "local_5.json": {"title": "동점 하나", "cwd": "/w/tie", "cliSessionId": "t1", "lastActivityAt": nowms - 7000},
    "local_6.json": {"title": "동점 둘", "cwd": "/w/tie", "cliSessionId": "t2", "lastActivityAt": nowms - 7000},
    "local_7.json": {"title": "시각 없음", "cwd": "/w/notime", "cliSessionId": "t3", "lastActivityAt": None},
    "local_.json": {"title": "짧은 이름", "cwd": "/w/shortname", "cliSessionId": "t4", "lastActivityAt": nowms - 9000},
    "notlocal_8.json": {"title": "안 읽힘", "cwd": "/w/notread", "lastActivityAt": nowms},
}
for n, d in metas.items(): open(f"{META}/{n}", "w").write(json.dumps(d, ensure_ascii=False))
open(f"{META}/local_bad.json", "w").write("{깨짐")
log("-w-Alpha", "s000", [user(), asst([tool("Read", {"file_path": "/a/알파.md"}), text("알파 보고입니다")])], 4000)
cats += [{"key": "alpha", "match": ["ALPHA"]}, {"key": "beta", "match": ["베타"]},
         {"key": "nfc", "match": [unicodedata.normalize("NFC", "한글폴더")]}, {"key": "nfd", "match": [unicodedata.normalize("NFD", "한글폴더")]},
         {"key": "tie", "match": ["/w/tie"]}, {"key": "notime", "match": ["notime"]}, {"key": "short", "match": ["shortname"]},
         {"key": "notread", "match": ["notread"]}, {"key": "all", "match": [""]}, {"key": "chars", "match": "zq"},
         {"key": "archived", "match": ["보관된"]}, {"key": "nothing", "match": []}, {"key": "nomatch"}]
json.dump({"title": "시험", "catWidth": 150, "staleSec": None, "extra": 1, "cats": cats}, open(f"{R}/team.json", "w"), ensure_ascii=False)
PY
run "시험 기록" "$T/fx/team.json" "$T/fx/meta" "$T/fx/projects"

[ -n "${KEEP:-}" ] && cp "$T/s.json" "$KEEP"

# 사용자 차례("!") 찾기: collect() 결과 밖이라 따로 시험한다
swiftc -swift-version 5 -parse-as-library desktop/StatusCollector.swift tests/attention_test.swift -o "$T/attention"
echo "사용자 차례:"; "$T/attention" || FAIL=1
[ $FAIL -eq 0 ] && echo "모두 같음" || { echo "다른 곳이 있음"; exit 1; }
