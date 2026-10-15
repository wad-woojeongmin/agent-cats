/* 데스크톱 고양이 모의 실행: 브라우저 없이 desk-world.js + desk-brain.js 를 20분 돌려 본다.
   실행: node tests/sim.js  (의존성 없음, 실패하면 0 아닌 값으로 끝난다) */
const path = require("path");

let seed = 7;                                                    // 같은 결과가 나오게 난수를 고정한다
Math.random = () => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; };

global.window = { innerWidth: 1400, innerHeight: 850, addEventListener() {} };
["palette.js", "props.js", "pose-sit.js", "pose-sleep.js", "pose-move.js", "cats.js", "lines.js", "desk-world.js", "desk-brain.js"]
  .forEach((f) => require(path.join(__dirname, "..", f)));

const W = window.deskWorld, B = window.deskBrain;
const POSES = new Set(Object.keys(window.CAT_POSES));
const fails = [];
const fail = (msg) => { if (fails.length < 20) fails.push(msg); };
if (!POSES.has("alert")) fail("놀람 자세(alert)가 없다");
["white", "tabby", "gray", "tux", "siamese"].forEach((variant) => [0, 1, 2].forEach((frame) => {   // 느낌표는 화면이 따로 띄운다
  const { grid, bbox } = window.catFrame({ variant, prop: "headphones" }, { pose: "alert", frame, tick: 0, bare: true });
  if (grid.some((row) => row.includes("!"))) fail("놀람 " + variant + " " + frame + ": 그림 안에 느낌표가 남았다");
  if (!(bbox[0] < bbox[2] && bbox[1] < bbox[3]) || bbox[0] < 0 || bbox[1] < 0 || bbox[2] > 44 || bbox[3] > 25) fail("놀람 " + variant + " " + frame + ": 그림 경계 " + bbox);
}));

const win = { id: 1, x: 600, y: 300, w: 560, h: 380 };
W.update({ menubar: 24, windows: [Object.assign({}, win)], icons: [{ x: 40, y: 80, w: 64, h: 64 }] });

const now0 = 1e12;
const cfgs = [
  { key: "a", variant: "white" }, { key: "b", variant: "tabby" }, { key: "c", variant: "white" },
  { key: "d", variant: "white" }, { key: "e", variant: "white" }
];
const status = {
  a: { state: "idle", last: now0 }, b: { state: "idle", last: now0 },
  c: { state: "working", last: now0, doing: "편집" }, d: { state: "missing" }, e: { state: "idle", last: now0 }
};
B.cats = cfgs.map((cfg) => B.make(cfg));
B.cats.forEach((c) => B.setLine(c, window.catLine(c.cfg, status[c.key])));
const main = B.cats;                                             // 뒤 시험들이 B.cats 를 갈아 끼운다

const DT = 0.033, STEPS = Math.round(20 * 60 / DT);
const seen = { win: new Set(), menubar: new Set() };
let t = now0, chased = 0;
B.onAction = (c, s) => { if (s.type === "chase") chased++; };   // 커서 쫓기는 흔들 때만: 저절로 나오면 안 된다

function check(c, where) {
  if (!Number.isFinite(c.x) || !Number.isFinite(c.y)) fail(where + ": " + c.key + " 위치가 " + c.x + "," + c.y);
  if (!POSES.has(c.pose)) fail(where + ": " + c.key + " 모르는 자세 " + c.pose);
  if (c.perch) seen[c.perch.kind].add(c.key);
}

for (let i = 0; i < STEPS; i++) {
  t += DT * 1000;
  if (i % 900 === 0) { W.mouse.x = Math.random() * W.w; W.mouse.y = 30 + Math.random() * (W.h - 30); W.mouse.moved = t; }   // 30초마다 커서
  if (i % 1800 === 900) {                                                                                               // 1분마다 창 이동
    win.x = 200 + Math.random() * 600; win.y = 150 + Math.random() * 250;
    W.update({ windows: [Object.assign({}, win)] });
    B.onWorld(t);
  }
  B.step(DT, t);
  B.cats.forEach((c) => check(c, "t=" + Math.round((t - now0) / 1000) + "s"));
  if (i % 300 === 0) B.cats.forEach((c) => {                                                                            // 그림도 그려 본다
    const { bbox } = window.catFrame(c.cfg, { pose: c.pose, frame: c.frame, tick: c.tick, shut: c.shut, bare: true });
    if (!(bbox[0] < bbox[2] && bbox[1] < bbox[3])) fail(c.key + " " + c.pose + " 그림이 비었다");
  });
}

