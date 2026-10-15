/* 데스크톱 화면: 고양이를 그리고 옮기고, 말풍선을 띄우고, 클릭·드래그·우클릭을 받는다.
   앱(Swift)과는 window.webkit.messageHandlers.cat 으로 말을 주고받는다 (desk.* 함수가 받는 쪽). */
(function () {
  const W = window.deskWorld, B = window.deskBrain, S = window.deskSettings, G = window.CAT_GRID;
  const layer = document.getElementById("pets");      // 고양이 몸
  const over = document.getElementById("overlay");    // 말풍선, 노란 "!" (어느 고양이보다 위)
  const staleEl = document.getElementById("stale");
  const MOVE_POSES = { walk: 1, run: 1, jump: 1, stretch: 1, rest: 1, play: 1, alert: 1 };
  let signature = "", lastRects = "", rectsAt = 0, savedAt = Date.now(), data = null, home = "";
  const greets = {};   // key → {text, until}: 앱이 보낸 인사. 그 고양이가 이 화면에 있거나 생기면 한 번 띄운다
  let attention = {};  // key → "reply" | "question": 사용자 차례라 머리 위에 노란 "!" (클릭하면 확인)

  const post = (msg) => { if (W.native) window.webkit.messageHandlers.cat.postMessage(msg); };
  const cell = () => S.size / G.w;
  const actLabel = (s) => s.type === "stay" ? "stay:" + s.pose + (s.love ? "+love" : "")
    : s.type === "move" ? "move:" + s.gait : s.type === "jump" ? "jump" + (s.perch ? "->" + s.perch.kind : "") : s.type;
  const saved = () => S.saved || (window.DESKTOP_SAVED && window.DESKTOP_SAVED.cats) || {};

  /* 이 디스플레이에 사는 고양이인지. 앱이 S.screen(이 화면)과 S.assign(고양이 → 화면)을 준다.
     브라우저에서 열면 둘 다 없어서 모두 보인다 */
  const mine = (cfg) => !S.screen || !S.assign || S.assign[cfg.key] === S.screen;

  /* ---------- 고양이 만들기 ---------- */
  function build(config) {
    const keep = {};
    B.cats.forEach((c) => { keep[c.key] = c; c.el.remove(); c.short.remove(); c.detail.remove(); c.bang.remove(); });
    B.cats = config.cats.filter((cfg) => !cfg.hidden && mine(cfg)).map((cfg, i) => {
      const old = keep[cfg.key];
      const c = old ? Object.assign(old, { cfg }) : B.make(cfg, saved()[cfg.key]);
      c.el = document.createElement("div");
      c.el.className = "pet";
      c.el.innerHTML = '<div class="art"></div><span class="zzz" aria-hidden="true"><i>z</i><i>z</i><i>Z</i></span><span class="hearts" aria-hidden="true"><i>♥</i><i>♥</i></span>';
      c.art = c.el.querySelector(".art");
      c.short = bubble("short"); c.detail = bubble("detail");
      c.bang = document.createElement("div");                            // 클릭은 통과 (hit rect 에도 안 넣는다)
      c.bang.className = "bang"; c.bang.hidden = true; c.bang.innerHTML = window.bangSVG("?");
      over.appendChild(c.bang);
      c.drawKey = ""; c.bbox = [0, 0, G.w, G.h];
      c.nextBubble = Date.now() + 4000 + i * 2500;
      layer.appendChild(c.el);
      c.el.addEventListener("pointerdown", (e) => grab(e, c));
      c.el.addEventListener("contextmenu", (e) => { e.preventDefault(); menu(c); });
      return c;
    });
    sendThumbs();
  }

  function bubble(kind) {
    const el = document.createElement("div");
    el.className = "bubble " + kind;
    el.innerHTML = kind === "short" ? '<b class="b-main"></b>' : '<b class="b-main"></b><span class="b-sub"></span><small class="b-meta"></small>';
    el.hidden = true;
    over.appendChild(el);
    return el;
  }

  /* ---------- 상태 ---------- */
  function apply() {
    data = window.CATTEAM;
    if (!data) return;
    const sig = JSON.stringify([data.cats, data.cats.filter(mine).map((c) => c.key)]);
    if (sig !== signature) { signature = sig; build(data); }
    staleEl.hidden = W.native || S.main === false || Date.now() - data.updated < (data.staleSec || 60) * 1000;   // 경고는 브라우저 주 화면에만 (앱은 직접 수집하고 오류는 메뉴에)
    const lines = {};
    B.cats.forEach((c) => {
      const line = window.catLine(c.cfg, (data.status || {})[c.key]);
      B.setLine(c, line);
      lines[c.key] = { short: line.short, state: line.state };
      fillDetail(c);   // 떠 있든 아니든 늘 최신으로
    });
    post({ type: "lines", items: lines });
    sayGreets(Date.now());
  }

  function sayGreets(now) {
    B.cats.forEach((c) => {
      const g = greets[c.key];
      if (!g) return;
      delete greets[c.key];
      c.detailUntil = 0; c.detail.hidden = true;
      showShort(c, now, g.text);
      c.nextBubble = Math.max(c.nextBubble, now + 4000);
    });
    for (const k in greets) if (now > greets[k].until) delete greets[k];   // 다른 화면에 사는 고양이 것
  }

  const poll = () => window.catPoll(apply);

  /* ---------- 말풍선 ---------- */
  function fillDetail(c) {
    const line = window.catLine(c.cfg, (data.status || {})[c.key]);
    c.detail.querySelector(".b-main").textContent = window.catLabel(c.cfg) + " · " + line.main;
    c.detail.querySelector(".b-sub").textContent = line.sub;
    c.detail.querySelector(".b-meta").textContent = line.meta;
  }
  const working = (c) => c.line && c.line.state === "working";
  const detailOn = (c, now) => working(c) || now < (c.detailUntil || 0);   // 일하는 동안은 늘, 아니면 클릭 후 8초
  function showShort(c, now, text) {
    if (!text && detailOn(c, now)) return;   // 인사는 자세한 말풍선을 잠깐 가린다
    c.short.querySelector(".b-main").textContent = text || c.line.short + (c.line.state === "working" ? " .." : "");
    c.short.hidden = false; c.shortUntil = now + 4000;
  }
  function showDetail(c) {   // 일하는 고양이는 이미 떠 있으니 그대로
    if (!data || working(c)) return;
    fillDetail(c); c.short.hidden = true;
    c.detailUntil = Date.now() + 8000;
  }

  /* placed: 이번 프레임에 먼저 놓인 말풍선들. 겹치면 위로 비켜 선다 */
  function placeBubble(c, el, box, placed) {
    if (el.hidden) return;
    const bw = el.offsetWidth, bh = el.offsetHeight, cx = (box[0] + box[2]) / 2;
    let left = Math.min(Math.max(cx - bw / 2, 8), W.w - bw - 8);
    let top = box[1] - bh - 12, below = top < W.menubar + 4;
    if (below) top = box[3] + 12;
    for (let i = 0; i < placed.length; i++) {
      const p = placed[i];
      if (left < p[2] + 4 && left + bw > p[0] - 4 && top < p[3] + 4 && top + bh > p[1] - 4) {
        top = below ? p[3] + 6 : p[1] - bh - 6; i = -1;
      }
    }
    placed.push([left, top, left + bw, top + bh]);
    el.classList.toggle("below", below);
    el.style.transform = "translate(" + Math.round(left) + "px," + Math.round(top) + "px)";
    el.style.setProperty("--tail", Math.round(Math.min(Math.max(cx - left, 16), bw - 16)) + "px");
  }

  /* 노란 "!": 그림 경계의 위 오른쪽. 놀란 "!" 가 떠 있거나 들고 있으면 숨긴다. 말풍선이 비켜 서도록 경계를 넓혀 돌려준다 */
  function placeBang(c) {
    const el = c.bang, k = cell();
    el.hidden = !attention[c.key] || c.pose === "alert" || c.held;
    if (el.hidden) return c.box;
    const w = window.BANG_GRID.w * k, h = window.BANG_GRID.h * k;
    const left = Math.min(Math.max(c.box[2] - w - k, 0), W.w - w);
    const top = Math.min(Math.max(c.box[1] - h, 0), W.h - h);
    el.style.width = w + "px";
    el.style.transform = "translate(" + Math.round(left) + "px," + Math.round(top) + "px)";
    return [c.box[0], Math.min(c.box[1], top), c.box[2], c.box[3]];
  }

  /* ---------- 그리기 ---------- */
  function flipOf(c) { return (MOVE_POSES[c.pose] && c.dir < 0) || (c.pose === "sleep" && c.dir > 0); }

  function render(c) {
    const st = { pose: c.pose, frame: c.frame, tick: c.tick, shut: c.shut, bare: true };
    const key = [c.pose, c.frame, c.pose === "sit" || c.pose === "sleep" || c.pose === "rest" ? c.tick >> 2 : c.tick, c.shut, flipOf(c), S.size].join("|");
    if (key !== c.drawKey) {
      c.drawKey = key;
      c.art.innerHTML = window.drawCat(c.cfg, st);
      const [x0, y0, x1, y1] = window.catFrame(c.cfg, st).bbox;         // 실제 그림이 있는 칸의 경계
      c.bbox = flipOf(c) ? [2 * G.footX - x1, y0, 2 * G.footX - x0, y1] : [x0, y0, x1, y1];
    }
    const k = cell(), left = c.x - G.footX * k, top = c.y - G.footY * k - (c.lift || 0);   // lift: 놀라서 제자리 점프
    c.el.style.width = S.size + "px";
    c.el.style.transform = "translate(" + Math.round(left) + "px," + Math.round(top) + "px)";
    c.art.style.transform = flipOf(c) ? "scaleX(-1)" : "";
    c.art.style.transformOrigin = G.footX * k + "px 50%";
    c.el.dataset.pose = c.pose;
    c.el.classList.toggle("love", c.love);
    c.el.classList.toggle("held", c.held);
    c.el.classList.toggle("pinned", c.pinned);
    c.box = [left + c.bbox[0] * k, top + c.bbox[1] * k, left + c.bbox[2] * k, top + c.bbox[3] * k];
    c.el.querySelector(".zzz").style.left = (flipOf(c) ? 2 * G.footX - 24 : 24) * k + "px";
  }

  /* ---------- 클릭·드래그·우클릭 ---------- */
  let drag = null;
  function grab(e, c) {
    if (e.button !== 0) return;
    e.preventDefault();
    drag = { c, sx: e.clientX, sy: e.clientY, dx: c.x - e.clientX, dy: c.y - e.clientY, moved: false };
  }
  window.addEventListener("pointermove", (e) => {
    if (!drag) return;
    if (!drag.moved && Math.hypot(e.clientX - drag.sx, e.clientY - drag.sy) > 4) {
      drag.moved = true; B.hold(drag.c); drag.c.short.hidden = true; drag.c.detail.hidden = true;
      post({ type: "drag", on: true });
    }
    if (drag.moved) { drag.c.x = e.clientX + drag.dx; drag.c.y = e.clientY + drag.dy; }
  });
  function release(click) {
    if (!drag) return;
    const { c, moved } = drag;
    drag = null;
    if (moved) { B.drop(c, c.x, c.y); post({ type: "drag", on: false }); save(); }
    else if (click) {
      showDetail(c);
      if (attention[c.key]) { delete attention[c.key]; post({ type: "ack", key: c.key }); }   // 일하는 중이어도 확인
    }
  }
  window.addEventListener("pointerup", () => release(true));
  window.addEventListener("pointercancel", () => release(false));               // 놓친 pointerup 때문에
  window.addEventListener("blur", () => release(false));                        // 화면 전체가 클릭을 막지 않게
  function menu(c) {
    if (W.native) post({ type: "menu", key: c.key, pinned: c.pinned, name: window.catLabel(c.cfg) });
    else { B.setPinned(c, !c.pinned); save(); }                          // 브라우저에서 시험할 때는 우클릭이 곧 고정
  }

  /* ---------- 앱으로 보내기 ---------- */
  function save() { savedAt = Date.now(); post({ type: "save", cats: B.snapshot() }); }

  function sendRects(now) {
    if (now - rectsAt < 66) return;
    rectsAt = now;
    const rects = [];
    B.cats.forEach((c) => { if (c.box) rects.push(c.box.map(Math.round)); });   // 말풍선은 클릭을 통과시킨다
    const s = JSON.stringify(rects);
    if (s !== lastRects) { lastRects = s; post({ type: "rects", rects }); }
  }

  function sendThumbs() {
    const items = {};
    (data ? data.cats : []).forEach((cfg) => {
      const f = window.catFrame(cfg, { pose: "sit", tick: 0, frame: 0, bare: true });
      const [x0, y0, x1, y1] = f.bbox;
      const px = [];
      for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) px.push(f.grid[y][x] === "." ? "" : window.catColor(f.variant, f.grid[y][x]));
      items[cfg.key] = { w: x1 - x0, h: y1 - y0, px };
    });
    post({ type: "thumbs", items });
  }

  /* ---------- 앱에서 받기 ---------- */
  window.desk = {
    settings(o) {
      const old = S.size;
      Object.assign(S, o, { behaviors: Object.assign({}, S.behaviors, o.behaviors || {}) });
      document.body.hidden = S.enabled === false;
      B.onAction = S.debugLog ? (c, s) => post({ type: "action", key: c.key, act: actLabel(s) }) : null;   // 행동 기록 (defaults debugLog)
      if (S.size !== old) B.cats.forEach((c) => { c.drawKey = ""; });
      const a = S.assign || {}, h = JSON.stringify([S.screen, Object.keys(a).sort().map((k) => [k, a[k]])]);   // 사전 순서는 매번 다를 수 있다
      if ((o.assign || o.screen) && h !== home) { home = h; apply(); }   // 이 화면에 사는 고양이가 바뀌었을 때만 다시 만든다
    },
    world(o) { W.update(o); if (o.windows) B.onWorld(Date.now()); },
    cancelDrag() { release(false); },
    pin(key, v) { const c = B.cats.find((x) => x.key === key); if (c) { B.setPinned(c, v); save(); } },
    unpinAll() { B.cats.forEach((c) => B.setPinned(c, false)); save(); },
    status(o) { window.CATTEAM = o; apply(); },                         // 앱이 모은 상태 (10초마다)
    attention(o) { attention = o || {}; },                              // 확인 안 한 사용자 차례 (바뀔 때만)
    greet(key, text) { greets[key] = { text, until: Date.now() + 30000 }; sayGreets(Date.now()); }   // 새로 온 고양이 인사
  };

  /* ---------- 루프 ---------- */
  let last = performance.now();
  function frame(t) {
    const dt = Math.min(0.1, (t - last) / 1000), now = Date.now();
    last = t;
    if (S.enabled !== false) {
      B.step(dt, now);
      const placed = [];
      B.cats.forEach((c) => {
        render(c);
        if (S.bubbleSec > 0 && now >= c.nextBubble) { showShort(c, now); c.nextBubble = now + S.bubbleSec * 1000; }
        if (!c.short.hidden && now > c.shortUntil) c.short.hidden = true;
        c.detail.hidden = !detailOn(c, now) || c.held || !c.short.hidden;   // 들고 있거나 인사 중엔 숨겼다가 다시
        if (c.held) c.short.hidden = true;
        const box = placeBang(c);
        placeBubble(c, c.detail, box, placed); placeBubble(c, c.short, box, placed);
      });
      sendRects(now);
      if (now - savedAt > 20000) save();
    }
    requestAnimationFrame(frame);
  }

  if (window.DESKTOP_SETTINGS) window.desk.settings(window.DESKTOP_SETTINGS);
  if (!W.native && /demo/.test(location.search)) {                       // 브라우저 시험용: 배경과 가짜 창 하나
    document.body.classList.add("demo");
    W.update({ menubar: 24, windows: [{ id: 1, x: W.w * .45, y: W.h * .35, w: W.w * .4, h: W.h * .45 }],
               icons: [{ x: 40, y: 80, w: 64, h: 64 }] });
    const win = W.windows[0], icon = W.icons[0];
    document.body.insertAdjacentHTML("afterbegin",
      '<div class="demo-win" style="left:' + win.x + "px;top:" + win.y + "px;width:" + win.w + "px;height:" + win.h + 'px">' +
      '<div class="demo-title"><i></i><i></i><i></i></div><div class="demo-body"><b></b><b></b><b></b><b></b></div></div>' +
      '<div class="demo-icon" style="left:' + icon.x + "px;top:" + icon.y + 'px"><span>작업 폴더</span></div><div class="demo-bar"></div>');
    const size = Number(new URLSearchParams(location.search).get("size"));   // ?demo&size=130: 고양이 크기 (48~200)
    if (size >= 48 && size <= 200) window.desk.settings({ size });
  }
  if (!W.native) { setInterval(poll, 15000); poll(); }                   // 브라우저에서는 status.js 를 읽는다
  requestAnimationFrame(frame);
  post({ type: "ready" });
})();
