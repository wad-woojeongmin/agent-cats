/* 데스크톱에서 움직이는 자세. 오른쪽을 보는 옆모습이고, 왼쪽을 볼 때는 화면에서 뒤집는다.
   발끝은 20번 줄(앉은 자세와 같은 바닥), 몸 가운데는 28번 칸 언저리다.
   walk/run(4프레임), jump(0: 웅크림, 1: 공중), stretch, rest(쉬기), play(앞발로 톡톡), sitside(옆으로 앉기),
   alert(놀람: 0 웅크림, 1 공중, 2 섬. 머리 위에 "!", 뛰어오르는 높이는 화면에서 준다). */
window.CAT_POSES = window.CAT_POSES || {};

(function () {
  function head(ctx, hx, hy, open) {
    const { R } = ctx;
    R(hx, hy, 9, 7, "C"); R(hx, hy, 1, 1, "."); R(hx + 8, hy, 1, 1, ".");
    R(hx + 1, hy - 2, 1, 1, "C"); R(hx + 1, hy - 1, 2, 1, "C"); R(hx + 2, hy - 1, 1, 1, "P");   // 귀
    R(hx + 7, hy - 2, 1, 1, "C"); R(hx + 6, hy - 1, 2, 1, "C"); R(hx + 6, hy - 1, 1, 1, "P");
    ctx.headAt = [hx, hy];
  }

  function face(ctx, open) {
    const { R } = ctx, [hx, hy] = ctx.headAt, eye = ctx.eyeKey;
    R(hx + 6, hy + 4, 3, 2, ctx.feature === "mask" ? "T" : "W");                              // 주둥이
    R(hx + 8, hy + 4, 1, 1, "P");                                                             // 코
    if (ctx.wide) R(hx + 5, hy + 2, 2, 2, eye);                                               // 놀라서 크게 뜬 눈
    else if (open && !ctx.shut) R(hx + 6, hy + 2, 1, 2, eye); else R(hx + 5, hy + 3, 2, 1, eye);
  }

  function leg(ctx, x, top, len) {
    ctx.R(x, top, 2, len, "C");
    ctx.R(x, top + len - 1, 2, 1, ctx.feature === "mask" ? "T" : "W");
  }

  /* 무늬와 소품. parts: body [x,y,w,h], tail [x,y,w,h] */
  function finish(ctx, parts, open) {
    const { M, feature } = ctx, [hx, hy] = ctx.headAt, [bx, by, bw, bh] = parts.body;
    if (feature === "stripes") {
      for (let x = bx + 2; x < bx + bw - 3; x += 3) M(x, by, 1, Math.min(3, bh), "T");
      M(hx + 2, hy, 1, 2, "T"); M(hx + 4, hy, 1, 2, "T");
      if (parts.tail) { const [tx, ty, tw, th] = parts.tail; for (let y = ty; y < ty + th; y += 2) M(tx, y, tw, 1, "T"); }
    } else if (feature === "mask") {
      M(hx + 4, hy + 1, 5, 5, "T"); M(hx + 1, hy - 2, 2, 2, "T"); M(hx + 6, hy - 2, 2, 2, "T");
      if (parts.tail) M(...parts.tail, "T");
    } else {
      M(hx + 1, hy, 4, 2, "c"); M(bx + 3, by, 4, 2, "c");
    }
    face(ctx, open);
    const prop = window.CAT_PROPS[ctx.cat.prop];
    if (prop && prop.head) prop.head(ctx, "side");
  }

  function tailUp(ctx, x, y, f) {   // 몸 뒤에서 위로 솟은 꼬리, f 로 끝이 흔들린다
    const { R } = ctx, sway = f % 2;
    R(x, y + 3, 2, 3, "C"); R(x - 1 + sway, y, 2, 3, "C");
    return [x - 1, y, 3, 6];
  }

  window.CAT_POSES.walk = function (ctx) {
    const f = ctx.tick % 4, bob = f % 2;
    const tail = tailUp(ctx, 18, 8 + bob, f >> 1);
    ctx.R(20, 13 + bob, 14, 5, "C");
    const legs = f % 2 ? [[22, 3], [24, 2], [29, 2], [31, 3]] : [[21, 3], [25, 3], [28, 3], [32, 3]];
    if (f === 2) legs.reverse().forEach((l, i) => (l[0] = [21, 25, 28, 32][i]));
    legs.forEach(([x, len]) => leg(ctx, x, 18, len));
    head(ctx, 31, 8 + bob);
    finish(ctx, { body: [20, 13 + bob, 14, 5], tail }, true);
  };

  window.CAT_POSES.run = function (ctx) {
    const f = ctx.tick % 4, air = f % 2;
    const by = air ? 12 : 14;
    ctx.R(12, by + 1, 7, 2, "C");                                                             // 뒤로 뻗은 꼬리
    ctx.R(18, by, 17, 4, "C");
    if (air) { leg(ctx, 16, by + 3, 2); ctx.R(16, by + 3, 3, 1, "C"); leg(ctx, 35, by + 3, 2); ctx.R(34, by + 3, 3, 1, "C"); }
    else { [22, 24, 29, 31].forEach((x) => leg(ctx, x, 18, 3)); }
    head(ctx, 32, by - 4);
    finish(ctx, { body: [18, by, 17, 4], tail: [12, by + 1, 7, 2] }, true);
  };

  window.CAT_POSES.jump = function (ctx) {
    if ((ctx.st.frame || 0) === 0) {                                                          // 웅크림
      const tail = tailUp(ctx, 18, 10, ctx.tick);
      ctx.R(20, 15, 13, 4, "C");
      [21, 24, 28, 30].forEach((x) => leg(ctx, x, 19, 2));
      head(ctx, 31, 11);
      finish(ctx, { body: [20, 15, 13, 4], tail }, true);
    } else {                                                                                  // 공중
      ctx.R(13, 9, 6, 2, "C");
      ctx.R(19, 10, 15, 4, "C");
      ctx.R(33, 14, 6, 2, "C"); ctx.R(38, 14, 1, 2, "W");
      ctx.R(14, 13, 6, 2, "C"); ctx.R(14, 13, 1, 2, "W");
      head(ctx, 32, 5);
      finish(ctx, { body: [19, 10, 15, 4], tail: [13, 9, 6, 2] }, true);
    }
  };

  window.CAT_POSES.stretch = function (ctx) {
    const f = ctx.tick % 8 < 4 ? 0 : 1;
    ctx.R(17 + f, 6, 2, 6, "C");                                                              // 높이 든 꼬리
    ctx.R(19, 11, 8, 6, "C"); ctx.R(26, 14, 8, 4, "C");                                     // 엉덩이를 든 몸
    leg(ctx, 20, 17, 4); leg(ctx, 23, 17, 4);
    ctx.R(32, 19, 9, 2, "C"); ctx.R(39, 19, 2, 2, "W");                                       // 쭉 뻗은 앞다리
    head(ctx, 32, 12);
    finish(ctx, { body: [19, 11, 15, 6], tail: [17 + f, 6, 2, 6] }, f === 0);
  };

  window.CAT_POSES.rest = function (ctx) {
    const wag = (ctx.tick >> 2) % 2;
    ctx.R(15, 19, 6, 2, "C"); ctx.R(15, 17 + wag, 2, 2, "C");                                // 바닥에 늘어진 꼬리
    ctx.R(20, 15, 13, 6, "C");
    ctx.R(32, 19, 5, 2, "C"); ctx.R(35, 19, 2, 2, ctx.feature === "mask" ? "T" : "W");      // 앞발
    head(ctx, 30, 10);
    finish(ctx, { body: [20, 15, 13, 6], tail: [15, 17, 6, 4] }, true);
  };

  window.CAT_POSES.play = function (ctx) {
    const hit = (ctx.tick >> 1) % 2;
    const tail = tailUp(ctx, 18, 9, ctx.tick);
    ctx.R(20, 14, 13, 7, "C");
    leg(ctx, 22, 19, 2); leg(ctx, 30, 19, 2);
    head(ctx, 30, 8);
    if (hit) { ctx.R(33, 18, 6, 2, "C"); ctx.R(37, 18, 2, 2, "W"); }                          // 앞발을 뻗어 톡
    else { ctx.R(36, 15, 2, 4, "C"); ctx.R(36, 15, 2, 1, "W"); }                              // 앞발을 든다
    finish(ctx, { body: [20, 14, 13, 7], tail }, true);
  };

  window.CAT_POSES.alert = function (ctx) {
    const { R } = ctx, f = ctx.st.frame || 0, low = f === 0 ? 2 : 0;
    ctx.wide = true;
    window.drawBang(R, 41, 1, "!");                                                          // 느낌표
    const tail = tailUp(ctx, 18, 7 + low, 0);
    R(20, 13 + low, 14, 5, "C");
    if (f === 1) [21, 25, 28, 32].forEach((x) => leg(ctx, x, 18, 2));                        // 공중: 다리를 모은다
    else [21, 25, 28, 32].forEach((x) => leg(ctx, x, 18 + low, 3 - low));
    head(ctx, 31, 8 + low);
    const [hx, hy] = ctx.headAt, ear = ctx.feature === "mask" ? "T" : "C";
    R(hx + 1, hy - 3, 1, 1, ear); R(hx + 7, hy - 3, 1, 1, ear);                               // 쫑긋 선 귀
    finish(ctx, { body: [20, 13 + low, 14, 5], tail }, true);
  };
})();
