import { chromium } from "playwright";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

const SHOTS = join(dirname(fileURLToPath(import.meta.url)), "shots");

function rpc(method, params, id = 1) {
  const payload = JSON.stringify({ jsonrpc: "2.0", id, method, params: params || {} });
  execFileSync(
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
}

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
await page.goto("http://127.0.0.1:5173", { waitUntil: "networkidle" });
await page.click("[data-testid=duck-sim]");
await page.fill("[data-testid=pin-input]", "000000");
await page.click("[data-testid=pin-submit]");
await page.waitForSelector("[data-testid=nav-interact]");

async function interactAt(id, file) {
  await page.click("[data-testid=nav-interact]");
  await page.waitForTimeout(400);
  const loc = page.locator(`[data-testid="${id}"]`);
  if ((await loc.count()) > 0) await loc.first().scrollIntoViewIfNeeded();
  else await page.evaluate(() => window.scrollTo(0, 2000));
  await page.waitForTimeout(200);
  await page.screenshot({ path: join(SHOTS, file) });
}

rpc("skill.uninstall", { id: "all" });
rpc("skill.install", { id: "run" });
await interactAt("skill-run", "app-interact-run-on.png");
rpc("skill.uninstall", { id: "run" });
await interactAt("skill-run", "app-interact-run-off.png");

rpc("skill.install", { id: "roulade" });
await interactAt("skill-roulade", "app-interact-roulade-on.png");
rpc("skill.uninstall", { id: "roulade" });
await interactAt("skill-roulade", "app-interact-roulade-off.png");

rpc("skill.install", { id: "all" });
rpc("robot.do", { skill: "walk" });
await interactAt("skill-walk", "app-interact-walk.png");
rpc("robot.do", { skill: "roller" });
await page.waitForTimeout(1200);
await interactAt("skill-roller", "app-interact-roller.png");

await page.click("[data-testid=nav-models]");
await page.waitForTimeout(500);
await page.locator("[data-testid=skill-card-run]").scrollIntoViewIfNeeded();
await page.screenshot({ path: join(SHOTS, "app-models-full.png") });

rpc("skill.uninstall", { id: "all" });
await page.click("[data-testid=nav-models]");
await page.waitForTimeout(500);
await page.locator("[data-testid=skill-card-run]").scrollIntoViewIfNeeded();
await page.screenshot({ path: join(SHOTS, "app-models-empty.png") });

rpc("skill.install", { id: "all" });
await browser.close();
console.log("recapture done");
