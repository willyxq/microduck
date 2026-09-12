#!/usr/bin/env node
// Protocol probe for App-sim. Same calls the phone will make over BLE later.
// hello → system.authenticate → system.info

const url = process.env.MICRODUCK_SIM_URL || "ws://127.0.0.1:17432";
const pin = process.env.MICRODUCK_PIN || "000000";
const API_VERSION = 16;

function rpc(ws, id, method, params = {}) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`${method} timed out`)), 8000);
    const onMessage = (ev) => {
      const text = typeof ev.data === "string" ? ev.data : new TextDecoder().decode(ev.data);
      for (const line of text.split("\n")) {
        if (!line.trim()) continue;
        let msg;
        try {
          msg = JSON.parse(line);
        } catch {
          continue;
        }
        if (msg.id !== id) continue;
        clearTimeout(timer);
        ws.removeEventListener("message", onMessage);
        if (msg.error) reject(Object.assign(new Error(msg.error.message || "RPC error"), msg.error));
        else resolve(msg.result);
        return;
      }
    };
    ws.addEventListener("message", onMessage);
    ws.send(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
  });
}

const ws = new WebSocket(url);
await new Promise((resolve, reject) => {
  ws.addEventListener("open", resolve);
  ws.addEventListener("error", () => reject(new Error(`cannot connect ${url} — run scripts/duck-app-sim up`)));
});

const hello = await rpc(ws, 1, "hello", { api_version: API_VERSION });
const auth = await rpc(ws, 2, "system.authenticate", { pin });
if (!auth.authenticated) {
  throw new Error(`PIN rejected, attempts_remaining=${auth.attempts_remaining}`);
}
const info = await rpc(ws, 3, "system.info");
ws.close();

const ok = info?.serial === "SIM-0001" && info?.name === "duck-sim";
console.log(JSON.stringify({ url, hello, auth, info, ok }, null, 2));
if (!ok) {
  console.error("system.info must be name=duck-sim serial=SIM-0001");
  process.exit(1);
}
