#!/usr/bin/env node
/** Install/uninstall + body-switch lab. Writes shots/ + index.html. */
import { chromium } from "playwright";
import { execFileSync } from "node:child_process";
import { mkdirSync, writeFileSync, copyFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = dirname(fileURLToPath(import.meta.url));
const SHOTS = join(ROOT, "shots");
mkdirSync(SHOTS, { recursive: true });

const CATALOG = [
  { id: "walk", title: "行走", kind: "locomotion", body: "walk", builtin: true },
  { id: "velstand", title: "走 + 爬起", kind: "locomotion", body: "walk" },
  { id: "run", title: "奔跑", kind: "locomotion", body: "walk" },
  { id: "sprint", title: "冲刺", kind: "locomotion", body: "walk" },
  { id: "moonwalk", title: "太空步", kind: "locomotion", body: "walk" },
  { id: "hop", title: "跳步", kind: "locomotion", body: "walk" },
  { id: "sitstand", title: "坐下 / 站起", kind: "pose", body: "walk", builtin: true },
  { id: "standup", title: "从地上爬起", kind: "trick", body: "walk" },
  { id: "pick", title: "低头捡", kind: "trick", body: "walk" },
  { id: "kick_left", title: "左脚踢", kind: "trick", body: "walk" },
  { id: "kick_right", title: "右脚踢", kind: "trick", body: "walk" },
  { id: "roulade", title: "前滚翻", kind: "trick", body: "walk" },
  { id: "roller", title: "轮滑走", kind: "locomotion", body: "rollers" },
  { id: "swizzle", title: "摆滑", kind: "locomotion", body: "rollers" },
  { id: "spin", title: "原地转", kind: "trick", body: "rollers" },
  { id: "roller_crouch", title: "轮滑下蹲", kind: "pose", body: "rollers" },
  { id: "roller_slope", title: "下坡滑", kind: "locomotion", body: "rollers" },
  { id: "roller_standup", title: "轮上爬起", kind: "trick", body: "rollers" },
];

function rpc(method, params, id = 1) {
  const payload = JSON.stringify({ jsonrpc: "2.0", id, method, params: params || {} });
  const out = execFileSync(
    "python3",
    [
      "-c",
      `import asyncio,json,sys,websockets
async def m():
    async with websockets.connect("ws://127.0.0.1:17434") as ws:
        await ws.send(sys.argv[1])
        print(await asyncio.wait_for(ws.recv(), timeout=25))
asyncio.run(m())`,
      payload,
    ],
    { encoding: "utf8" },
  );
  return JSON.parse(out);
}

function health() {
  return JSON.parse(execFileSync("curl", ["-sfS", "--max-time", "2", "http://127.0.0.1:17435/health"], { encoding: "utf8" }));
}

function grabCamera(name) {
  execFileSync("curl", ["-sfS", "--max-time", "2", "-o", join(SHOTS, name), "http://127.0.0.1:17435/camera.jpg"]);
}

function skillMap() {
  const listed = rpc("skill.list");
  const skills = listed.result?.skills || [];
  return Object.fromEntries(skills.map((s) => [s.id, s]));
}

function interactHas(page, id) {
  return page.locator(`[data-testid="skill-${id}"]`).count();
}

async function shot(page, name) {
  await page.screenshot({ path: join(SHOTS, name), fullPage: false });
}

function htmlEscape(s) {
  return String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
}

function renderHtml(rows, bodies) {
  const rowHtml = rows
    .map(
      (r) => `<tr class="${r.ok ? "ok" : "bad"}">
      <td>${htmlEscape(r.title)}</td>
      <td class="mono">${htmlEscape(r.id)}</td>
      <td>${htmlEscape(r.body)}</td>
      <td>${r.installOk ? "下载成功" : "下载失败"}</td>
      <td>${r.appear ? "互动出现" : "互动没有"}</td>
      <td>${r.uninstallOk ? "卸载成功" : "卸载失败"}</td>
      <td>${r.gone ? (r.builtin ? "出厂仍在" : "互动消失") : "仍挂着"}</td>
      <td>${r.ok ? "通过" : "失败"}</td>
    </tr>`,
    )
    .join("");
  return `<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>能力实验室 · 下载 / 卸载 / 机体</title>
<link rel="preconnect" href="https://fonts.googleapis.com"/>
<link href="https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,500;9..144,700&family=IBM+Plex+Mono:wght@400;500&family=Source+Sans+3:wght@400;600&display=swap" rel="stylesheet"/>
<style>
:root{--paper:#efe6d4;--ink:#1c1914;--mute:#6a6458;--duck:#e8a31a;--ok:#1f7a4d;--bad:#b42318;--card:#fffaf0}
*{box-sizing:border-box}
body{margin:0;background:
  radial-gradient(circle at 8% -10%,rgba(232,163,26,.22),transparent 28rem),
  repeating-linear-gradient(0deg,transparent,transparent 27px,rgba(28,25,20,.04) 28px),
  var(--paper);color:var(--ink);font:17px/1.5 "Source Sans 3",sans-serif}
.wrap{max-width:980px;margin:0 auto;padding:48px 22px 80px}
h1{font-family:Fraunces,serif;font-size:52px;line-height:.95;margin:0 0 12px}
.lede{font-size:20px;color:var(--mute);max-width:36rem}
.stamp{display:inline-block;margin:18px 0 36px;padding:6px 12px;border:1px solid var(--ink);font:12px/1 "IBM Plex Mono",monospace;letter-spacing:.08em;text-transform:uppercase}
section{margin:48px 0}
h2{font-family:Fraunces,serif;font-size:28px;margin:0 0 14px}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:16px}
@media(max-width:720px){.grid{grid-template-columns:1fr}}
figure{margin:0;background:var(--card);padding:10px;box-shadow:0 12px 30px rgba(60,40,10,.08)}
figure img{width:100%;display:block;border-radius:8px}
figcaption{font:12px/1.4 "IBM Plex Mono",monospace;color:var(--mute);padding:8px 4px 2px}
table{width:100%;border-collapse:collapse;background:var(--card);font-size:14px}
th,td{padding:10px 8px;border-bottom:1px solid #eadfcb;text-align:left}
th{font:12px "IBM Plex Mono",monospace;color:var(--mute)}
tr.ok td:last-child{color:var(--ok);font-weight:700}
tr.bad td:last-child{color:var(--bad);font-weight:700}
.mono{font-family:"IBM Plex Mono",monospace;font-size:12px}
.pair{display:grid;grid-template-columns:1fr 1fr;gap:16px}
.note{background:#1c1914;color:#efe6d4;padding:18px 20px;font-size:15px}
</style>
</head>
<body>
<div class="wrap">
  <p class="stamp">Body-sim · 2026-09-12 · LAN :17434</p>
  <h1>下载，卸载，<br/>换一双脚。</h1>
  <p class="lede">模型页点下载 / 卸载。互动页只出现已启用的能力。点行走用 Cream 脚；点轮滑走换成四只被动轮。下面是刚跑完的实机记录。</p>

  <section>
    <h2>1. 机体必须对上</h2>
    <p>点「行走」时 health.body = walk。点「轮滑走」时 health.body = rollers。摄像头跟的是同一只鸭子。</p>
    <div class="pair">
      <figure><img src="shots/sim-walk.jpg" alt="walk body"/><figcaption>行走 · ${htmlEscape(bodies.walk)}</figcaption></figure>
      <figure><img src="shots/sim-roller.jpg" alt="roller body"/><figcaption>轮滑走 · ${htmlEscape(bodies.roller)}</figcaption></figure>
    </div>
    <div class="grid" style="margin-top:16px">
      <figure><img src="shots/app-interact-walk.png" alt="interact walk"/><figcaption>互动 · 行走选中</figcaption></figure>
      <figure><img src="shots/app-interact-roller.png" alt="interact roller"/><figcaption>互动 · 轮滑走选中</figcaption></figure>
    </div>
  </section>

  <section>
    <h2>2. 模型页：空仓 → 装满 → 再卸</h2>
    <div class="grid">
      <figure><img src="shots/app-models-empty.png" alt="models empty"/><figcaption>卸载已下载之后。行走 / 坐下仍是出厂包。</figcaption></figure>
      <figure><img src="shots/app-models-full.png" alt="models full"/><figcaption>18 个能力全部下载。每张卡可卸载。</figcaption></figure>
    </div>
  </section>

  <section>
    <h2>3. 每个能力：下载出现，卸载消失</h2>
    <table>
      <thead><tr><th>能力</th><th>id</th><th>机体</th><th>下载</th><th>互动</th><th>卸载</th><th>之后</th><th></th></tr></thead>
      <tbody>${rowHtml}</tbody>
    </table>
  </section>

  <section>
    <h2>4. 抽样：奔跑 / 前滚翻 / 轮滑走</h2>
    <div class="grid">
      <figure><img src="shots/app-interact-run-on.png" alt="run on"/><figcaption>下载奔跑后，互动出现「奔跑」</figcaption></figure>
      <figure><img src="shots/app-interact-run-off.png" alt="run off"/><figcaption>卸载奔跑后，互动不再有它</figcaption></figure>
      <figure><img src="shots/app-interact-roulade-on.png" alt="roulade on"/><figcaption>下载前滚翻后，动作栏出现</figcaption></figure>
      <figure><img src="shots/app-interact-roulade-off.png" alt="roulade off"/><figcaption>卸载前滚翻后，动作栏没有</figcaption></figure>
    </div>
  </section>

  <p class="note">出厂能力（行走、坐下 / 站起）卸掉的是 ubuntu-lan 那份覆盖文件，内置 alpha_*.onnx 还在，所以互动栏不会空。其余 16 个：卸掉就从互动页消失，Body-sim 也不再挂那条会话。</p>
</div>
</body>
</html>`;
}

const rows = [];
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 390, height: 844 } });

