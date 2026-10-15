/* 색과 품종. 새 품종은 VARIANTS 에 한 줄 더하면 된다.
   품종 하나 = 색 덮어쓰기 + 무늬 방식(feature) + 컵 색.
   feature: "patch"(머리 위 얼룩) | "stripes"(줄무늬) | "mask"(귀, 얼굴, 꼬리가 짙은 색) */
window.CAT_BASE = {
  C: "#ebe6dc", c: "#d2cbbd", W: "#fbfbf8", T: "#8a6a55", P: "#f2aeb0", E: "#1b1b1f", I: "#4aa3ff",
  O: "#1b1b1f",                                         // 테두리
  D: "#a8703f", d: "#c98d55", e: "#6f4524",             // 책상
  N: "#2f3139", V: "#454955", n: "#5a5f6c", k: "#b8bcc4", q: "#6b7280",   // 모니터, 키보드
  g: "#6ee7b7", t: "#67e8f9", b: "#93c5fd",             // 화면 위 글자와 그래프
  R: "#d93a3a", r: "#a82525",                           // 컵
  Z: "#c7ccd4",                                         // 김
  A: "#ffffff", a: "#9ca3af",                           // 종이와 글줄
  F: "#e0262b",                                         // 안경테
  U: "#374151",                                         // 헤드폰
  y: "#fde68a", p: "#fbcfe8"                            // 포스트잇
};

window.CAT_VARIANTS = {
  white:   { feature: "patch" },
  tabby:   { feature: "stripes", C: "#f0a860", c: "#d98a3d", W: "#fff1dc", T: "#c9722a", P: "#f7b9a8", R: "#4f7cff", r: "#3558c4" },
  gray:    { feature: "patch", C: "#9aa3b2", c: "#7c8596", W: "#d8dde6", R: "#2f9e6a", r: "#1f7a50" },
  tux:     { feature: "patch", C: "#4a4a55", c: "#35353f", W: "#f5efe6", E: "#f5efe6", R: "#2f9e6a", r: "#1f7a50" },
  siamese: { feature: "mask", C: "#efe3cf", c: "#d9c7a8", T: "#6b4a3a", P: "#e6a5a0", eye: "I" }
};

/* 상태 이름 하나로 색을 찾는다 (품종 값이 없으면 기본값) */
window.catColor = function (variant, ch) {
  const v = window.CAT_VARIANTS[variant] || window.CAT_VARIANTS.white;
  return v[ch] || window.CAT_BASE[ch];
};
