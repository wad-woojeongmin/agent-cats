/* 앉은 자세. work: 모니터 앞에서 타닥타닥, sit: 데스크톱에서 얌전히 앉기.
   좌표는 44x25 격자(칸) 기준이다. 면만 채우고 테두리는 cats.js 가 자동으로 두른다. */
window.CAT_POSES = window.CAT_POSES || {};

function sitBody(ctx) {
  const { R, tick, feature, working, awake } = ctx;
  const wag = (working || awake) ? (tick >> 1) % 2 : 0;
  // 꼬리, 몸, 가슴
  R(35, 19, 2, 2, "C"); R(36, 15, 2, 5, "C"); R(36 + wag, 13, 2, 2, feature === "stripes" || feature === "mask" ? "T" : "W");
  R(22, 11, 13, 10, "C"); R(23, 20, 12, 1, "c"); R(24, 11, 8, 3, "W");
  // 머리와 귀
  R(21, 4, 14, 7, "C"); R(22, 10, 12, 1, "C");
  R(21, 1, 2, 1, "C"); R(21, 2, 3, 1, "C"); R(21, 3, 4, 1, "C"); R(22, 2, 1, 1, "P"); R(22, 3, 2, 1, "P");
  R(33, 1, 2, 1, "C"); R(32, 2, 3, 1, "C"); R(31, 3, 4, 1, "C"); R(33, 2, 1, 1, "P"); R(32, 3, 2, 1, "P");
  // 무늬
  if (feature === "stripes") {
    R(26, 4, 1, 2, "T"); R(29, 4, 1, 2, "T"); R(27, 4, 2, 1, "T"); R(21, 8, 2, 1, "T"); R(33, 8, 2, 1, "T");
    R(22, 13, 2, 1, "T"); R(22, 16, 2, 1, "T"); R(33, 13, 2, 1, "T"); R(33, 16, 2, 1, "T"); R(36, 17, 2, 1, "T");
  } else if (feature === "mask") {
    R(21, 1, 2, 1, "T"); R(21, 2, 3, 1, "T"); R(21, 3, 4, 1, "T"); R(33, 1, 2, 1, "T"); R(32, 2, 3, 1, "T"); R(31, 3, 4, 1, "T");
    R(22, 3, 1, 1, "P"); R(33, 3, 1, 1, "P"); R(23, 5, 10, 5, "T"); R(35, 19, 2, 2, "T"); R(36, 15, 2, 5, "T");
  } else {
    R(29, 4, 6, 3, "c");
  }
  // 눈과 코
  const eye = ctx.eyeKey, open = (working || awake) && !ctx.shut;
  if (open) { R(24, 6, 1, 2, eye); R(31, 6, 1, 2, eye); } else { R(24, 7, 1, 1, eye); R(31, 7, 1, 1, eye); }
  R(27, 8, 2, 1, feature === "mask" ? "P" : "E");
}

function sitMug(ctx) {
  const { R, tick, working } = ctx;
  R(30, 17, 4, 4, "R"); R(30, 20, 4, 1, "r"); R(34, 18, 1, 2, "r");
  if (working) { R(31 + (tick % 4 < 2 ? 0 : 1), 15, 1, 1, "Z"); R(32 - (tick % 4 < 2 ? 0 : 1), 13 + (tick % 2), 1, 1, "Z"); }
}

window.CAT_POSES.work = function (ctx) {
  sitBody(ctx);
  const prop = window.CAT_PROPS[ctx.cat.prop];
  if (prop && prop.head) prop.head(ctx, "sit");
  const down = ctx.tick % 2, lY = down ? 18 : 17, rY = down ? 17 : 18;   // 앞발이 번갈아 내려온다
  ctx.R(23, 13, 2, lY - 13, "C"); ctx.R(22, lY, 3, 2, "W");
  ctx.R(26, 13, 2, rY - 13, "C"); ctx.R(26, rY, 3, 2, "W");
  sitMug(ctx);
};

window.CAT_POSES.sit = function (ctx) {   // 데스크톱: 앞발을 모으고 얌전히 앉는다
  ctx.awake = true;   // 눈을 뜨고 꼬리를 흔든다
  sitBody(ctx);
  const prop = window.CAT_PROPS[ctx.cat.prop];
  if (prop && prop.head) prop.head(ctx, "sit");
  ctx.R(24, 18, 3, 2, "W"); ctx.R(28, 18, 3, 2, "W");
};