/* 창을 닫는다. 앱은 창 목록이 바뀔 때만 world 를 보내므로 onWorld 도 한 번만 부른다 */
W.update({ windows: [] });
B.onWorld(t);
for (let i = 0; i < Math.round(5 / DT); i++) {
  t += DT * 1000;
  B.step(DT, t);
  B.cats.forEach((c) => check(c, "창 닫은 뒤"));
}
const stranded = B.cats.filter((c) => c.perch && c.perch.kind === "win");
if (stranded.length) fail("창이 없는데 창 위에 있다: " + stranded.map((c) => c.key).join(","));
if (!seen.win.size) fail("창 위에 올라간 고양이가 없다");
if (!seen.menubar.size) fail("메뉴 막대에 올라간 고양이가 없다");
if (chased) fail("흔들지 않았는데 커서를 쫓았다 (" + chased + "번)");
B.onAction = null;


/* 창으로 뛰는 중(또는 뛸 차례를 기다리는 중)에 창이 닫히면, 내려앉자마자 바닥으로 떨어져야 한다 */
function jumpOntoClosing(queued) {
  W.update({ windows: [Object.assign({}, win)] }); B.onWorld(t);
  const seg = W.windowSegments(B.catH()).find((s) => s.id === win.id);
  const x = seg.a + 40, c = B.make({ key: queued ? "q" : "j", variant: "white" });
  B.setLine(c, window.catLine(c.cfg, { state: "idle", last: t }));
  [c.x, c.y] = W.clampFloor(x, seg.y + 120, window.deskSettings.size, B.catH());
  const jump = { type: "jump", x, y: seg.y, perch: { kind: "win", id: win.id, y: seg.y, a: seg.a, b: seg.b, dx: x - win.x } };
  c.queue = (queued ? [{ type: "move", x: x - 60, y: c.y, gait: "walk" }] : []).concat(jump, { type: "stay", pose: "sit", dur: 30000 });
  B.cats = [c];
  for (let i = 0; i < 4; i++) { t += DT * 1000; B.step(DT, t); }
  if (!queued && !(c.cur && c.cur.type === "jump")) fail(c.key + ": 시험 준비 실패, 뛰는 중이 아니다");
  W.update({ windows: [] }); B.onWorld(t);                                  // 창 닫힘: 앱이 한 번만 알린다
  for (let i = 0; i < Math.round(6 / DT); i++) { t += DT * 1000; B.step(DT, t); check(c, "뛰는 중 창 닫힘"); }
  if (c.perch && c.perch.kind === "win") fail(c.key + ": 닫힌 창 위에 떠 있다 (" + Math.round(c.x) + "," + Math.round(c.y) + ")");
}
jumpOntoClosing(false);
jumpOntoClosing(true);

