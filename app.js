/* 화면 로직. status.js(수집.py 가 쓴다)를 15초마다 다시 읽어 말풍선과 고양이를 갱신한다. */
(function () {
  const team = document.getElementById("team");
  const titleEl = document.getElementById("title");
  const updatedEl = document.getElementById("updated");
  const staleEl = document.getElementById("stale");
  let cats = [], signature = "";

  const two = (n) => String(n).padStart(2, "0");
  const stamp = (ms) => {
    const d = new Date(ms);
    return d.getFullYear() + "-" + two(d.getMonth() + 1) + "-" + two(d.getDate()) + " " + two(d.getHours()) + ":" + two(d.getMinutes()) + ":" + two(d.getSeconds());
  };
  const label = window.catLabel;

  function build(config) {
    team.innerHTML = "";
    team.style.setProperty("--cols", config.columns || 3);
    cats = config.cats.filter((cfg) => !cfg.hidden).map((cfg) => {
      const el = document.createElement("article");
      el.className = "cat";
      el.dataset.state = "idle";
      el.innerHTML =
        '<div class="figure"><div class="art" style="width:' + (config.catWidth || 166) + 'px" role="img" aria-label="' + label(cfg) + '"></div>' +
        '<span class="name">' + label(cfg) + "</span></div>" +
        '<div class="bubble" aria-live="polite"><b class="b-main"></b><span class="b-sub"></span><small class="b-meta"></small></div>';
      team.appendChild(el);
      return { cfg, el, art: el.querySelector(".art"), main: el.querySelector(".b-main"),
               sub: el.querySelector(".b-sub"), meta: el.querySelector(".b-meta"),
               st: { tick: 0, shut: false, pose: "sleep", dots: 0 } };
    });
  }

  /* 고양이 한 마리의 말풍선과 자세를 정한다 */
  function say(c, data) {
    const { cfg, st } = c;
    const s = (data.status || {})[cfg.key];
    const line = window.catLine(cfg, s, ".".repeat(2 + (st.dots++ % 2)));
    st.pose = line.pose;
    c.main.textContent = line.main; c.sub.textContent = line.sub; c.meta.textContent = line.meta;
    c.el.dataset.state = line.state === "missing" ? "idle" : line.state;
    draw(c);
  }

  function draw(c) {
    c.art.innerHTML = window.drawCat(c.cfg, c.st) +
      (c.st.pose === "sleep" ? '<span class="zzz" aria-hidden="true"><i>z</i><i>z</i><i>Z</i></span>' : "");
  }

  function apply() {
    const data = window.CATTEAM;
    if (!data) return;
    const sig = JSON.stringify([data.cats, data.columns, data.catWidth]);
    if (sig !== signature) { signature = sig; build(data); }
    titleEl.textContent = data.title || "고양이 팀";
    updatedEl.textContent = "상태 갱신 " + stamp(data.updated);
    staleEl.hidden = Date.now() - data.updated < (data.staleSec || 60) * 1000;
    cats.forEach((c) => say(c, data));
  }

  const poll = () => window.catPoll(apply);

  setInterval(() => { cats.forEach((c) => { c.st.tick++; if (c.st.pose !== "sleep") draw(c); }); }, 260);      // 타닥타닥, 꼬리
  setInterval(() => { cats.forEach((c) => { c.st.shut = true; draw(c); setTimeout(() => { c.st.shut = false; draw(c); }, 140); }); }, 3600);   // 눈 깜빡
  setInterval(() => { const d = window.CATTEAM; if (d) cats.forEach((c) => { if (c.st.pose !== "sleep") say(c, d); }); }, 1500);    // 점 애니메이션
  setInterval(poll, 15000);
  poll();
})();
