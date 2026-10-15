/* 소품. 직군에 어울리게 팀.json 의 "prop" 으로 고른다. 새 소품은 여기에 함수 하나를 더하면 된다.
   head(ctx, pose): 얼굴 위에 얹는 것 (안경, 헤드폰). pose 는 "sit" 또는 "sleep".
   monitor(ctx): 모니터 주변 (포스트잇)
   screen(ctx): 모니터 화면 내용 (일하는 중일 때) */
window.CAT_PROPS = {
  glasses: {
    head(ctx, pose) {
      const R = ctx.R;
      if (pose === "side") {    // 옆모습: 눈 둘레 테와 귀로 걸친 다리
        const [hx, hy] = ctx.headAt;
        R(hx + 5, hy + 1, 3, 1, "F"); R(hx + 5, hy + 4, 3, 1, "F"); R(hx + 5, hy + 2, 1, 2, "F"); R(hx + 7, hy + 2, 1, 2, "F"); R(hx + 1, hy + 2, 4, 1, "F");
      } else if (pose === "sleep") {   // 납작한 네모 안경
        R(15, 15, 4, 1, "F"); R(15, 17, 4, 1, "F"); R(15, 16, 1, 1, "F"); R(18, 16, 1, 1, "F");
        R(20, 15, 4, 1, "F"); R(20, 17, 4, 1, "F"); R(20, 16, 1, 1, "F"); R(23, 16, 1, 1, "F");
      } else {
        R(22, 5, 4, 1, "F"); R(22, 8, 4, 1, "F"); R(22, 6, 1, 2, "F"); R(25, 6, 1, 2, "F");
        R(30, 5, 4, 1, "F"); R(30, 8, 4, 1, "F"); R(30, 6, 1, 2, "F"); R(33, 6, 1, 2, "F"); R(26, 6, 4, 1, "F");
      }
    }
  },
  headphones: {
    head(ctx, pose) {
      const R = ctx.R;
      if (pose === "side") { const [hx, hy] = ctx.headAt; R(hx + 1, hy - 1, 6, 1, "U"); R(hx + 2, hy + 1, 3, 4, "U"); }
      else if (pose === "sleep") { R(15, 13, 9, 1, "U"); R(13, 15, 2, 4, "U"); R(24, 15, 2, 4, "U"); }
      else { R(22, 4, 12, 1, "U"); R(20, 6, 2, 4, "U"); R(34, 6, 2, 4, "U"); }
    }
  },
  postit: {
    monitor(ctx) { ctx.R(2, 5, 3, 3, "y"); ctx.R(6, 5, 3, 3, "p"); ctx.R(9, 6, 2, 2, "y"); }
  },
  chart: {
    screen(ctx) {   // 일하는 중에는 막대가 오르내린다
      const t = ctx.tick;
      [0, 1, 2, 3].forEach((i) => {
        const h = 1 + ((i * 2 + t) % 5);
        ctx.R(3 + i * 2, 15 - h, 1, h, i % 2 ? "t" : "g");
      });
    }
  }
};