/* 서로 놀기: 이미 짝지은 고양이는 셋째 고양이가 데려가지 못한다 */
{
  const friends = B.idle.find((o) => o.need === "friends");
  B.cats = ["f1", "f2", "f3"].map((key) => {
    const c = B.make({ key, variant: "white" });
    B.setLine(c, window.catLine(c.cfg, { state: "idle", last: t }));
    return c;
  });
  const [a] = B.cats;
  a.queue = friends.make(a, t) || [];
  const mate = B.cats.find((o) => o !== a && o.queue.some((s) => s.love));
  if (!a.queue.length || !mate) fail("서로 놀기: 첫 짝을 못 지었다");
  else {
    const third = B.cats.find((o) => o !== a && o !== mate), before = mate.queue;
    if (friends.make(third, t)) fail("서로 놀기: 노는 중인 " + a.key + "/" + mate.key + " 를 " + third.key + " 가 데려갔다");
    if (mate.queue !== before) fail("서로 놀기: " + mate.key + " 의 할 일이 바뀌었다");
  }

  /* 짝은 쉬는 중 또는 세션 없는 고양이만: 세션 없는 고양이는 깨워서 놀고, 일하는/기다리는 고양이는 못 데려간다 */
  const pair = (cfg, st) => {
    const a = B.make({ key: "p1", variant: "white" }), o = B.make(Object.assign({ key: "p2", variant: "white" }, cfg));
    B.setLine(a, window.catLine(a.cfg, { state: "idle", last: t }));
    B.setLine(o, window.catLine(o.cfg, st));
    B.cats = [a, o];
    return [a, o, friends.make(a, t)];
  };
  {
    const [, o, q] = pair({}, { state: "missing" });
    if (!q || !q.some((s) => s.love) || !o.queue.some((s) => s.love)) fail("서로 놀기: 세션 없는 고양이를 짝으로 못 골랐다");
  }
  {
    const [, o, q] = pair({}, { state: "working", last: t, doing: "편집" });
    if (q) fail("서로 놀기: " + o.line.state + " 고양이를 짝으로 데려갔다");
  }

  /* 먼저 온 고양이는 짝이 올 때까지 기다렸다가 함께 놀기 시작하고 함께 끝낸다. 짝이 안 오면 15초 안에 접고 혼자 놀지 않는다 */
  const meet = (key, spoil) => {
    const a = B.make({ key: key + "1", variant: "white" }), o = B.make({ key: key + "2", variant: "white" });
    [a, o].forEach((c) => B.setLine(c, window.catLine(c.cfg, { state: "idle", last: t })));
    [a.x, a.y] = W.clampFloor(200, 600, window.deskSettings.size, B.catH());
    [o.x, o.y] = W.clampFloor(900, 600, window.deskSettings.size, B.catH());
    B.cats = [a, o];
    a.queue = friends.make(a, t) || [];
    if (!a.queue.length) { fail("서로 놀기(" + key + "): 짝을 못 지었다"); return; }
    [a, o].forEach((c) => c.queue.forEach((s) => { if (s.type === "move") s.gait = "walk"; }));
    const am = a.queue.find((s) => s.type === "move"); [a.x, a.y] = [am.x, am.y];   // a 는 바로 도착, o 는 한참 걷는다
    const log = [];
    for (let i = 0; i < Math.round(30 / DT); i++) {
      t += DT * 1000;
      if (spoil && i === Math.round(1 / DT)) spoil(o);
      B.step(DT, t);
      log.push({ i, a: a.love, o: o.love, oHere: !!(o.cur && o.cur.type === "stay"), aMeet: !!(a.cur && a.cur.meet) });
    }
    return log;
  };
  {
    const log = meet("m");
    if (log) {
      const here = log.findIndex((f) => f.oHere);
      const first = (k) => log.findIndex((f) => f[k]), last = (k) => log.length - 1 - [...log].reverse().findIndex((f) => f[k]);
      if (here < 0) fail("서로 놀기: 늦은 짝이 끝내 도착하지 않았다");
      else if (log.slice(0, here).some((f) => f.a)) fail("서로 놀기: 먼저 온 고양이가 짝이 오기 전에 혼자 놀았다");
      if (first("a") < 0 || first("o") < 0) fail("서로 놀기: 둘 중 하나가 놀지 않았다");
      else {
        if (Math.abs(first("a") - first("o")) > 1) fail("서로 놀기: 노는 시작이 " + Math.abs(first("a") - first("o")) + "걸음 어긋났다");
        if (Math.abs(last("a") - last("o")) > 1) fail("서로 놀기: 노는 끝이 " + Math.abs(last("a") - last("o")) + "걸음 어긋났다");
      }
    }
  }
  [["잡힘", (o) => B.hold(o)], ["상태 바뀜", (o) => B.setLine(o, window.catLine(o.cfg, { state: "working", last: t, doing: "편집" }))]]
    .forEach(([why, spoil]) => {
      const log = meet("n", spoil);
      if (!log) return;
      if (log.some((f) => f.a)) fail("서로 놀기(" + why + "): 짝 없이 혼자 놀았다");
      if (log.slice(Math.round(16 / DT)).some((f) => f.aMeet)) fail("서로 놀기(" + why + "): 16초가 지나도 짝을 기다린다");
    });
}

