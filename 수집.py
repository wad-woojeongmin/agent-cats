#!/usr/bin/env python3
"""고양이 팀 상태 수집기.

팀.json 에 적힌 고양이마다 "찾을 말"이 세션 제목이나 작업 폴더 경로에 들어 있는 세션을 모두 찾고,
그중 가장 최근에 움직인 세션 하나의 상태를 그 고양이 상태로 쓴다. 결과는 status.js 로 쓰고,
index.html 이 15초마다 다시 불러 말풍선을 바꾼다.

  python3 수집.py          한 번만 쓴다
  python3 수집.py --loop   10초마다 계속 쓴다 (화면을 열어 둘 때)
  python3 수집.py --config 다른설정.json   팀.json 대신 다른 설정으로

읽는 것: 세션 제목, 작업 폴더 경로, 마지막 활동 시각, 마지막 도구 이름과 대상, 마지막 보고의 첫 문장.
대화 내용을 저장하거나 밖으로 보내지 않는다. "private": true 인 고양이는 보고 문장도 싣지 않는다.
"""
import argparse, json, os, re, shutil, time
from pathlib import Path

HERE = Path(__file__).parent
CONFIG = HERE / "팀.json"
OUT = HERE / "status.js"
META = Path(os.path.expanduser("~/Library/Application Support/Claude/claude-code-sessions"))
PROJECTS = Path(os.path.expanduser("~/.claude/projects"))
RUNNING_WITHIN = 300     # 초. 턴을 모를 때만: 이 안에 기록이 움직였으면 일하는 중
OPEN_TURN_MAX = 45 * 60  # 초. 턴이 안 끝났으면 기록이 조용해도 이만큼은 일하는 중. 끝난 턴은 바로 쉼
TAIL = 900_000

TOOL_PHRASE = [
    (r"figma", "피그마에서 작업하는 중"),
    (r"^(Edit|Write|NotebookEdit)$", "파일을 고치는 중"),
    (r"^(Read|Grep|Glob)$", "자료를 읽는 중"),
    (r"^Bash$", "명령을 돌리는 중"),
    (r"WebSearch|WebFetch|browser|playwright|chrome", "웹에서 찾아보는 중"),
    (r"^(Agent|Workflow|Task)$", "다른 에이전트에게 일 시키는 중"),
    (r"Artifact", "아티팩트를 올리는 중"),
    (r"slack|gmail|calendar|drive", "연결된 앱을 보는 중"),
]
BASH_WORDS = {"ls": "폴더를 살펴보는 중", "find": "파일을 찾는 중", "grep": "내용을 찾는 중", "cat": "파일을 읽는 중",
              "sed": "파일을 훑는 중", "curl": "요청을 보내는 중", "open": "앱을 여는 중", "sleep": "잠깐 기다리는 중",
              "npm": "패키지 명령을 돌리는 중", "node": "스크립트를 돌리는 중", "mkdir": "폴더를 만드는 중",
              "cp": "파일을 복사하는 중", "mv": "파일을 옮기는 중"}

_CWD_CACHE = {}


def _find_cwd(p, size):
    """작업 폴더는 세션 동안 안 바뀐다. 끝부분에 없으면 앞부분을 읽고, 한 번 찾으면 기억해 둔다."""
    if p in _CWD_CACHE:
        return _CWD_CACHE[p]
    with open(p, "rb") as fh:
        for offset in (max(0, size - 60_000), 0):
            fh.seek(offset)
            chunk = fh.read(200_000).decode("utf-8", "ignore")
            hits = re.findall(r'"cwd":"([^"]+)"', chunk)
            if hits:
                _CWD_CACHE[p] = hits[-1] if offset else hits[0]
                return _CWD_CACHE[p]
    return ""