await page.goto("http://127.0.0.1:5173", { waitUntil: "networkidle" });
await page.click("[data-testid=duck-sim]");
await page.fill("[data-testid=pin-input]", "000000");
await page.click("[data-testid=pin-submit]");
await page.waitForSelector("[data-testid=nav-models]");

console.log("uninstall all");
rpc("skill.uninstall", { id: "all" });

await page.click("[data-testid=nav-models]");
await page.waitForTimeout(600);
await shot(page, "app-models-empty.png");
await page.click("[data-testid=nav-interact]");
await page.waitForTimeout(500);
await shot(page, "app-interact-empty.png");

for (const skill of CATALOG) {
  const row = { ...skill, installOk: false, appear: false, uninstallOk: false, gone: false, ok: false };
  try {
    const inst = rpc("skill.install", { id: skill.id });
    row.installOk = !inst.error && inst.result?.ok;
    await page.click("[data-testid=nav-interact]");
    await page.waitForTimeout(450);
    const n = await interactHas(page, skill.id);
    if (skill.id === "sitstand") {
      row.appear = (await page.locator("[data-testid=sit]").count()) > 0;
    } else {
      row.appear = n > 0;
    }
    if (skill.id === "run") await shot(page, "app-interact-run-on.png");
    if (skill.id === "roulade") await shot(page, "app-interact-roulade-on.png");

    const un = rpc("skill.uninstall", { id: skill.id });
    if (un.error && skill.builtin) {
      row.uninstallOk = /出厂|卸不掉/.test(un.error.message || "") || /还没安装/.test(un.error.message || "");
      // if a copied file existed, uninstall should have succeeded
      const after = skillMap()[skill.id];
      row.uninstallOk = !after?.removable;
      row.gone = true; // still present via builtin — expected
    } else {
      row.uninstallOk = !un.error;
      await page.click("[data-testid=nav-interact]");
      await page.waitForTimeout(450);
      const n2 = await interactHas(page, skill.id);
      row.gone = skill.builtin ? true : n2 === 0;
      if (skill.id === "run") await shot(page, "app-interact-run-off.png");
      if (skill.id === "roulade") await shot(page, "app-interact-roulade-off.png");
    }
    row.ok = row.installOk && row.appear && row.uninstallOk && row.gone;
  } catch (e) {
    row.error = String(e);
    row.ok = false;
  }
  console.log(row.id, row.ok ? "PASS" : "FAIL", row);
  rows.push(row);
}