/* 커서 흔들기: 가까운 쉬는 고양이 한 마리만 쫓아온다 */
{
  const size = window.deskSettings.size;
  const mk = (key, st, cfg, dx) => {
    const c = B.make(Object.assign({ key, variant: "white" }, cfg));
    B.setLine(c, window.catLine(c.cfg, st));
    [c.x, c.y] = W.clampFloor(500 + (dx || 0), 600, size, B.catH());
    c.queue = [{ type: "stay", pose: "sit", dur: 120000 }];
    return c;
  };
  const mouse = (x, y) => { t += 66; W.update({ mouse: { x, y, t } }); B.step(0.066, t); };   // 앱은 15Hz 로 보낸다
  const shake = (c, ox) => { for (let i = 0; i < 8; i++) mouse(c.x + (ox || 0) + (i % 2 ? 40 : -40), c.y - B.catH() / 2); };
  const zigzag = (c, turns) => {                                     // 한 번 긋는 데 2표본(133ms), 방향을 turns번 바꾼다
    let x = c.x - 30; mouse(x, c.y - B.catH() / 2);
    for (let s = 0; s <= turns; s++) for (let k = 0; k < 2; k++) { x += (s % 2 ? -30 : 30); mouse(x, c.y - B.catH() / 2); }
  };
  const wait = (sec) => { for (let i = 0; i < Math.round(sec / DT); i++) { t += DT * 1000; B.step(DT, t); } };
  const chasing = (c) => !!(c.cur && c.cur.type === "chase");
  const startled = (c) => !!(c.cur && c.cur.hop);                    // 흔들면 먼저 1초 놀라서 제자리 점프
  const caught = (c) => startled(c) || chasing(c);
  const idle = () => ({ state: "idle", last: t });                     // 각 시험 앞 wait(1.6): 앞 시험의 흔들기가 잊히게

  { const a = mk("w1", idle()), b = mk("w2", idle(), {}, size * 0.8); wait(1.6); B.cats = [a, b];
    shake(a);
    if (!startled(a) || a.pose !== "alert") fail("흔들기: 쉬는 고양이가 놀라지 않았다");
    if (caught(b)) fail("흔들기: 두 마리가 함께 쫓아왔다");
    wait(1.1);
    if (!chasing(a)) fail("흔들기: 놀란 뒤 쫓아오지 않았다"); }
  { const a = mk("w3", { state: "missing" }); wait(1.6); B.cats = [a]; shake(a);
    if (!caught(a)) fail("흔들기: 세션 없는 고양이가 쫓아오지 않았다"); }
  { const a = mk("w4", { state: "working", last: t, doing: "편집" }); wait(1.6); B.cats = [a]; shake(a);
    if (caught(a)) fail("흔들기: " + a.line.state + " 고양이가 쫓아왔다"); }
  { const a = mk("w11", idle()); wait(1.6); B.cats = [a]; zigzag(a, 4);   // 15Hz 로 1초 안에 4번 바꾸면 아직, 5번이면 반응
    if (caught(a)) fail("흔들기: 방향을 4번만 바꿨는데 쫓아왔다");
    wait(1.6); zigzag(a, 5);
    if (!caught(a)) fail("흔들기: 1초 안에 방향을 5번 바꿨는데 쫓아오지 않았다"); }
  { const a = mk("w5", idle()); wait(1.6); B.cats = [a];
    for (let i = 0; i < 14; i++) mouse(a.x - 200 + i * 30, a.y - B.catH() / 2);
    if (caught(a)) fail("흔들기: 한 방향으로 지나가기만 했는데 쫓아왔다"); }
  { const a = mk("w6", idle()); wait(1.6); B.cats = [a]; shake(a, size * 1.5 + 60);
    if (caught(a)) fail("흔들기: 멀리서 흔들었는데 쫓아왔다"); }
  { const a = mk("w8", idle()); wait(1.6); B.cats = [a]; a.dir = 1;   // 놀람: 커서 쪽을 보고 제자리에서 뛰었다 내려앉고, 그동안 다시 흔들어도 그대로
    const x0 = a.x, y0 = a.y;
    shake(a, -60);                                                     // 커서는 왼쪽에서 멈춘다
    const s0 = a.cur;
    if (!startled(a)) fail("놀람: 흔들었는데 놀라지 않았다");
    else {
      if (a.dir !== -1) fail("놀람: 커서 쪽(왼쪽)을 보지 않았다");
      let air = 0, start = 0;
      const look = () => { if (startled(a) && a.frame === 1 && a.lift > 0) air++; };
      for (let i = 0; i < 8; i++) { mouse(a.x - 60 + (i % 2 ? 40 : -40), a.y - B.catH() / 2); look(); }   // 다시 흔든다
      if (a.cur !== s0 || a.queue.length !== 2) fail("놀람: 놀라는 중에 다시 흔들었더니 처음부터 다시 했다");
      for (let i = 0; i < Math.round(1.5 / DT) && !start; i++) {
        t += DT * 1000; B.step(DT, t);
        look();
        if (startled(a) && (a.x !== x0 || a.y !== y0)) fail("놀람: 뛰는 사이 자리가 바뀌었다");
        if (chasing(a)) start = t;
      }
      if (!air) fail("놀람: 공중에 뜬 적이 없다");
      if (!start || Math.abs(start - s0.t0 - 1000) > 100) fail("놀람: 1초 뒤에 쫓기 시작하지 않았다");
      else {
        if (a.x !== x0 || a.y !== y0 || a.lift) fail("놀람: 제자리에 내려앉지 않았다");
        if (a.cur.until !== start + 30000) fail("놀람: 30초를 쫓기 시작부터 세지 않았다");
      }
    } }
  { const a = mk("w9", idle(), {}, -350); wait(1.6); B.cats = [a];  // 커서가 너무 멀리 가면 흥미를 잃는다. 잠깐은 괜찮다
    const far = size * B.chaseFar + 400, away = (sec) => {
      for (let i = 0; i < Math.round(sec * 15); i++) mouse(a.x + far + (i % 2 ? 20 : -20), a.y - B.catH() / 2);
    };
    shake(a);
    for (let i = 0; i < 20; i++) mouse(a.x + 60 + (i % 2) * 20, a.y - B.catH() / 2);
    if (!chasing(a)) fail("멀어짐: 시험 준비 실패, 쫓는 중이 아니다");
    away(0.3);                                                         // 0.5초가 안 되게 잠깐
    for (let i = 0; i < 30; i++) mouse(a.x + 60 + (i % 2) * 20, a.y - B.catH() / 2);
    if (!chasing(a)) fail("멀어짐: 잠깐 멀어졌다 돌아왔는데 그만뒀다");
    const t0 = t; let end = 0;
    for (let i = 0; i < 4 * 15 && !end; i++) { away(1 / 15); if (!chasing(a)) end = t - t0; }
    if (end < 500 || end > 1000) fail("멀어짐: 멀리 간 지 " + (end / 1000) + "초 만에 그만뒀다 (0.5~1초여야)"); }
  { const a = mk("w10", idle(), {}, -350); wait(1.6); B.cats = [a]; // 실제로 났던 일: 커서가 멀리 한 곳에 머물면 고양이가 달려가 문턱 안으로 들어와 버린다
    shake(a);
    for (let i = 0; i < 20; i++) mouse(a.x + 60 + (i % 2) * 20, a.y - B.catH() / 2);
    if (!chasing(a)) fail("멀어짐(고정): 시험 준비 실패, 쫓는 중이 아니다");
    const fx = a.x + size * 7, fy = a.y - B.catH() / 2, t0 = t;        // 너비의 7배 떨어진 곳으로 옮겨 거의 가만히 둔다 (조금씩 움직여 3초 규칙은 안 걸리게)
    let end = 0;
    for (let i = 0; i < 3 * 15 && !end; i++) { mouse(fx, fy + (i % 2 ? 6 : -6)); if (!chasing(a)) end = t - t0; }
    if (!end || end > 1000) fail("멀어짐(고정): 커서가 멀리 머문 지 " + (end ? end / 1000 + "초 만에" : "3초가 지나도") + " 그만뒀다 (1초 안이어야)"); }
  { const a = mk("w7", idle()); wait(1.6); B.cats = [a]; shake(a);
    wait(3.5);
    if (chasing(a)) fail("흔들기: 커서가 멈추고 3초가 지나도 쫓는다");
    wait(2); shake(a);
    if (!caught(a)) fail("흔들기: 두 번째로 흔들었는데 쫓아오지 않았다");
    const cx = a.x, cy = a.y - 200, t0 = t;
    let lastChase = 0, start = 0;
    for (let i = 0; i < 36 * 15; i++) {                                    // 4초에 한 바퀴 원을 그리며 계속 움직인다
      const u = (t - t0) / 4000 * 2 * Math.PI;
      mouse(cx + 150 * Math.cos(u), cy + 80 * Math.sin(u));
      if (chasing(a)) { start = start || t; lastChase = t - start; }
    }
    if (lastChase < 29000 || lastChase > 30500) fail("흔들기: 계속 움직일 때 " + Math.round(lastChase / 1000) + "초 쫓았다 (30초여야)"); }
}

console.log("모의 " + STEPS + "걸음 (" + Math.round(STEPS * DT / 60) + "분), 고양이 " + main.length + "마리");
console.log("창 위: " + ([...seen.win].join(",") || "-") + " / 메뉴 막대: " + ([...seen.menubar].join(",") || "-"));
console.log("마지막 자세: " + main.map((c) => c.key + "=" + c.pose).join(" "));
if (fails.length) { console.log("실패:\n  " + fails.join("\n  ")); process.exit(1); }
console.log("통과");
