/* 고양이 한 마리의 한 프레임을 그려 SVG 문자열로 돌려준다.
   순서: 책상 -> (모니터) -> 자세(pose-*.js) -> 테두리.
   포즈: work(일하는 중), sleep(쉬는 중), 그리고 pose-move.js 의 움직이는 자세.
   st.bare 가 참이면(데스크톱) 일할 때 말고는 책상과 모니터를 그리지 않는다. */
(function () {
  const GW = 44, GH = 25;
  window.CAT_GRID = { w: GW, h: GH, footX: 28, footY: 21 };                            // 발끝 칸. 좌우 뒤집기도 footX 기준
  const CODE = [
    [[3, 10, 3, "g"], [7, 10, 2, "t"], [3, 12, 2, "t"], [6, 12, 4, "g"], [3, 14, 3, "b"]],
    [[3, 10, 4, "g"], [8, 10, 2, "b"], [3, 12, 3, "t"], [7, 12, 3, "g"], [3, 14, 2, "g"], [6, 14, 3, "t"]],
    [[3, 10, 2, "t"], [6, 10, 4, "g"], [3, 12, 5, "g"], [3, 14, 4, "b"], [8, 14, 2, "t"]]
  ];

  function monitor(ctx) {
    const { R, tick, cat } = ctx;
    R(13, 19, 13, 1, "k"); R(13, 20, 13, 1, "q");                                      // 키보드
    R(1, 8, 12, 9, "N"); R(2, 9, 10, 7, "V"); R(12, 8, 1, 9, "n"); R(6, 17, 2, 2, "N"); R(4, 19, 6, 2, "N");
    const prop = window.CAT_PROPS[cat.prop] || {};
    if (ctx.working) {
      if (prop.screen) prop.screen(ctx);
      else CODE[tick % 3].forEach(([x, y, w, c]) => R(x, y, w, 1, c));
      if (tick % 2) R(11, 14, 1, 1, "W");
    } else {
      R(3, 10, 3, 1, "n");
    }
    if (prop.monitor) prop.monitor(ctx);
  }

  /* 그림 둘레 빈칸을 테두리(O)로 칠한 새 격자 */
  function outline(g) {
    const o = g.map((row) => row.slice());
    for (let y = 0; y < g.length; y++) for (let x = 0; x < g[y].length; x++) {
      if (g[y][x] !== ".") continue;
      if ([[1, 0], [-1, 0], [0, 1], [0, -1]].some(([dx, dy]) => (g[y + dy] || [])[x + dx] && g[y + dy][x + dx] !== ".")) o[y][x] = "O";
    }
    return o;
  }

  /* 격자를 가로로 이어 붙인 사각형으로 줄여서 SVG 로 만든다 */
  function svg(grid, variant) {
    let rects = "";
    grid.forEach((row, y) => {
      let x = 0;
      while (x < row.length) {
        const ch = row[x]; let n = 1;
        while (row[x + n] === ch) n++;
        if (ch !== ".") rects += '<rect x="' + x + '" y="' + y + '" width="' + n + '" height="1" fill="' + window.catColor(variant, ch) + '"/>';
        x += n;
      }
    });
    return '<svg viewBox="0 0 ' + grid[0].length + " " + grid.length + '" shape-rendering="crispEdges" xmlns="http://www.w3.org/2000/svg">' + rects + "</svg>";
  }

  function frame(cat, st) {
    const variant = window.CAT_VARIANTS[cat.variant] ? cat.variant : "white";
    const g = Array.from({ length: GH }, () => Array(GW).fill("."));
    const R = (x, y, w, h, c) => { for (let yy = y; yy < y + h; yy++) for (let xx = x; xx < x + w; xx++) g[yy][xx] = c; };
    const M = (x, y, w, h, c) => { for (let yy = y; yy < y + h; yy++) for (let xx = x; xx < x + w; xx++) if (g[yy][xx] === "C") g[yy][xx] = c; };
    const ctx = {
      cat, st, g, R, M, GW, GH, tick: st.tick, shut: st.shut,
      working: st.pose === "work",
      feature: window.CAT_VARIANTS[variant].feature, eyeKey: window.CAT_VARIANTS[variant].eye || "E"
    };
    const desk = !st.bare || st.pose === "work";                                       // 데스크톱(bare)에서는 일할 때만 책상을 편다
    if (desk) { R(0, 21, GW, 3, "D"); R(0, 21, GW, 1, "d"); R(0, 23, GW, 1, "e"); }      // 책상
    if (desk) monitor(ctx);
    (window.CAT_POSES[st.pose] || window.CAT_POSES.sleep)(ctx);
    const o = outline(g);
    let x0 = GW, y0 = GH, x1 = 0, y1 = 0;                                               // 실제 그림이 있는 칸의 경계
    o.forEach((row, y) => row.forEach((ch, x) => { if (ch !== ".") { x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x + 1); y1 = Math.max(y1, y + 1); } }));
    return { grid: o, variant, bbox: [x0, y0, x1, y1] };
  }

  window.catFrame = frame;

  /* 느낌표: (x, y) 가 막대 왼쪽 위. 막대 2x4, 한 칸 띄고 점 2x2. 둘 다 왼쪽 위 칸은 반짝임(h) */
  window.drawBang = function (R, x, y, key) {
    R(x, y, 2, 4, key); R(x, y + 5, 2, 2, key);
    R(x, y, 1, 1, "h"); R(x, y + 5, 1, 1, "h");
  };

  /* 한 프레임을 SVG 로 */
  window.drawCat = function (cat, st) {
    const { grid, variant } = frame(cat, st);
    return svg(grid, variant);
  };

  /* 느낌표만 따로 (테두리 포함 4x9 칸). 고양이와 같은 칸 크기로 그리면 된다 */
  window.BANG_GRID = { w: 4, h: 9 };
  window.bangSVG = function (key) {
    const g = Array.from({ length: 9 }, () => Array(4).fill("."));
    window.drawBang((x, y, w, h, c) => { for (let yy = y; yy < y + h; yy++) for (let xx = x; xx < x + w; xx++) g[yy][xx] = c; }, 1, 1, key);
    return svg(outline(g), "white");
  };
})();
