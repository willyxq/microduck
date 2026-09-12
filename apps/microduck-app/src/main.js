import { DuckRpc, SIM_DUCK } from "./rpc.js";

const root = document.getElementById("app");
const rpc = new DuckRpc(SIM_DUCK.url);
const lan = new DuckRpc(SIM_DUCK.lanUrl);

const COPY = {
  stop: "立即停止不走 BLE。真急停是物理按钮；松手停靠 teleop 死人手。",
  sit: "坐下 / 叫一声要局域网控制通道，不能经 BLE 下发。",
  apply: "模拟环境不下载模型。真鸭子上由它自己的 Wi-Fi 拉签名包。",
  rollback: "模拟环境不切换已安装版本。真鸭子上回退已安装版本，不经 BLE 传文件。",
  cameraKicker: "摄像头",
  cameraTitle: "现在没有直播",
  cameraSub: "画面要等局域网 / WebRTC。这里不是假视频。",
  sitLan: "已切换坐下 / 站起（局域网，不经 BLE）",
  quackLan: "叫了一声（局域网，不经 BLE）",
  stopLan: "已停止（局域网控制通道，仍不是物理急停）",
};

const state = {
  screen: "discover",
  tab: "home",
  pin: "",
  toast: "",
  busy: false,
  error: "",
  info: null,
  health: null,
  net: null,
  networks: [],
  update: null,
  installed: [],
  wifiDraft: null,
  rollbackDraft: false,
  lanReady: false,
  cameraLive: false,
};

function duckSvg(size = 128) {
  return `<svg class="duck" width="${size}" height="${size}" viewBox="0 0 128 128" aria-hidden="true">
    <ellipse cx="64" cy="86" rx="36" ry="28" fill="#f3b42c"/>
    <circle cx="72" cy="52" r="26" fill="#f3b42c"/>
    <circle cx="80" cy="46" r="5" fill="#1f2320"/>
    <path d="M96 54c10 2 16 8 16 12s-8 6-18 4" fill="#ef8b24"/>
    <ellipse cx="54" cy="108" rx="10" ry="4" fill="#ef8b24"/>
    <ellipse cx="78" cy="108" rx="10" ry="4" fill="#ef8b24"/>
  </svg>`;
}

function toast(msg) {
  state.toast = msg;
  render();
  setTimeout(() => {
    if (state.toast === msg) {
      state.toast = "";
      render();
    }
  }, 2800);
}

async function withBusy(fn) {
  state.busy = true;
  state.error = "";
  render();
  try {
    await fn();
  } catch (e) {
    state.error = e.message || String(e);
    toast(state.error);
  } finally {
    state.busy = false;
    render();
  }
}

async function connectAndAuth(pin) {
  await rpc.connect();
  await rpc.hello();
  const auth = await rpc.authenticate(pin);
  if (!auth.authenticated) {
    throw new Error(`PIN 不对，还剩 ${auth.attempts_remaining} 次`);
  }
  state.info = await rpc.call("system.info");
  await refreshStatus();
  await connectLan();
  state.screen = "app";
  state.tab = "home";
}

async function probeCamera() {
  try {
    const r = await fetch(`${SIM_DUCK.cameraStill}?t=${Date.now()}`, { cache: "no-store" });
    state.cameraLive = r.ok;
  } catch {
    state.cameraLive = false;
  }
}

async function connectLan() {
  try {
    await lan.connect();
    await lan.hello();
    state.lanReady = true;
    try {
      const cam = await lan.call("camera.info");
      if (cam?.live) state.cameraLive = true;
    } catch {
      /* HTTP still is the source of truth for the <img> */
    }
  } catch {
    state.lanReady = false;
  }
  if (!state.cameraLive) {
    await probeCamera();
  }
}

async function lanCall(method, params, okMessage, fallback) {
  if (!state.lanReady) {
    toast(fallback);
    return;
  }
  try {
    await lan.call(method, params);
    toast(okMessage);
  } catch (e) {
    toast(e.message || fallback);
  }
}

async function refreshStatus() {
  const jobs = [
    rpc.call("system.info").then((v) => { state.info = v; }).catch(() => {}),
    rpc.call("robot.health").then((v) => { state.health = v; }).catch((e) => {
      state.health = { healthy: false, reason: e.message };
    }),
    rpc.call("net.status").then((v) => { state.net = v; }).catch(() => {}),
    rpc.call("update.status").then((v) => { state.update = v; }).catch(() => {}),
    rpc.call("update.listInstalled", { component: "daemon" }).then((v) => {
      state.installed = v;
    }).catch(() => {}),
  ];
  await Promise.all(jobs);
}