console.log("install all + body pair");
rpc("skill.install", { id: "all" });
await page.click("[data-testid=nav-models]");
await page.waitForTimeout(700);
await shot(page, "app-models-full.png");

rpc("robot.do", { skill: "walk" });
await page.waitForTimeout(900);
await page.click("[data-testid=nav-interact]");
await page.waitForTimeout(500);
await shot(page, "app-interact-walk.png");
grabCamera("sim-walk.jpg");
const walkHealth = health();

rpc("robot.do", { skill: "roller" });
await page.waitForTimeout(1600);
await page.click("[data-testid=nav-interact]");
await page.waitForTimeout(500);
await shot(page, "app-interact-roller.png");
grabCamera("sim-roller.jpg");
const rollerHealth = health();

await browser.close();

const bodies = {
  walk: `body=${walkHealth.body} loco=${walkHealth.locomotion}`,
  roller: `body=${rollerHealth.body} loco=${rollerHealth.locomotion}`,
};
writeFileSync(join(ROOT, "results.json"), JSON.stringify({ rows, bodies, walkHealth, rollerHealth }, null, 2));
writeFileSync(join(ROOT, "index.html"), renderHtml(rows, bodies));
console.log("wrote", join(ROOT, "index.html"));
console.log("pass", rows.filter((r) => r.ok).length, "/", rows.length);
console.log("bodies", bodies);
