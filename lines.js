/* 고양이 한 마리의 상태 문구를 정한다. 브라우저 화면(app.js)과 데스크톱 화면(desk-view.js)이 함께 쓴다.
   short: 데스크톱에서 주기적으로 뜨는 한 줄, main/sub/meta: 자세한 말풍선 3줄.
   catPoll: status.js(수집.py 가 쓴다)를 다시 읽고 onDone 을 부른다. */
(function () {
  const ago = (ms) => {
    const m = Math.max(0, Math.round(ms / 60000));
    if (m < 1) return "방금 전";
    if (m < 60) return m + "분 전";
    if (m < 1440) return Math.floor(m / 60) + "시간 전";
    return Math.floor(m / 1440) + "일 전";
  };
  const label = (cat) => [cat.name, cat.role].filter(Boolean).join(" ");
  const folderName = (s, cfg) => (s.folder || cfg.name || "").replace(/-/g, " ");

  window.catAgo = ago;
  window.catPoll = function (onDone) {
    const el = document.createElement("script");
    el.src = "status.js?t=" + Date.now();
    el.onload = el.onerror = () => { el.remove(); onDone(); };
    document.head.appendChild(el);
  };
  window.catLabel = label;

  window.catLine = function (cfg, s, dots) {
    dots = dots || "";
    if (!s || s.state === "missing") {                          // 맡은 세션이 아직 없다
      return { state: "missing", pose: "sleep", short: "아직 일을 시작 안 했어요",
               main: "아직 일을 시작 안 했어요", sub: "찾을 말이 들어간 폴더나 세션을 열면 여기 나타나요.", meta: label(cfg) };
    }
    if (s.state === "working") {
      const title = cfg.task || folderName(s, cfg) + " 작업중";
      return { state: "working", pose: "work", short: s.doing || title,
               main: title + dots, sub: s.step || s.doing || "",
               meta: (s.doing && s.step ? "지금 " + s.doing + " · " : "") + "마지막 움직임 " + ago(Date.now() - s.last) };
    }
    return { state: "idle", pose: "sleep", short: "잠깐 쉬는 중",
             main: "잠깐 쉬는 중", sub: s.step ? "마지막 보고: " + s.step : "",
             meta: folderName(s, cfg) + " · 마지막 움직임 " + ago(Date.now() - s.last) };
  };
})();