def cli_sessions(known):
    """앱 목록에 없는 세션(터미널 등)도 기록 파일에서 찾는다. 최근 이틀 안에 움직인 것만."""
    out = []
    for p in PROJECTS.glob("*/*.jsonl"):
        if p.stem in known:
            continue
        try:
            st = p.stat()
            if time.time() - st.st_mtime > 2 * 86400:
                continue
            cwd = _find_cwd(p, st.st_size)
        except Exception:
            continue
        if cwd:
            out.append({"title": "", "cwd": cwd, "cliSessionId": p.stem, "lastActivityAt": int(st.st_mtime * 1000)})
    return out


def all_sessions():
    metas = []
    for f in META.glob("*/*/local_*.json"):
        try:
            metas.append(json.loads(f.read_text(encoding="utf-8")))
        except Exception:
            continue
    known = {d.get("cliSessionId") for d in metas}
    return [m for m in metas if not m.get("isArchived")] + cli_sessions(known)


def find_sessions(sessions, needles):
    """세션 제목이나 작업 폴더 경로 '전체'에서 대소문자 구분 없이 부분 일치. (하위 폴더로 옮겨 다녀도 잡힌다)"""
    out = []
    for d in sessions:
        title, where = (d.get("title") or "").lower(), (d.get("cwd") or "").lower()
        if any(n.lower() in title or n.lower() in where for n in needles):
            out.append(d)
    return out


def find_log(cli):
    for p in PROJECTS.glob(f"*/{cli}.jsonl"):
        return p
    return None


def activity(s):
    log = find_log(s.get("cliSessionId") or "")
    last = s.get("lastActivityAt") or 0
    if log:
        last = max(last, int(log.stat().st_mtime * 1000))
    return log, last


def phrase(tool):
    for pat, text in TOOL_PHRASE:
        if re.search(pat, tool or "", re.I):
            return text
    return "작업을 이어가는 중"


def describe(tool, inp):
    """도구 이름에 대상까지 붙여서 지금 뭘 하는지 말한다."""
    inp = inp if isinstance(inp, dict) else {}
    base = os.path.basename(inp.get("file_path") or inp.get("notebook_path") or "")
    if base and tool in ("Read", "Edit", "Write", "NotebookEdit"):
        return base + (" 읽는 중" if tool == "Read" else " 고치는 중")
    if tool == "Bash":
        cmd = inp.get("command") or ""
        if "osascript" in cmd:
            return "브라우저 화면을 조작하는 중"
        if re.match(r"\s*git ", cmd):
            return "git 작업을 하는 중"
        desc = inp.get("description") or ""
        if re.search(r"[가-힣]", desc):
            return desc[:40]
        m = re.search(r"python3?\s+(?:-\w+\s+)*([^\s|;&<>]+\.py)", cmd)
        if m:
            return os.path.basename(m.group(1)) + " 돌리는 중"
        first = re.sub(r"^(cd [^;&|]+(;|&&)\s*)+", "", cmd.strip()).split()[:1]
        if first and first[0] in BASH_WORDS:
            return BASH_WORDS[first[0]]
    if tool in ("Agent", "Task"):
        desc = inp.get("description") or ""
        if re.search(r"[가-힣]", desc):
            return desc[:40] + " 맡기는 중"
    return phrase(tool)


def first_line(text):
    for line in (text or "").splitlines():
        line = re.sub(r"[`*#>|_]|\[([^\]]*)\]\([^)]*\)", lambda m: m.group(1) or "", line).strip()
        if len(line) >= 4:
            return line[:70]
    return ""


def first_sentence(line, cap=48):
    sent = re.split(r"(?<=[다요음임죠])\.\s|(?<=\.)\s", line or "", maxsplit=1)[0].rstrip(".")
    return sent if len(sent) <= cap else sent[: cap - 1].rstrip() + "…"


def tail_events(path):
    size = path.stat().st_size
    with open(path, "rb") as fh:
        fh.seek(max(0, size - TAIL))
        raw = fh.read().decode("utf-8", "ignore")
    lines = raw.splitlines()[1:] if size > TAIL else raw.splitlines()
    for line in reversed(lines):
        try:
            yield json.loads(line)
        except Exception:
            continue


