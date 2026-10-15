/* 쉬는 자세: 몸을 동그랗게 말고 앞발에 머리를 묻은 채 눈을 감는다 */
window.CAT_POSES = window.CAT_POSES || {};

window.CAT_POSES.sleep = function (ctx) {
  const { R, M, g, GW, GH, feature } = ctx;
  const ell = (cx, cy, rx, ry, c) => {
    for (let y = 0; y < GH; y++) for (let x = 0; x < GW; x++)
      if (((x + .5 - cx) / rx) ** 2 + ((y + .5 - cy) / ry) ** 2 <= 1) g[y][x] = c;
  };
  ell(27, 15.5, 8.5, 5, "C");   // 동그랗게 만 몸
  if (feature === "stripes") [23, 27, 30, 33].forEach((x) => M(x, 11, 1, 3, "T")); else M(28, 11, 6, 3, "c");
  // 몸을 감싼 꼬리
  for (let y = 19; y < 21; y++) for (let x = 25; x < 36; x++)
    if (g[y][x] === "C") g[y][x] = (x >> 1) % 2 ? (feature === "stripes" ? "T" : "C") : "c";
  R(25, 20, 3, 1, "W");
  ell(19.5, 16.5, 5, 3.8, "C");   // 머리
  R(15, 10, 2, 1, "C"); R(15, 11, 3, 1, "C"); R(15, 12, 3, 1, "C"); R(16, 11, 1, 2, "P");
  R(22, 10, 2, 1, "C"); R(21, 11, 3, 1, "C"); R(21, 12, 3, 1, "C"); R(22, 11, 1, 2, "P");
  if (feature === "stripes") { R(18, 13, 1, 1, "T"); R(20, 13, 1, 1, "T"); }
  else if (feature === "mask") {
    R(15, 10, 2, 1, "T"); R(15, 11, 3, 1, "T"); R(15, 12, 3, 1, "T"); R(22, 10, 2, 1, "T"); R(21, 11, 3, 1, "T"); R(21, 12, 3, 1, "T");
    R(16, 14, 8, 4, "T");
  } else R(21, 13, 3, 1, "c");
  R(16, 16, 2, 1, ctx.eyeKey); R(21, 16, 2, 1, ctx.eyeKey); R(19, 17, 1, 1, "P");   // 감은 눈과 코
  const prop = window.CAT_PROPS[ctx.cat.prop];
  if (prop && prop.head) prop.head(ctx, "sleep");
  R(14, 19, 5, 2, "W"); R(18, 20, 6, 1, "W");   // 머리를 받친 앞발
  R(36, 17, 3, 4, "R"); R(36, 20, 3, 1, "r");   // 컵
};
