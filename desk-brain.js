/* 고양이마다 다음에 무엇을 할지 정하고, 지금 하는 일을 한 걸음씩 진행한다.
   한 고양이의 할 일은 단계(step) 목록이다:
     move  {x, y, gait}            바닥이나 횃대 위를 걸어/달려서 간다
     jump  {x, y, perch}           포물선으로 뛰어 (횃대에) 내려앉는다
     stay  {pose, dur, face, love} 제자리에서 한 자세로 머문다
           {hop}                   놀라서 제자리 점프(alert). 높이는 c.lift(px)로만 주고 x, y 는 그대로
           {meet}                  서로 놀기: 짝도 meet 단계에 오면 같이 다음(놀기)으로, dur 안에 안 오면 놀기를 건너뛴다
     chase {dur}                   커서를 쫓아가 톡톡 친다 (커서를 흔들 때만). until 은 시작할 때 정한다 */
(function () {
  const W = window.deskWorld, G = window.CAT_GRID;
  const S = window.deskSettings = {
    size: 96, activity: 0.5, bubbleSec: 60, enabled: true,
    behaviors: { walk: true, run: true, jump: true, stretch: true, chase: true, window: true,
                 windowSide: true, menubar: true, icons: true, friends: true }
  };
  const SPEED = { walk: 46, run: 170 };
  const TICK = { walk: 150, run: 90 };
  const CHASE_FAR = 5;                                 // 커서가 고양이 너비의 이 배보다 CHASE_FAR_GRACE 넘게 멀어지면 쫓기를 그만둔다
  const CHASE_FAR_GRACE = 500;                         // ms. 짧아야 한다: 고양이가 170px/s 로 다가가므로 1.5초면 문턱 안으로 들어와 버린다
  const rand = W.rand, pick = (a) => a[Math.floor(Math.random() * a.length)];
  const catW = () => S.size, catH = () => S.size * G.h / G.w;
  const on = (k) => S.behaviors[k] !== false;
  const slow = () => 1.6 - S.activity;                 // 활발할수록 한자리에 짧게 머문다
  const B = window.deskBrain = { cats: [], catH };               // catH: 고양이 그림 높이(px). tests/sim.js 가 쓴다
  B.onAction = null;                                             // (c, step): 새 걸음을 시작할 때. desk-view.js 가 디버그 기록에 쓴다

  B.make = function (cfg, saved) {
    const [x, y] = saved ? W.clampFloor(saved.x, saved.y, catW(), catH()) : W.randomFloor(catW(), catH());
    return { cfg, key: cfg.key, x, y, dir: Math.random() < .5 ? 1 : -1, perch: null, pinned: !!(saved && saved.pinned),
             line: { state: "idle", pose: "sleep" }, cur: null, queue: [], pose: "sit", frame: 0,
             tick: 0, tickAt: 0, shut: false, held: false, love: false };
  };

  /* ---------- 이동 계획 ---------- */
  function gait() {
    if (!on("walk") && !on("run")) return null;
    if (!on("walk")) return "run";
    return on("run") && Math.random() < 0.15 + 0.3 * S.activity ? "run" : "walk";
  }

  /* 지금 자리에서 (x, y) 바닥, 또는 perch 위 x 까지 가는 단계들 */
  function travel(c, x, y, perch) {
    const g = gait();
    if (!g) return null;
    const steps = [];
    if (c.perch && !(perch && samePerch(c.perch, perch))) {          // 횃대에서 먼저 내려온다
      const [fx, fy] = W.clampFloor(c.x + c.dir * 30, c.y + rand(120, 220), catW(), catH());
      steps.push({ type: "jump", x: fx, y: fy, perch: null });
    }
    if (perch && !(c.perch && samePerch(c.perch, perch))) {
      if (!on("jump")) return null;
      const [ax, ay] = W.clampFloor(x - c.dir * 20, perch.y + rand(70, 140), catW(), catH());
      steps.push({ type: "move", x: ax, y: ay, gait: g });
      steps.push({ type: "jump", x, y: perch.y, perch });
    } else if (perch) {
      steps.push({ type: "move", x, y: perch.y, gait: "walk" });
    } else {
      steps.push({ type: "move", x, y, gait: g });
    }
    return steps;
  }
  function samePerch(a, b) { return a.kind === b.kind && (a.kind === "menubar" || a.id === b.id); }
  const stay = (pose, dur, extra) => Object.assign({ type: "stay", pose, dur: dur * 1000 }, extra || {});

  /* ---------- 쉬는 고양이가 고를 수 있는 일 ---------- */
  const IDLE = [
    { w: 3, mobile: true, make(c) {                                   // 돌아다니기
      if (c.perch && Math.random() < .5) return travel(c, rand(c.perch.a + 20, c.perch.b - 20), c.y, c.perch);
      const [x, y] = W.randomFloor(catW(), catH());
      const t = travel(c, x, y); return t && t.concat(stay(pick(["sit", "rest"]), rand(3, 8) * slow()));
    } },
    { w: 2, make: () => [stay("sit", rand(6, 14) * slow())] },
    { w: 2, make: () => [stay("rest", rand(8, 20) * slow())] },
    { w: 2, make: () => [stay("sleep", rand(25, 60) * slow())] },
    { w: 1, need: "stretch", make: () => [stay("stretch", 3.2), stay("sit", rand(3, 6))] },
    { w: 1, need: "run", mobile: true, make(c) {
      const [x, y] = W.randomFloor(catW(), catH());
      if (c.perch) return null;
      return [{ type: "move", x, y, gait: "run" }, stay("sit", rand(2, 5))];
    } },
    { w: 1.2, need: "window", mobile: true, make(c) {                 // 창 위에 올라가기
      const segs = W.windowSegments(catH());
      if (!segs.length) return null;
      const s = pick(segs), x = rand(s.a + 20, s.b - 20);
      const t = travel(c, x, s.y, { kind: "win", id: s.id, y: s.y, a: s.a, b: s.b, dx: x - s.win.x });
      return t && t.concat(stay(pick(["sit", "rest", "sleep"]), rand(12, 40) * slow()));
    } },
    { w: .6, need: "windowSide", mobile: true, make(c) {              // 창 옆에서 기웃거리기
      const wins = W.visibleWindows();
      if (!wins.length) return null;
      const win = pick(wins), left = Math.random() < .5;
      const x = left ? win.x - catW() * 0.35 : win.x + win.w + catW() * 0.35;
      if (x < W.floor.left + 20 || x > W.floor.right - 20) return null;
      const [fx, fy] = W.clampFloor(x, win.y + rand(Math.min(120, win.h * .4), win.h - 10), catW(), catH());
      const t = travel(c, fx, fy);
      return t && t.concat(stay("play", rand(4, 7), { face: left ? 1 : -1 }), stay("sit", rand(4, 8), { face: left ? 1 : -1 }));
    } },
    { w: .6, need: "menubar", mobile: true, make(c) {                 // 메뉴 막대에 앉기
      const p = W.menubarPerch();
      if (!p) return null;
      const x = rand(p.a + 40, p.b - 40);
      const t = travel(c, x, p.y, Object.assign({}, p, { dx: 0 }));
      return t && t.concat(stay(pick(["sit", "rest"]), rand(10, 25) * slow()));
    } },
    { w: .8, need: "icons", mobile: true, make(c) {                   // 바탕화면 아이콘 톡톡
      if (!W.icons.length) return null;
      const ic = pick(W.icons), left = Math.random() < .5;
      const x = left ? ic.x - catW() * 0.3 : ic.x + ic.w + catW() * 0.3;
      const [fx, fy] = W.clampFloor(x, ic.y + ic.h * .8, catW(), catH());
      const t = travel(c, fx, fy);
      return t && t.concat(stay("play", rand(4, 7), { face: left ? 1 : -1 }), stay("sit", 3, { face: left ? 1 : -1 }));
    } },
    { w: .8, need: "friends", mobile: true, make(c) {                 // 서로 놀기: 짝은 쉬는 중 또는 세션 없음 고양이
      const mates = B.cats.filter((o) => o !== c && free(o) && (o.line.state === "idle" || o.line.state === "missing"));
      if (!mates.length) return null;
      const o = pick(mates);
      const gap = catW() * 0.42;
      const [mx, my] = W.clampFloor((c.x + o.x) / 2, (c.y + o.y) / 2, catW() + gap, catH());
      const mine = travel(c, mx - gap, my), theirs = travel(o, mx + gap, my);
      if (!mine || !theirs) return null;
      const dur = rand(6, 9), pair = { cats: [c, o] };                // 둘 다 도착해야 같이 논다
      const after = (face) => [stay("sit", 15, { face, meet: pair }), stay("play", dur, { face, love: true }), stay("sit", 3, { face })];
      o.queue = theirs.concat(after(-1));
      o.cur = null;
      return mine.concat(after(1));
    } }
  ];
  B.chaseFar = CHASE_FAR;                                             // tests/sim.js 가 쓴다
  B.idle = IDLE;                                                      // tests/sim.js 가 '서로 놀기'를 바로 불러 본다
  const free = (o) => !o.pinned && !o.held && !o.perch && (!o.cur || o.cur.type === "stay") &&
                      ![o.cur].concat(o.queue).some((s) => s && (s.love || s.meet));   // 이미 다른 친구와 노는(기다리는) 중이면 빼 둔다

  function choose(c, now) {
    const st = c.line.state;
    if (st === "working") return [Math.random() < .12 && on("stretch") ? stay("stretch", 3.2) : stay("work", rand(40, 90))];
    if (c.pinned) {
      if (st === "missing") return [stay("sleep", 120)];
      return [stay(pick(["sit", "rest", "sleep", "sleep"]), rand(15, 40))];
    }
    if (st === "missing") {
      if (Math.random() < .2) { const [x, y] = W.randomFloor(catW(), catH()); const t = travel(c, x, y); if (t) return t.concat(stay("sleep", 90)); }
      return [stay("sleep", rand(60, 160))];
    }
    const opts = IDLE.filter((o) => !o.need || on(o.need));
    for (let tries = 0; tries < 6; tries++) {
      const total = opts.reduce((s, o) => s + o.w * (o.mobile ? 0.5 + S.activity : 1), 0);
      let r = Math.random() * total, o = opts[0];
      for (const x of opts) { r -= x.w * (x.mobile ? 0.5 + S.activity : 1); if (r <= 0) { o = x; break; } }
      const steps = o.make(c, now);
      if (steps && steps.length) return steps;
    }
    return [stay("sit", 8)];
  }

  /* ---------- 한 걸음 ---------- */
  function begin(c, step, now) {
    step.t0 = now;
    if (step.type === "jump") { step.x0 = c.x; step.y0 = c.y; step.dur = 450 + Math.min(500, Math.hypot(step.x - c.x, step.y - c.y)); c.perch = null; }
    if (step.type === "stay" && step.face) c.dir = step.face;
    if (step.type === "chase") step.until = now + step.dur;
    c.cur = step;
    B.onAction?.(c, step);
  }

  function advance(c, dt, now) {
    c.lift = 0;
    if (c.held) { c.pose = "jump"; c.frame = 1; return; }
    const s = c.cur;
    c.love = false;
    if (s.type === "move" || s.type === "chase") {
      let tx = s.x, ty = s.y, g = s.gait;
      if (s.type === "chase") {
        tx = W.mouse.x; ty = W.clampFloor(W.mouse.x, W.mouse.y + catH() * 0.3, catW(), catH())[1]; g = "run";
        if (now > s.until || now - W.mouse.moved > 3000) return finish(c, now);   // 다른 화면으로 가면 위치가 안 오므로 멈춘 것과 같다
        if (Math.hypot(W.mouse.x - c.x, W.mouse.y - (c.y - catH() / 2)) <= catW() * CHASE_FAR) s.far = 0;   // 너무 멀리 가 있으면 흥미를 잃는다
        else if (!s.far) s.far = now;
        else if (now - s.far > CHASE_FAR_GRACE) return finish(c, now);
      }
      if (c.perch) ty = c.y;
      const dx = tx - c.x, dy = ty - c.y, d = Math.hypot(dx, dy), v = SPEED[g] * dt;
      if (Math.abs(dx) > 2) c.dir = dx > 0 ? 1 : -1;
      if (d <= Math.max(v, s.type === "chase" ? catW() * 0.45 : 2)) {
        if (s.type === "chase") { c.pose = "play"; c.frame = 0; return; }
        c.x = tx; c.y = ty; return finish(c, now);
      }
      c.x += dx / d * v; c.y += dy / d * v;
      if (c.perch) {
        c.x = Math.min(Math.max(c.x, c.perch.a), c.perch.b);
        markDx(c);
      }
      c.pose = g; c.frame = 0;
    } else if (s.type === "jump") {
      const t = Math.min(1, (now - s.t0) / s.dur);
      if (Math.abs(s.x - s.x0) > 2) c.dir = s.x > s.x0 ? 1 : -1;
      c.pose = "jump";
      if (t < .18) { c.frame = 0; return; }
      const u = (t - .18) / .82, arc = 40 + Math.min(80, Math.abs(s.x - s.x0) * .15);
      c.frame = 1;
      c.x = s.x0 + (s.x - s.x0) * u;
      c.y = s.y0 + (s.y - s.y0) * u - arc * 4 * u * (1 - u);
      if (t >= 1) {
        c.x = s.x; c.y = s.y;
        if (s.perch) { c.perch = Object.assign({}, s.perch); markDx(c); }
        if (s.perch && s.perch.kind === "win" && !settle(c, now)) return;   // 뛰는 사이 창이 닫혔을 수 있다
        finish(c, now);
      }
    } else {
      const m = s.meet;
      if (m && m.cats.every((o) => B.cats.includes(o) && o.cur && o.cur.meet === m)) {   // 둘 다 왔다: 같은 순간 함께 놀기 시작
        m.cats.forEach((o) => finish(o, now));
        return advance(c, dt, now);
      }
      c.pose = s.pose; c.frame = 0; c.love = !!s.love;
      if (s.hop) {                                                    // 웅크림 -> 공중 -> 착지 웅크림 -> 섬
        const u = (now - s.t0) / s.dur, p = (u - .15) / .45;
        c.frame = u < .15 || (u >= .6 && u < .72) ? 0 : u < .6 ? 1 : 2;
        if (c.frame === 1) c.lift = catH() * .4 * 4 * p * (1 - p);
      }
      if (now - s.t0 > s.dur) {
        if (m) c.queue = c.queue.filter((x) => !x.love);              // 짝이 끝내 안 왔다: 혼자 놀지 않는다
        finish(c, now);
      }
    }
  }
  function finish(c, now) { c.cur = null; const next = c.queue.shift(); if (next) begin(c, next, now); }

  /* 창 횃대면 창 왼쪽 끝에서 고양이까지(dx)를 다시 잰다. 창이 움직이면 이만큼 떨어져 따라간다 */
  function markDx(c) {
    const win = c.perch && c.perch.kind === "win" && W.windows.find((w) => w.id === c.perch.id);
    if (win) c.perch.dx = c.x - win.x;
  }

  /* 횃대를 지금 세계에 맞춘다. 횃대가 사라졌으면 바닥으로 뛰어내리고 false */
  function settle(c, now) {
    const p = W.refreshPerch(c.perch, c.x, catH());
    if (!p) {
      const [fx, fy] = W.clampFloor(c.x, c.y + rand(140, 240), catW(), catH());
      c.perch = null; c.queue = [stay("sit", 3)];
      begin(c, { type: "jump", x: fx, y: fy, perch: null }, now);
      return false;
    }
    c.perch = p;
    if (p.kind === "win") c.x = p.x;
    c.y = p.y;
    return true;
  }

  /* 고양이 가까이서 커서를 흔들면 가장 가까운 쉬는 고양이가 하던 일을 접고 쫓아온다 */
  function wiggled(now) {
    const m = W.mouse;
    if (!on("chase") || m.hist.length < 4 || !W.wiggle(now)) return;
    let near = null, best = catW() * 1.5;
    B.cats.forEach((c) => {
      const st = c.line.state, s = c.cur;
      if ((st !== "idle" && st !== "missing") || c.pinned || c.held || c.perch || (s && (s.type === "jump" || s.type === "chase" || s.hop))) return;
      const d = Math.hypot(m.x - c.x, m.y - (c.y - catH() / 2));      // 몸 가운데까지
      if (d <= best) { near = c; best = d; }
    });
    if (!near) return;
    m.hist = [];                                                      // 다음은 새로 흔들어야 한다
    near.queue = [{ type: "chase", dur: 30000 }, stay("sit", 3)];       // 1초 놀라고 나서 쫓는다. 30초는 쫓기 시작부터
    begin(near, stay("alert", 1, { face: m.x >= near.x ? 1 : -1, hop: true }), now);
  }

  /* 큐가 비면 새 계획을 세운다 */
  B.step = function (dt, now) {
    wiggled(now);
    B.cats.forEach((c) => {
      if (!c.cur && !c.held) {
        if (!c.queue.length) c.queue = choose(c, now);
        begin(c, c.queue.shift(), now);
      }
      advance(c, dt, now);
      const every = TICK[c.pose] || 260;                                     // 애니메이션 박자
      if (now - c.tickAt >= every) { c.tick++; c.tickAt = now; }
      if (!c.shut && Math.random() < dt / 3.6) { c.shut = true; c.shutAt = now; }
      if (c.shut && now - c.shutAt > 140) c.shut = false;
    });
  };

  /* 창이 움직이면 횃대 위 고양이가 따라가고, 횃대가 사라지면 떨어진다 */
  B.onWorld = function (now) {
    B.cats.forEach((c) => {
      if (c.perch && !c.held && !(c.cur && c.cur.type === "jump")) settle(c, now);   // 뛰는 중이면 내려앉을 때 맞춘다
    });
  };

  /* 상태가 바뀌면(일 시작, 쉬기 시작) 하던 일을 접는다 */
  B.setLine = function (c, line) {
    const changed = c.line.state !== line.state;
    c.line = line;
    if (changed && !c.held && !(c.cur && c.cur.type === "jump")) { c.cur = null; c.queue = []; }
  };

  B.hold = function (c) { c.held = true; c.cur = null; c.queue = []; c.perch = null; };
  B.drop = function (c, x, y) {
    c.held = false;
    const p = W.perchNear(x, y, catH());
    if (p) {
      c.x = Math.min(Math.max(x, p.a), p.b); c.y = p.y;
      c.perch = Object.assign({}, p); markDx(c);
    } else {
      [c.x, c.y] = W.clampFloor(x, y, catW(), catH());
      c.perch = null;
    }
    c.queue = [];
    begin(c, stay("sit", 4), Date.now());
  };
  B.setPinned = function (c, v) { c.pinned = v; c.cur = null; c.queue = []; };
  B.snapshot = function () {
    const o = {};
    B.cats.forEach((c) => { o[c.key] = { x: Math.round(c.x), y: Math.round(c.y), pinned: c.pinned }; });
    return o;
  };
})();
