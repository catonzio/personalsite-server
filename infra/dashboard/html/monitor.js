// Monitor tab: live stats from Glances, history from Prometheus.
// Both are reached through nginx (see ../nginx/default.conf) with relative
// URLs, so the page works both at /infra/ (Traefik) and on 127.0.0.1:8090.
const Monitor = (() => {
  const RANGES = { "1h": 3600, "6h": 21600, "24h": 86400, "7d": 604800, "30d": 2592000, "180d": 15552000 };
  const REFRESHES = [2, 5, 10, 30, 60];
  const HISTORY_EVERY = 60; // seconds; Prometheus stores one sample per minute
  const NET = 'device!~"lo|veth.*|br-.*|docker0"';
  const DISK = 'device=~"nvme[0-9]+n[0-9]+"';
  const PSYS = "node_rapl_psys_joules_total";
  const PKG = "node_rapl_package_joules_total";

  // ---- settings (URL > saved > defaults) ---------------------------------
  const store = {
    get(k) { try { return localStorage.getItem(`monitor.${k}`); } catch { return null; } },
    set(k, v) { try { localStorage.setItem(`monitor.${k}`, v); } catch { /* private mode */ } },
  };
  const params = new URLSearchParams(location.search);
  const defaults = typeof MONITOR_DEFAULTS === "object" ? MONITOR_DEFAULTS : { refresh: 5, range: "24h" };
  let refresh = Number(params.get("refresh") || store.get("refresh") || defaults.refresh);
  if (!(refresh >= 1)) refresh = 5;
  let range = params.get("range") || store.get("range") || defaults.range;
  if (!(range in RANGES)) range = "24h";

  let active = false;
  let built = false;
  let liveTimer = null;
  let histTimer = null;
  const $ = (id) => document.getElementById(id);

  // ---- formatting ---------------------------------------------------------
  const fmt = {
    pct: (v) => `${v.toFixed(0)}%`,
    num: (v) => v.toFixed(2),
    bytes: (v) => (v >= 2 ** 30 ? `${(v / 2 ** 30).toFixed(1)} GiB` : `${(v / 2 ** 20).toFixed(0)} MiB`),
    watt: (v) => `${v.toFixed(1)} W`,
    celsius: (v) => `${v.toFixed(0)} °C`,
    Bps: (v) => {
      if (v >= 2 ** 20) return `${(v / 2 ** 20).toFixed(1)} MiB/s`;
      if (v >= 2 ** 10) return `${(v / 2 ** 10).toFixed(0)} KiB/s`;
      return `${v.toFixed(0)} B/s`;
    },
    kwh: (v) => `${v.toFixed(3)} kWh`,
  };
  const two = (n) => String(n).padStart(2, "0");
  const clock = (d) => `${two(d.getHours())}:${two(d.getMinutes())}:${two(d.getSeconds())}`;
  const dayLabel = (d) => `${two(d.getDate())}/${two(d.getMonth() + 1)}`;
  const timeLabel = (t, span) => {
    const d = new Date(t * 1000);
    if (span <= 86400) return `${two(d.getHours())}:${two(d.getMinutes())}`;
    if (span <= 7 * 86400) return `${dayLabel(d)} ${two(d.getHours())}h`;
    return dayLabel(d);
  };

  // ---- data access --------------------------------------------------------
  async function getJSON(url) {
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), 8000);
    try {
      const r = await fetch(url, { credentials: "same-origin", signal: ctl.signal });
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      return await r.json();
    } finally {
      clearTimeout(timer);
    }
  }
  const glances = (p) => getJSON(`glances/api/4/${p}`);
  async function promQuery(query) {
    const j = await getJSON(`prom/api/v1/query?${new URLSearchParams({ query })}`);
    const r = j.data.result[0];
    return r ? Number(r.value[1]) : null;
  }
  async function promRange(query, start, end, step) {
    const j = await getJSON(`prom/api/v1/query_range?${new URLSearchParams({ query, start, end, step })}`);
    const r = j.data.result[0];
    return r ? r.values.map(([t, v]) => [Number(t), Number(v)]) : [];
  }

  // ---- DOM ----------------------------------------------------------------
  function el(tag, cls, text) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }
  function select(id, options, value) {
    const s = el("select");
    s.id = id;
    for (const [v, label] of options) {
      const o = el("option", null, label);
      o.value = String(v);
      s.append(o);
    }
    if (![...s.options].some((o) => o.value === String(value))) {
      const o = el("option", null, `${value}s`);
      o.value = String(value);
      s.append(o);
    }
    s.value = String(value);
    return s;
  }
  function section(title, noteId, noteText) {
    const s = el("section");
    const h = el("h2", null, title);
    const n = el("span", "note", noteText || "");
    if (noteId) n.id = noteId;
    h.append(n);
    s.append(h);
    return s;
  }

  const TILES = [
    ["cpu", "CPU"], ["load", "Load 1m"], ["ram", "RAM"], ["swap", "Swap"],
    ["temp", "CPU temp"], ["power", "Power"], ["energy", "Energy today"], ["uptime", "Uptime"],
  ];

  const CHARTS = [
    { id: "cpu", title: "CPU", unit: fmt.pct, max: 100,
      q: (w) => [["used", `100 * (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[${w}])))`]] },
    { id: "load", title: "Load", unit: fmt.num,
      q: () => [["1m", "node_load1"], ["5m", "node_load5"], ["15m", "node_load15"]] },
    { id: "mem", title: "Memory", unit: fmt.bytes,
      q: () => [["used", "node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes"],
                ["cache", "node_memory_Buffers_bytes + node_memory_Cached_bytes"],
                ["swap used", "node_memory_SwapTotal_bytes - node_memory_SwapFree_bytes"]] },
    { id: "power", title: "Power (RAPL estimate)", unit: fmt.watt,
      q: (w) => [["platform", `max(rate(${PSYS}[${w}]))`], ["CPU package", `max(rate(${PKG}[${w}]))`]] },
    { id: "temp", title: "Temperature", unit: fmt.celsius,
      q: () => [["CPU", 'max(node_hwmon_temp_celsius{chip=~".*coretemp.*"})'],
                ["NVMe", 'max(node_hwmon_temp_celsius{chip=~".*nvme.*"})']] },
    { id: "net", title: "Network", unit: fmt.Bps,
      q: (w) => [["in", `sum(rate(node_network_receive_bytes_total{${NET}}[${w}]))`],
                 ["out", `sum(rate(node_network_transmit_bytes_total{${NET}}[${w}]))`]] },
    { id: "disk", title: "Disk I/O", unit: fmt.Bps,
      q: (w) => [["read", `sum(rate(node_disk_read_bytes_total{${DISK}}[${w}]))`],
                 ["write", `sum(rate(node_disk_written_bytes_total{${DISK}}[${w}]))`]] },
  ];

  function build() {
    const root = $("tab-monitor");

    const bar = el("div", "mon-toolbar");
    const l1 = el("label", null, "Live refresh ");
    l1.append(select("m-refresh", REFRESHES.map((s) => [s, `${s}s`]), refresh));
    const l2 = el("label", null, "History ");
    l2.append(select("m-range", Object.keys(RANGES).map((r) => [r, r]), range));
    const status = el("span", "mon-status");
    status.id = "m-status";
    bar.append(l1, l2, status);

    const now = section("Now", "m-sys");
    const tiles = el("div", "tiles");
    for (const [id, label] of TILES) {
      const t = el("div", "tile");
      t.id = `t-${id}`;
      t.append(el("span", "tile-label", label), el("span", "tile-value", "–"), el("span", "tile-sub", ""));
      tiles.append(t);
    }
    now.append(tiles);

    const split = el("div", "mon-split");
    const procs = section("Processes", "m-pc");
    const table = el("table", "procs");
    table.innerHTML = "<thead><tr><th>PID</th><th>User</th><th class=r>CPU%</th><th class=r>MEM%</th>"
      + "<th class=r>RES</th><th>Command</th></tr></thead><tbody id=m-procs></tbody>";
    const scroll = el("div", "table-scroll");
    scroll.append(table);
    procs.append(scroll);
    const cores = section("CPU cores", "m-freq");
    const coreList = el("div", "cores");
    coreList.id = "m-cores";
    const sensors = el("dl", "sensors");
    sensors.id = "m-sensors";
    cores.append(coreList, sensors);
    split.append(procs, cores);

    const hist = section("History", null, "1 sample per minute, kept 180 days");
    const charts = el("div", "charts");
    for (const c of CHARTS) {
      const card = el("div", "chart-card");
      card.append(el("h3", null, c.title));
      const legend = el("div", "legend");
      legend.id = `l-${c.id}`;
      const box = el("div", "chart");
      box.id = `c-${c.id}`;
      card.append(legend, box);
      charts.append(card);
    }
    hist.append(charts);

    const energy = section("Energy per day", "m-energy-note");
    const ecard = el("div", "chart-card");
    const ebox = el("div", "chart");
    ebox.id = "c-energy";
    ecard.append(ebox);
    energy.append(ecard);

    root.append(bar, now, split, hist, energy);

    $("m-refresh").addEventListener("change", (e) => {
      refresh = Number(e.target.value);
      store.set("refresh", refresh);
      restart();
    });
    $("m-range").addEventListener("change", (e) => {
      range = e.target.value;
      store.set("range", range);
      updateHistory();
    });
    let resizeTimer = null;
    window.addEventListener("resize", () => {
      clearTimeout(resizeTimer);
      resizeTimer = setTimeout(redrawAll, 150);
    });
    built = true;
  }

  function setTile(id, value, sub, level) {
    const t = $(`t-${id}`);
    t.querySelector(".tile-value").textContent = value;
    t.querySelector(".tile-sub").textContent = sub || "";
    t.dataset.level = level || "";
  }
  // Status is never color-only: warn/crit also add a word to the sub line.
  function level(v, warn, crit) {
    if (v >= crit) return "crit";
    if (v >= warn) return "warn";
    return "";
  }
  const levelWord = { warn: "high", crit: "critical", "": "" };
  const withLevel = (sub, lv) => (lv ? `${levelWord[lv]} · ${sub}` : sub);

  const statusParts = { live: "", history: "" };
  function setStatus(key, text) {
    statusParts[key] = text;
    $("m-status").textContent = [statusParts.live, statusParts.history].filter(Boolean).join(" · ");
  }

  // ---- live (Glances) -----------------------------------------------------
  async function updateLive() {
    const names = ["quicklook", "load", "mem", "memswap", "sensors", "uptime", "processcount", "processlist/top/20"];
    const res = await Promise.allSettled(names.map(glances));
    const [ql, load, mem, swap, sensors, uptime, pc, procs] = res.map((r) => (r.status === "fulfilled" ? r.value : null));
    if (res.every((r) => r.status === "rejected")) {
      setStatus("live", `Glances unreachable (${res[0].reason.message})`);
      return;
    }
    setStatus("live", `Live ${clock(new Date())}`);

    if (ql) {
      const lv = level(ql.cpu, 70, 90);
      setTile("cpu", fmt.pct(ql.cpu), withLevel(`${(ql.cpu_hz_current / 1e9).toFixed(1)} GHz`, lv), lv);
      $("m-sys").textContent = ql.cpu_name || "";
      $("m-freq").textContent = `${ql.percpu.length} threads`;
      renderCores(ql.percpu);
    }
    if (load) {
      const lv = level(load.min1 / load.cpucore, 0.7, 1);
      setTile("load", load.min1.toFixed(2), withLevel(`${load.min5.toFixed(2)} · ${load.min15.toFixed(2)}`, lv), lv);
    }
    if (mem) {
      const lv = level(mem.percent, 80, 90);
      setTile("ram", fmt.pct(mem.percent), withLevel(`${fmt.bytes(mem.total - mem.available)} / ${fmt.bytes(mem.total)}`, lv), lv);
    }
    if (swap) {
      const lv = level(swap.percent, 60, 85);
      setTile("swap", fmt.pct(swap.percent), withLevel(`${fmt.bytes(swap.used)} / ${fmt.bytes(swap.total)}`, lv), lv);
    }
    if (sensors) {
      const pkg = sensors.find((s) => s.label === "Package id 0");
      if (pkg) {
        const lv = level(pkg.value, 75, 90);
        setTile("temp", fmt.celsius(pkg.value), withLevel("package", lv), lv);
      }
      renderSensors(sensors);
    }
    if (uptime) {
      // Glances sends e.g. "38 days, 8:24:51" or "8:24:51".
      const m = String(uptime).match(/(?:(\d+) days?, )?(\d+):(\d+)/);
      if (m) setTile("uptime", m[1] ? `${m[1]}d ${m[2]}h` : `${m[2]}h ${m[3]}m`, "");
    }
    if (pc) $("m-pc").textContent = `${pc.total} total · ${pc.running} running · ${pc.thread} threads`;
    if (procs) renderProcs(procs);
  }

  function renderCores(percpu) {
    const box = $("m-cores");
    box.textContent = "";
    for (const c of percpu) {
      const row = el("div", "core");
      const fill = el("span", "core-fill");
      fill.style.width = `${Math.min(100, c.total)}%`;
      const track = el("span", "core-track");
      track.append(fill);
      row.append(el("span", "core-name", `cpu${c.cpu_number}`), track, el("span", "core-val", fmt.pct(c.total)));
      box.append(row);
    }
  }

  function renderSensors(sensors) {
    const box = $("m-sensors");
    box.textContent = "";
    const add = (k, v) => box.append(el("dt", null, k), el("dd", null, v));
    const nvme = sensors.find((s) => s.label === "Composite");
    if (nvme) add("NVMe", fmt.celsius(nvme.value));
    for (const f of sensors.filter((s) => s.type === "fan_speed")) {
      add(`Fan ${f.label.replace(/\D+/g, "")}`, `${f.value} rpm`);
    }
    const bat = sensors.find((s) => s.type === "battery");
    if (bat) add("Battery", `${bat.value}%`);
  }

  function renderProcs(list) {
    const body = $("m-procs");
    body.textContent = "";
    for (const p of list) {
      const tr = el("tr");
      const cmd = (p.cmdline && p.cmdline.length ? p.cmdline.join(" ") : p.name) || "";
      const cmdCell = el("td", "cmd", cmd);
      cmdCell.title = cmd;
      tr.append(
        el("td", "r mono", String(p.pid)),
        el("td", "user", p.username || ""),
        el("td", "r mono", (p.cpu_percent || 0).toFixed(1)),
        el("td", "r mono", (p.memory_percent || 0).toFixed(1)),
        el("td", "r mono", p.memory_info ? fmt.bytes(p.memory_info.rss) : ""),
        cmdCell,
      );
      body.append(tr);
    }
  }

  // ---- history (Prometheus) -----------------------------------------------
  const chartData = {};

  async function updateHistory() {
    const end = Math.floor(Date.now() / 1000);
    const span = RANGES[range];
    const start = end - span;
    // About 300 points per chart, never finer than the scrape interval.
    const step = Math.max(60, Math.round(span / 300 / 60) * 60);
    const win = `${Math.max(120, step)}s`;
    try {
      await Promise.all([
        ...CHARTS.map(async (c) => {
          const series = await Promise.all(c.q(win).map(async ([name, q]) => ({
            name, pts: await promRange(q, start, end, step),
          })));
          chartData[c.id] = { series, start, end, step, span };
          drawLine(c);
        }),
        updateEnergy(),
      ]);
      setStatus("history", `History ${clock(new Date())}`);
    } catch (err) {
      setStatus("history", `Prometheus unreachable (${err.message})`);
    }
  }

  async function updateEnergy() {
    const now = new Date();
    const midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const sinceMidnight = Math.max(60, Math.floor((now - midnight) / 1000));
    const [watts, today] = await Promise.all([
      promQuery(`max(rate(${PSYS}[2m]))`),
      promQuery(`max(increase(${PSYS}[${sinceMidnight}s])) / 3600000`),
    ]);
    setTile("power", watts == null ? "–" : fmt.watt(watts), "RAPL estimate");
    setTile("energy", today == null ? "–" : fmt.kwh(today), "since midnight");

    // Each point at a local midnight holds the energy of the day before it.
    // (Days that include a DST change are off by up to one hour.)
    const endTs = Math.floor(midnight / 1000);
    const pts = await promRange(`max(increase(${PSYS}[1d])) / 3600000`, endTs - 29 * 86400, endTs, 86400);
    const days = pts.map(([t, v]) => ({ t: t - 86400, v, partial: false }));
    if (today != null) days.push({ t: endTs, v: today, partial: true });
    chartData.energy = days;
    const total = days.reduce((a, d) => a + d.v, 0);
    $("m-energy-note").textContent = `RAPL estimate (lower bound of wall energy) · ${fmt.kwh(total)} in ${days.length} days`;
    drawBars();
  }

  // ---- charts (plain SVG) -------------------------------------------------
  const SVG = "http://www.w3.org/2000/svg";
  function svgEl(tag, attrs) {
    const e = document.createElementNS(SVG, tag);
    for (const [k, v] of Object.entries(attrs || {})) e.setAttribute(k, v);
    return e;
  }
  function niceMax(v) {
    if (!(v > 0)) return 1;
    const p = 10 ** Math.floor(Math.log10(v));
    for (const m of [1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10]) if (m * p >= v) return m * p;
    return 10 * p;
  }
  const M = { l: 64, r: 12, t: 8, b: 22 };

  function frame(box, height) {
    box.textContent = "";
    const w = Math.max(240, box.clientWidth);
    const svg = svgEl("svg", { width: w, height, viewBox: `0 0 ${w} ${height}`, role: "img" });
    box.append(svg);
    const tip = el("div", "tip");
    tip.hidden = true;
    box.append(tip);
    return { svg, tip, w, h: height, pw: w - M.l - M.r, ph: height - M.t - M.b };
  }
  function yAxis(f, ymax, unit) {
    for (let i = 0; i <= 4; i++) {
      const v = (ymax * i) / 4;
      const y = M.t + f.ph - (f.ph * i) / 4;
      f.svg.append(svgEl("line", { x1: M.l, x2: M.l + f.pw, y1: y, y2: y, class: i ? "grid" : "axis" }));
      const t = svgEl("text", { x: M.l - 6, y: y + 4, "text-anchor": "end", class: "tick" });
      t.textContent = unit(v);
      f.svg.append(t);
    }
  }

  function drawLine(c) {
    const d = chartData[c.id];
    const box = $(`c-${c.id}`);
    if (!d || !box || box.offsetParent === null) return;
    const f = frame(box, 170);
    const all = d.series.flatMap((s) => s.pts.map((p) => p[1])).filter(Number.isFinite);
    const ymax = c.max || niceMax(Math.max(...all, 0) * 1.05);
    yAxis(f, ymax, c.unit);
    const x = (t) => M.l + ((t - d.start) / (d.end - d.start)) * f.pw;
    const y = (v) => M.t + f.ph - (Math.min(v, ymax) / ymax) * f.ph;

    for (let i = 0; i <= 4; i++) {
      const t = d.start + ((d.end - d.start) * i) / 4;
      const lbl = svgEl("text", { x: x(t), y: f.h - 6, "text-anchor": i === 0 ? "start" : i === 4 ? "end" : "middle", class: "tick" });
      lbl.textContent = timeLabel(t, d.span);
      f.svg.append(lbl);
    }

    if (!all.length) {
      const t = svgEl("text", { x: M.l + f.pw / 2, y: M.t + f.ph / 2, "text-anchor": "middle", class: "empty" });
      t.textContent = "No data yet";
      f.svg.append(t);
    }

    d.series.forEach((s, i) => {
      let path = "";
      let prev = null;
      for (const [t, v] of s.pts) {
        if (!Number.isFinite(v)) { prev = null; continue; }
        // Break the line over gaps (server off, scrape missing).
        path += `${prev === null || t - prev > 2.5 * d.step ? "M" : "L"}${x(t).toFixed(1)},${y(v).toFixed(1)}`;
        prev = t;
      }
      f.svg.append(svgEl("path", { d: path, class: `line s${i + 1}` }));
    });

    // Legend with the latest value per series (needed for 2+ series).
    const legend = $(`l-${c.id}`);
    legend.textContent = "";
    if (d.series.length > 1 || c.id === "cpu") {
      d.series.forEach((s, i) => {
        const last = s.pts.length ? s.pts[s.pts.length - 1][1] : null;
        const item = el("span", "legend-item");
        item.append(el("i", `sw s${i + 1}`), el("span", null, s.name), el("b", null, last == null ? "–" : c.unit(last)));
        legend.append(item);
      });
    }

    // Hover: crosshair, dots and a tooltip with every series at that time.
    const cross = svgEl("line", { y1: M.t, y2: M.t + f.ph, class: "cross", visibility: "hidden" });
    const dots = d.series.map((s, i) => svgEl("circle", { r: 4, class: `dot s${i + 1}`, visibility: "hidden" }));
    f.svg.append(cross, ...dots);
    const hit = svgEl("rect", { x: M.l, y: M.t, width: f.pw, height: f.ph, class: "hit" });
    f.svg.append(hit);
    const nearest = (pts, t) => {
      let lo = 0, hi = pts.length - 1;
      if (hi < 0) return null;
      while (hi - lo > 1) { const mid = (lo + hi) >> 1; if (pts[mid][0] < t) lo = mid; else hi = mid; }
      return Math.abs(pts[lo][0] - t) <= Math.abs(pts[hi][0] - t) ? pts[lo] : pts[hi];
    };
    hit.addEventListener("mousemove", (ev) => {
      const r = f.svg.getBoundingClientRect();
      const px = ev.clientX - r.left;
      const t = d.start + ((px - M.l) / f.pw) * (d.end - d.start);
      const rows = [];
      let tx = null;
      d.series.forEach((s, i) => {
        const p = nearest(s.pts, t);
        if (!p || Math.abs(p[0] - t) > 2.5 * d.step) { dots[i].setAttribute("visibility", "hidden"); return; }
        tx = p[0];
        dots[i].setAttribute("cx", x(p[0]));
        dots[i].setAttribute("cy", y(p[1]));
        dots[i].setAttribute("visibility", "visible");
        rows.push(`<div><i class="sw s${i + 1}"></i>${s.name} <b>${c.unit(p[1])}</b></div>`);
      });
      if (tx === null) { f.tip.hidden = true; cross.setAttribute("visibility", "hidden"); return; }
      cross.setAttribute("x1", x(tx));
      cross.setAttribute("x2", x(tx));
      cross.setAttribute("visibility", "visible");
      const dt = new Date(tx * 1000);
      f.tip.innerHTML = `<div class="tip-time">${dayLabel(dt)} ${two(dt.getHours())}:${two(dt.getMinutes())}</div>${rows.join("")}`;
      f.tip.hidden = false;
      const left = x(tx) + 12 + f.tip.offsetWidth > f.w ? x(tx) - 12 - f.tip.offsetWidth : x(tx) + 12;
      f.tip.style.left = `${left}px`;
      f.tip.style.top = `${M.t}px`;
    });
    hit.addEventListener("mouseleave", () => {
      f.tip.hidden = true;
      cross.setAttribute("visibility", "hidden");
      dots.forEach((dot) => dot.setAttribute("visibility", "hidden"));
    });
  }

  function drawBars() {
    const days = chartData.energy;
    const box = $("c-energy");
    if (!days || !box || box.offsetParent === null) return;
    const f = frame(box, 170);
    const ymax = niceMax(Math.max(...days.map((d) => d.v), 0) * 1.05);
    yAxis(f, ymax, (v) => v.toFixed(ymax < 0.1 ? 3 : 2));
    if (!days.length) return;
    const slot = f.pw / days.length;
    const bw = Math.max(2, slot - 2); // 2px gap between bars
    days.forEach((d, i) => {
      const h = (Math.max(0, d.v) / ymax) * f.ph;
      const x0 = M.l + i * slot + (slot - bw) / 2;
      const y0 = M.t + f.ph - h;
      const r = Math.min(4, bw / 2, h);
      // Rounded top, square base on the baseline.
      const path = `M${x0},${M.t + f.ph}V${y0 + r}Q${x0},${y0} ${x0 + r},${y0}H${x0 + bw - r}Q${x0 + bw},${y0} ${x0 + bw},${y0 + r}V${M.t + f.ph}Z`;
      const bar = svgEl("path", { d: path, class: `bar s1${d.partial ? " partial" : ""}` });
      f.svg.append(bar);
      const hit = svgEl("rect", { x: M.l + i * slot, y: M.t, width: slot, height: f.ph, class: "hit" });
      hit.addEventListener("mouseenter", () => {
        const label = d.partial ? "today so far" : dayLabel(new Date(d.t * 1000));
        f.tip.innerHTML = `<div class="tip-time">${label}</div><div><b>${fmt.kwh(d.v)}</b></div>`;
        f.tip.hidden = false;
        const cx = M.l + i * slot + slot / 2;
        const left = cx + 12 + f.tip.offsetWidth > f.w ? cx - 12 - f.tip.offsetWidth : cx + 12;
        f.tip.style.left = `${left}px`;
        f.tip.style.top = `${M.t}px`;
        bar.classList.add("hover");
      });
      hit.addEventListener("mouseleave", () => { f.tip.hidden = true; bar.classList.remove("hover"); });
      f.svg.append(hit);
      if (i % 5 === 0 || i === days.length - 1) {
        const t = svgEl("text", { x: M.l + i * slot + slot / 2, y: f.h - 6, "text-anchor": "middle", class: "tick" });
        t.textContent = d.partial ? "today" : dayLabel(new Date(d.t * 1000));
        f.svg.append(t);
      }
    });
  }

  function redrawAll() {
    if (!active) return;
    CHARTS.forEach(drawLine);
    drawBars();
  }

  // ---- scheduling ---------------------------------------------------------
  // Polling runs only while the tab is shown and the page is visible, so
  // Glances is not queried when nobody is looking.
  function stop() {
    clearInterval(liveTimer);
    clearInterval(histTimer);
    liveTimer = histTimer = null;
  }
  function restart() {
    stop();
    if (!active || document.hidden) return;
    updateLive();
    updateHistory();
    liveTimer = setInterval(updateLive, refresh * 1000);
    histTimer = setInterval(updateHistory, HISTORY_EVERY * 1000);
  }
  document.addEventListener("visibilitychange", restart);

  return {
    setActive(on) {
      active = on;
      if (on && !built) build();
      restart();
      if (on) redrawAll();
    },
  };
})();
