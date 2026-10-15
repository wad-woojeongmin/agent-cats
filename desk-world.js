/* 데스크톱 세계: 화면 크기, 메뉴 막대, Dock 을 뺀 바닥, 열린 창, 바탕화면 아이콘, 커서.
   좌표는 화면 왼쪽 위가 원점인 CSS px 이다. 앱(Swift)이 desk.world({...}) 로 넣어 주고,
   브라우저에서 그냥 열면 창 크기를 화면으로 삼는다. */
(function () {
  const W = window.deskWorld = {
    w: window.innerWidth, h: window.innerHeight,
    menubar: 0,                          // 메뉴 막대 높이 (브라우저에서는 0)
    floor: { top: 0, bottom: window.innerHeight, left: 0, right: window.innerWidth },   // Dock 을 뺀 영역
    windows: [],                         // 앞에서 뒤 순서 [{id, x, y, w, h}]
    icons: [],                           // [{x, y, w, h}]
    mouse: { x: -1, y: -1, moved: 0 },   // moved: 마지막으로 움직인 시각(ms)
    native: !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.cat)
  };

  W.update = function (o) {
    if (o.screen) { W.w = o.screen.w; W.h = o.screen.h; }
    if ("menubar" in o) W.menubar = o.menubar;
    if (o.floor) W.floor = o.floor;
    if (o.windows) W.windows = o.windows;
    if (o.icons) W.icons = o.icons;
    if (o.mouse) { W.mouse.x = o.mouse.x; W.mouse.y = o.mouse.y; W.mouse.moved = Date.now(); }
  };

  if (!W.native) {
    window.addEventListener("resize", () => {
      W.w = window.innerWidth; W.h = window.innerHeight;
      W.floor = { top: 0, bottom: W.h, left: 0, right: W.w };
    });
    window.addEventListener("mousemove", (e) => W.update({ mouse: { x: e.clientX, y: e.clientY } }));
  }

  /* 창 윗변 가운데 앞 창에 가리지 않은 구간. 고양이 키(catH)만큼 위쪽 띠가 가려지면 뺀다 */
  W.windowSegments = function (catH) {
    const out = [];
    W.windows.forEach((win, i) => {
      if (win.y < W.menubar + catH * 0.6 || win.y > W.floor.bottom) return;
      let segs = [[Math.max(win.x + 12, 30), Math.min(win.x + win.w - 12, W.w - 30)]];   // 다른 디스플레이로 걸친 부분은 뺀다
      for (let j = 0; j < i; j++) {
        const o = W.windows[j];
        if (o.y < win.y + 2 && o.y + o.h > win.y - catH) {
          const next = [];
          segs.forEach(([a, b]) => {
            if (o.x + o.w <= a || o.x >= b) { next.push([a, b]); return; }
            if (o.x > a) next.push([a, o.x]);
            if (o.x + o.w < b) next.push([o.x + o.w, b]);
          });
          segs = next;
        }
      }
      segs.forEach(([a, b]) => { if (b - a > 70) out.push({ kind: "win", id: win.id, y: win.y, a, b, win }); });
    });
    return out;
  };

  W.menubarPerch = function () {
    return W.menubar > 0 ? { kind: "menubar", y: W.menubar, a: 30, b: W.w - 30 } : null;
  };

  /* 횃대를 지금 세계 기준으로 다시 찾는다. 창이 사라졌거나 가려졌으면 null */
  W.refreshPerch = function (perch, x, catH) {
    if (!perch) return null;
    if (perch.kind === "menubar") return W.menubarPerch();
    const win = W.windows.find((w) => w.id === perch.id);
    if (!win) return null;
    const nx = win.x + perch.dx;
    const seg = W.windowSegments(catH).find((s) => s.id === perch.id && nx >= s.a - 4 && nx <= s.b + 4);
    return seg ? Object.assign({}, seg, { dx: perch.dx, x: nx }) : null;
  };

  /* 놓은 자리 근처의 횃대 */
  W.perchNear = function (x, y, catH) {
    const mb = W.menubarPerch();
    if (mb && y < W.menubar + 28) return mb;
    return W.windowSegments(catH).find((s) => Math.abs(y - s.y) < 26 && x >= s.a && x <= s.b) || null;
  };

  const rand = (a, b) => a + Math.random() * (b - a);
  W.rand = rand;
  W.clampFloor = function (x, y, catW, catH) {
    const f = W.floor;
    return [Math.min(Math.max(x, f.left + catW * 0.4), f.right - catW * 0.4),
            Math.min(Math.max(y, Math.max(f.top, W.menubar) + catH * 1.2), f.bottom - 4)];
  };
  /* 창 안쪽(작업 내용 위)은 되도록 피해서 고른다 */
  W.randomFloor = function (catW, catH) {
    let p;
    for (let i = 0; i < 8; i++) {
      p = W.clampFloor(rand(W.floor.left, W.floor.right), rand(W.floor.top + catH, W.floor.bottom), catW, catH);
      if (!W.windows.some((w) => p[0] > w.x - catW * .3 && p[0] < w.x + w.w + catW * .3 && p[1] > w.y && p[1] < w.y + w.h + catH * .2)) break;
    }
    return p;
  };
  /* 창 옆에서 기웃거릴 만한 창: 충분히 크고 가로로 화면 안에 걸친 창 */
  W.visibleWindows = function () {
    return W.windows.filter((w) => w.w > 160 && w.h > 120 && w.x < W.w && w.x + w.w > 0);
  };
})();