async function scanWifi() {
  await withBusy(async () => {
    state.networks = (await rpc.call("net.scan")).networks || [];
  });
}

async function joinWifi(ssid, psk) {
  await withBusy(async () => {
    const result = await rpc.call("net.connect", { ssid, psk });
    if (result.outcome === "failed" && result.reason === "bad_key") {
      throw new Error("密码不对（BadKey），不是网络消失了");
    }
    if (result.outcome === "failed") {
      throw new Error(result.reason || "加入失败");
    }
    toast(`已加入 ${ssid}`);
    await refreshStatus();
  });
}

function topbar() {
  return `<div class="topbar"><span class="clock">9:41</span><span class="sub">模拟鸭子</span></div>`;
}

function tabbar() {
  if (state.screen !== "app") return "";
  const tabs = [
    ["home", "首页", homeIcon],
    ["interact", "互动", interactIcon],
    ["models", "模型", modelsIcon],
    ["settings", "设置", settingsIcon],
  ];
  return `<nav class="tabbar">${tabs
    .map(
      ([id, label, icon]) =>
        `<button class="tab ${state.tab === id ? "on" : ""}" data-testid="nav-${id === "settings" ? "settings" : id}" data-tab="${id}">${icon()}${label}</button>`,
    )
    .join("")}</nav>`;
}