def interrupted(msg):
    # 사용자가 끊은 줄 (Esc): "[Request interrupted by user]", "... for tool use]"
    c = msg.get("content")
    if isinstance(c, list):
        c = "".join(p["text"] for p in c if isinstance(p, dict) and p.get("type") == "text" and isinstance(p.get("text"), str))
    return isinstance(c, str) and c.startswith("[Request interrupted by user")


def build(cat, sessions):
    now = int(time.time() * 1000)
    found = find_sessions(sessions, cat.get("match") or [])
    if not found:
        return {"state": "missing", "now": now}
    s = max(found, key=lambda d: activity(d)[1])
    log, last = activity(s)
    tool, tinp, said, turn_open = "", {}, "", None
    if log:
        for ev in tail_events(log):
            msg = ev.get("message") or {}
            if turn_open is None and ev.get("type") in ("user", "assistant") and not ev.get("isMeta") and not ev.get("isSidechain"):
                turn_open = not interrupted(msg) if ev["type"] == "user" else msg.get("stop_reason") != "end_turn"
            if ev.get("type") != "assistant" or not isinstance(msg.get("content"), list):
                continue
            for part in msg["content"]:
                if not tool and part.get("type") == "tool_use":
                    tool, tinp = part.get("name", ""), part.get("input")
                if not said and part.get("type") == "text":
                    said = first_line(part.get("text", ""))
            if tool and said:
                break
    age = (now - last) / 1000
    # 턴을 알면 턴만 본다 (막 끝난 턴은 기록이 새것이어도 쉼). 모르면 (기록 없음 등) 최근에 움직였는지로
    running = age < RUNNING_WITHIN if turn_open is None else turn_open and age < OPEN_TURN_MAX
    out = {"state": "working" if running else "idle", "title": s.get("title") or "",
           "folder": os.path.basename((s.get("cwd") or "").rstrip("/")),
           "doing": describe(tool, tinp) if tool else "", "step": first_sentence(said), "last": last, "now": now}
    if cat.get("private"):
        # 민감한 정보가 오갈 수 있는 팀: 보고 문장, 폴더 이름, 파일 이름은 싣지 않고 일반적인 말만 싣는다
        out["step"] = ""
        out["folder"] = ""
        out["title"] = ""
        out["doing"] = phrase(tool) if tool else ""
    return out


def write(cfg):
    sessions = all_sessions()
    status = {c["key"]: build(c, sessions) for c in cfg["cats"] if c.get("match")}
    public = [{k: v for k, v in c.items() if k not in ("match",)} for c in cfg["cats"]]
    data = {"title": cfg.get("title", ""), "catWidth": cfg.get("catWidth", 166), "columns": cfg.get("columns", 3),
            "staleSec": cfg.get("staleSec", 60), "updated": int(time.time() * 1000), "cats": public, "status": status}
    tmp = OUT.with_suffix(f".{os.getpid()}.tmp")   # 앱이 한 번 더 돌리는 수집과 겹쳐도 서로 지우지 않게
    tmp.write_text("window.CATTEAM=" + json.dumps(data, ensure_ascii=False) + ";\n", encoding="utf-8")
    tmp.replace(OUT)
    return status


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--loop", action="store_true")
    ap.add_argument("--config", default=str(CONFIG), help="설정 파일 (기본: 팀.json)")
    a = ap.parse_args()
    if a.config == str(CONFIG) and not CONFIG.exists():               # 처음 실행이면 예시를 복사해 팀.json 을 만든다
        shutil.copyfile(HERE / "팀.example.json", CONFIG)
    while True:
        try:
            cfg = json.loads(Path(a.config).read_text(encoding="utf-8"))   # 팀.json 을 고치면 다음 주기에 바로 반영
            st = write(cfg)
            print(time.strftime("%H:%M:%S"), {k: v["state"] for k, v in st.items()}, flush=True)
        except Exception as e:                                         # 팀.json 을 고치는 도중이어도 --loop 는 죽지 않는다
            if not a.loop:
                raise
            print(time.strftime("%H:%M:%S"), "건너뜀:", e, flush=True)
        if not a.loop:
            break
        time.sleep(10)
