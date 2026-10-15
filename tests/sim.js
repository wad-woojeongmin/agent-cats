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

const win = { id: 1, x: 600, y: 300, w: 560, h: 380 };
W.update({ menubar: 24, windows: [Object.assign({}, win)], icons: [{ x: 40, y: 80, w: 64, h: 64 }] });

const now0 = 1e12;
const cfgs = [
  { key: "a", variant: "white" }, { key: "b", variant: "tabby" }, { key: "c", variant: "white" },
  { key: "d", variant: "white" }, { key: "e", variant: "white", fixed: { main: "기다리는 중" } }
];
const status = {
  a: { state: "idle", last: now0 }, b: { state: "idle", last: now0 },
  c: { state: "working", last: now0, doing: "편집" }, d: { state: "missing" }
};
B.cats = cfgs.map((cfg) => B.make(cfg));
B.cats.forEach((c) => B.setLine(c, window.catLine(c.cfg, status[c.key])));
const main = B.cats;                                             // 뒤 시험들이 B.cats 를 갈아 끼운다

const DT = 0.033, STEPS = Math.round(20 * 60 / DT);
const seen = { win: new Set(), menubar: new Set() };
let t = now0;

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
}

console.log("모의 " + STEPS + "걸음 (" + Math.round(STEPS * DT / 60) + "분), 고양이 " + main.length + "마리");
console.log("창 위: " + ([...seen.win].join(",") || "-") + " / 메뉴 막대: " + ([...seen.menubar].join(",") || "-"));
console.log("마지막 자세: " + main.map((c) => c.key + "=" + c.pose).join(" "));
if (fails.length) { console.log("실패:\n  " + fails.join("\n  ")); process.exit(1); }
console.log("통과");