function homeIcon() {
  return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M4 11.5 12 4l8 7.5V20a1 1 0 0 1-1 1h-5v-6H10v6H5a1 1 0 0 1-1-1z"/></svg>`;
}
function interactIcon() {
  return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="12" r="3"/><circle cx="12" cy="12" r="8"/></svg>`;
}
function modelsIcon() {
  return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="4" y="4" width="7" height="7" rx="1.5"/><rect x="13" y="4" width="7" height="7" rx="1.5"/><rect x="4" y="13" width="7" height="7" rx="1.5"/><rect x="13" y="13" width="7" height="7" rx="1.5"/></svg>`;
}
function settingsIcon() {
  return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="12" r="3"/><path d="M12 3v2M12 19v2M3 12h2M19 12h2M5.6 5.6l1.4 1.4M17 17l1.4 1.4M18.4 5.6 17 7M7 17l-1.4 1.4"/></svg>`;
}

function discoverView() {
  return `${topbar()}
    <div class="page">
      <p class="kicker">第一层 · 现场管理员</p>
      <h1>附近的鸭子</h1>
      <p class="sub">模拟模式不扫蓝牙。真鸭子到了，同一套调用改走 BLE。</p>
      <button class="go" data-testid="duck-sim" data-open="1">
        <div>
          <div class="title">duck-sim</div>
          <div class="kicker">SIM-0001 · ws://127.0.0.1:17432</div>
        </div>
        <span>›</span>
      </button>
      <p class="note">需要先在本机运行 <code>scripts/duck-app-sim up</code>。</p>
      ${state.error ? `<p class="error">${state.error}</p>` : ""}
    </div>`;
}

function pinView() {
  return `${topbar()}
    <div class="page">
      <p class="kicker">连接 duck-sim</p>
      <h1>输入 PIN</h1>
      <p class="sub">出厂 PIN 是 000000，和真鸭子一样写在仓库里。</p>
      <form id="pin-form">
        <div class="pin-row">
          <input data-testid="pin-input" name="pin" inputmode="numeric" maxlength="6" placeholder="000000" value="${state.pin}" />
        </div>
        <button class="cta" data-testid="pin-submit" ${state.busy ? "disabled" : ""}>认证</button>
      </form>
      ${state.error ? `<p class="error">${state.error}</p>` : ""}
    </div>`;
}

function batteryLabel() {
  const pct = state.health?.battery?.percent;
  return pct == null ? "—" : `${Math.round(pct)}%`;
}

function wifiLabel() {
  if (!state.net) return "未读到";
  if (state.net.ssid) return state.net.ssid;
  if (state.net.state === "disconnected") return "未联网";
  return state.net.state || "未知";
}

function healthTitle() {
  if (!state.health) return "正在读取";
  if (state.health.healthy) return "一切正常";
  return state.health.reason || "需要处理";
}

function homeView() {
  const name = state.info?.name || "duck-sim";
  return `${topbar()}
    <div class="page">
      <div class="row">
        <div>
          <h1>${name}</h1>
          <p class="sub">第一层 · 基础控制</p>
        </div>
        <span class="chip ok">现场连接</span>
      </div>
      <div class="card hero">
        <p class="kicker">现场管理员模式</p>
        <h1>${healthTitle()}</h1>
        ${duckSvg()}
        <div class="stats">
          <div class="stat"><b>${batteryLabel()}</b><span>电池</span></div>
          <div class="stat"><b>${wifiLabel()}</b><span>Wi-Fi</span></div>
        </div>
      </div>
      <button class="update" data-tab="models">
        <div>
          <div class="title">行走模型有新版本</div>
          <div class="kicker">daemon 0.10.0 → 0.11.0 · 模拟环境不下载</div>
        </div>
        <span class="ghost">查看</span>
      </button>
      <button class="go" data-tab="interact">
        <div>
          <div class="title">去互动</div>
          <div class="kicker">看画面、停止、坐下或叫一声</div>
        </div>
        <span>›</span>
      </button>
      <p class="sub">先可靠，再聪明 · 无厂商控制云</p>
    </div>`;
}

function interactView() {
  return `${topbar()}
    <div class="page">
      <div class="row">
        <h2>互动</h2>
        <span class="chip">基础控制</span>
      </div>
      <div class="card" data-testid="camera-placeholder">
        <p class="kicker">${COPY.cameraKicker}</p>
        ${
          state.cameraLive
            ? `<p class="title">跟随鸭子</p>
        <p class="sub">局域网画面，不是 BLE。电脑上的 MuJoCo 窗口是真实世界。</p>
        <img class="stage-live" data-testid="camera-feed" src="${SIM_DUCK.cameraStill}" alt="body camera" />`
            : `<p class="title">${COPY.cameraTitle}</p>
        <p class="sub">${COPY.cameraSub}</p>
        <div class="stage">${duckSvg(88)}</div>`
        }
      </div>
      <button class="danger" data-testid="stop" data-stop="1">立即停止</button>
      <p class="kicker" style="margin:18px 0 8px">基础互动</p>
      <div class="actions">
        <button class="action" data-testid="sit" data-act="sit">坐下 / 站起</button>
        <button class="action" data-testid="quack" data-act="quack">叫一声</button>
      </div>
      <p class="kicker" style="margin:20px 0 8px">手动驾驶 · 调试能力</p>
      ${
        state.lanReady
          ? `<div class="stick-wrap">
        <div class="stick-pad" data-testid="stick-drive">
          <div class="stick-knob" data-testid="stick-knob"></div>
        </div>
      </div>
      <p class="stick-hint">上前 · 左右转 · 松手即停 · 不经 BLE</p>`
          : `<div class="stick">等待局域网 teleop<br/>运动控制不经 BLE</div>`
      }
    </div>`;
}

function modelsView() {
  const installed = state.installed?.[0]?.version || "0.10.0";
  return `${topbar()}
    <div class="page">
      <div class="row">
        <h2>模型</h2>
        <span class="chip ok">${state.net?.ssid ? "鸭子已联网" : "未联网"}</span>
      </div>
      <p class="sub">第一层 · 能力底座</p>
      <div class="card">
        <div class="row">
          <div>
            <div class="title">行走 Walk</div>
            <div class="kicker">当前 v${installed}</div>
          </div>
          <span class="chip warn">有更新</span>
        </div>
        <p class="sub">v0.11.0 · 模拟环境只报告，不下载制品</p>
        <button class="cta" data-testid="apply-update" data-apply="1" ${state.busy ? "disabled" : ""}>更新</button>
        <button class="ghost wide" data-testid="rollback" data-rollback="1" ${state.busy ? "disabled" : ""}>回到上一版本</button>
      </div>
      ${state.rollbackDraft ? `<div class="card" data-testid="rollback-confirm-card">
        <div class="title">确认回退</div>
        <p class="sub">回退目标：已安装 v${installed}。不会恢复出厂。</p>
        <button class="cta" data-testid="rollback-confirm" data-rollback-confirm="1" ${state.busy ? "disabled" : ""}>确认回退</button>
        <button class="ghost wide" data-testid="rollback-cancel" data-rollback-cancel="1">取消</button>
      </div>` : ""}
      <div class="card">
        <div class="title">升级到第二层还差什么？</div>
        <p class="sub">5 个高级意图 · 成功率 90% · 安全验收。现在不要做意图墙。</p>
      </div>
    </div>`;
}

function settingsView() {
  const nets = state.networks
    .map(
      (n) => `<button class="wifi" data-ssid="${n.ssid}" data-security="${n.security || ""}" data-testid="wifi-${n.ssid}">
        <span>${n.ssid}</span><span class="kicker">${n.security === "open" ? "开放" : "WPA"} · ${n.signal}</span>
      </button>`,
    )
    .join("");
  const draft = state.wifiDraft
    ? `<div class="card">
        <div class="title">加入 ${state.wifiDraft.ssid}</div>
        <p class="sub">错密码必须显示是密码问题，不能说网络没了。</p>
        <div class="wifi-join">
          <input data-testid="wifi-password" name="psk" type="password" placeholder="密码" value="${state.wifiDraft.psk || ""}" />
          <button class="cta" data-wifi-join="1" data-testid="wifi-join" ${state.busy ? "disabled" : ""}>加入</button>
        </div>
      </div>`
    : "";
  return `${topbar()}
    <div class="page">
      <h2>设置</h2>
      <p class="sub">${state.info?.serial || "SIM-0001"} · ${state.info?.name || "duck-sim"}</p>
      <div class="card">
        <div class="title">连接</div>
        <p class="sub">传输：MICRODUCK_TRANSPORT=${SIM_DUCK.transport} · 真鸭子到了改 ble，页面和调用名不改</p>
        <p class="sub">健康：${state.health?.healthy ? "控制环在跑" : state.health?.reason || "未知"}</p>
      </div>
      <div class="row">
        <h2 style="font-size:22px">Wi-Fi</h2>
        <button class="ghost" data-scan="1" data-testid="wifi-scan">扫描</button>
      </div>
      ${nets || `<p class="sub">点扫描，FakeNet 会给出 Pollen 和 Cafe。</p>`}
      ${draft}
      ${state.error ? `<p class="error" data-testid="error">${state.error}</p>` : ""}
      <p class="note">Pollen 的密码是 <b>correct-key</b>。其他密码会返回 BadKey，App 必须说是密码问题。</p>
    </div>`;
}

const MAX_LINEAR = 0.3;
const MAX_ANGULAR = 1.5;
const drive = { vx: 0, vy: 0, vyaw: 0, sending: false, x: 0, y: 0, holding: false };

function sendTwist(forceZero = false) {
  if (!state.lanReady) return;
  const idle = !drive.vx && !drive.vy && !drive.vyaw;
  if (idle || forceZero) {
    if (drive.sending || forceZero) {
      lan.notify("robot.move", { vx: 0, vy: 0, vyaw: 0 });
      drive.sending = false;
    }
    return;
  }
  drive.sending = true;
  lan.notify("robot.move", { vx: drive.vx, vy: drive.vy, vyaw: drive.vyaw });
}

function haltDrive() {
  drive.vx = 0;
  drive.vy = 0;
  drive.vyaw = 0;
  drive.x = 0;
  drive.y = 0;
  drive.holding = false;
  sendTwist(true);
}

function wireStick() {
  const pad = document.querySelector("[data-testid='stick-drive']");
  const knob = document.querySelector("[data-testid='stick-knob']");
  if (!pad || !knob) return;
  const draw = (x, y) => {
    knob.style.transform = `translate(${x * 48}px, ${y * 48}px)`;
  };
  draw(drive.x, drive.y);
  const read = (ev) => {
    const box = pad.getBoundingClientRect();
    return {
      x: Math.max(-1, Math.min(1, (2 * (ev.clientX - box.left)) / box.width - 1)),
      y: Math.max(-1, Math.min(1, (2 * (ev.clientY - box.top)) / box.height - 1)),
    };
  };
  const apply = (x, y) => {
    drive.x = x;
    drive.y = y;
    drive.vx = -y * MAX_LINEAR;
    drive.vyaw = -x * MAX_ANGULAR;
    draw(x, y);
    sendTwist();
  };
  pad.onpointerdown = (ev) => {
    pad.setPointerCapture(ev.pointerId);
    drive.holding = true;
    const at = read(ev);
    apply(at.x, at.y);
  };
  pad.onpointermove = (ev) => {
    if (!pad.hasPointerCapture(ev.pointerId)) return;
    const at = read(ev);
    apply(at.x, at.y);
  };
  const release = () => apply(0, 0);
  pad.onpointerup = release;
  pad.onpointercancel = release;
}

setInterval(() => {
  if (drive.sending) sendTwist();
}, 100);

window.addEventListener("keydown", (ev) => {
  if (state.screen !== "app" || state.tab !== "interact") return;
  if (ev.target?.matches?.("input, textarea")) return;
  const key = ev.key.toLowerCase();
  if (!["w", "a", "s", "d", "arrowup", "arrowdown", "arrowleft", "arrowright"].includes(key)) return;
  ev.preventDefault();
  if (key === "w" || key === "arrowup") drive.vx = MAX_LINEAR;
  if (key === "s" || key === "arrowdown") drive.vx = -MAX_LINEAR;
  if (key === "a" || key === "arrowleft") drive.vyaw = MAX_ANGULAR;
  if (key === "d" || key === "arrowright") drive.vyaw = -MAX_ANGULAR;
  sendTwist();
});
window.addEventListener("keyup", (ev) => {
  const key = ev.key.toLowerCase();
  if (key === "w" || key === "arrowup" || key === "s" || key === "arrowdown") drive.vx = 0;
  if (key === "a" || key === "arrowleft" || key === "d" || key === "arrowright") drive.vyaw = 0;
  sendTwist();
});
window.addEventListener("blur", () => haltDrive());

let camPoll = 0;

function tickCamera() {
  const img = document.querySelector("[data-testid='camera-feed']");
  if (img) img.src = `${SIM_DUCK.cameraStill}?t=${Date.now()}`;
}

function render() {
  let body = "";
  if (state.screen === "discover") body = discoverView();
  else if (state.screen === "pin") body = pinView();
  else if (state.tab === "home") body = homeView();
  else if (state.tab === "interact") body = interactView();
  else if (state.tab === "models") body = modelsView();
  else body = settingsView();

  root.innerHTML = `<div class="phone">${body}${tabbar()}${
    state.toast ? `<div class="toast" data-testid="toast">${state.toast}</div>` : ""
  }</div>`;

  const live = state.screen === "app" && state.tab === "interact" && state.cameraLive;
  if (live && !camPoll) {
    tickCamera();
    camPoll = setInterval(tickCamera, 150);
  } else if (!live && camPoll) {
    clearInterval(camPoll);
    camPoll = 0;
  }
  wireStick();
}

root.addEventListener("click", async (ev) => {
  const tab = ev.target.closest("[data-tab]");
  if (tab) {
    if (tab.dataset.tab !== "interact") haltDrive();
    state.tab = tab.dataset.tab;
    render();
    if (state.tab === "interact") {
      await probeCamera();
      render();
    }
    return;
  }
  if (ev.target.closest("[data-open]")) {
    state.screen = "pin";
    state.error = "";
    render();
    return;
  }
  if (ev.target.closest("[data-scan]")) {
    await scanWifi();
    return;
  }
  if (ev.target.closest("[data-wifi-join]")) {
    const input = root.querySelector("[data-testid='wifi-password']");
    const psk = input?.value || "";
    if (state.wifiDraft) state.wifiDraft.psk = psk;
    await joinWifi(state.wifiDraft?.ssid, psk);
    return;
  }
  const wifi = ev.target.closest("[data-ssid]");
  if (wifi) {
    const ssid = wifi.dataset.ssid;
    const open = wifi.dataset.security === "open";
    if (open) {
      state.wifiDraft = null;
      await joinWifi(ssid, undefined);
      return;
    }
    state.wifiDraft = { ssid, psk: "" };
    state.error = "";
    render();
    return;
  }
  if (ev.target.closest("[data-stop]")) {
    haltDrive();
    await lanCall("robot.stop", {}, COPY.stopLan, COPY.stop);
    return;
  }
  if (ev.target.closest("[data-act]")) {
    const act = ev.target.closest("[data-act]").dataset.act;
    if (act === "quack") {
      await lanCall("robot.sound", {}, COPY.quackLan, COPY.sit);
    } else {
      await lanCall("robot.do", { skill: "sit_toggle" }, COPY.sitLan, COPY.sit);
    }
    return;
  }
  if (ev.target.closest("[data-rollback-cancel]")) {
    state.rollbackDraft = false;
    render();
    return;
  }
  if (ev.target.closest("[data-rollback-confirm]")) {
    state.rollbackDraft = false;
    await withBusy(async () => {
      try {
        await rpc.call("update.rollback", { component: "daemon" });
      } catch {
        throw new Error(COPY.rollback);
      }
    });
    return;
  }
  if (ev.target.closest("[data-rollback]")) {
    state.rollbackDraft = true;
    render();
    return;
  }
  if (ev.target.closest("[data-apply]")) {
    await withBusy(async () => {
      try {
        await rpc.call("update.apply", { component: "daemon" });
      } catch {
        throw new Error(COPY.apply);
      }
    });
  }
});

root.addEventListener("submit", async (ev) => {
  ev.preventDefault();
  const pin = new FormData(ev.target).get("pin") || "000000";
  state.pin = String(pin);
  await withBusy(() => connectAndAuth(state.pin));
});

render();
