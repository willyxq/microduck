const API_VERSION = 16;

export class DuckRpc {
  constructor(url) {
    this.url = url;
    this.ws = null;
    this.nextId = 1;
    this.pending = new Map();
    this.buffer = "";
  }

  async connect() {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) return;
    this.ws = new WebSocket(this.url);
    this.ws.binaryType = "arraybuffer";
    await new Promise((resolve, reject) => {
      this.ws.onopen = resolve;
      this.ws.onerror = () => reject(new Error(`无法连接 ${this.url}。先运行 scripts/duck-app-sim up`));
      this.ws.onclose = () => {
        for (const [, job] of this.pending) {
          job.reject(new Error("连接已断开"));
        }
        this.pending.clear();
      };
      this.ws.onmessage = (ev) => this.#onMessage(ev);
    });
  }

  close() {
    this.ws?.close();
    this.ws = null;
  }

  async hello() {
    return this.call("hello", { api_version: API_VERSION });
  }

  async authenticate(pin) {
    return this.call("system.authenticate", { pin });
  }

  async call(method, params = {}) {
    await this.connect();
    const id = this.nextId++;
    const line = JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n";
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`${method} 超时`));
      }, 20000);
      this.pending.set(id, { resolve, reject, timer });
      this.ws.send(line);
    });
  }

  #onMessage(ev) {
    const text = typeof ev.data === "string" ? ev.data : new TextDecoder().decode(ev.data);
    this.buffer += text;
    let nl;
    while ((nl = this.buffer.indexOf("\n")) >= 0) {
      const line = this.buffer.slice(0, nl).replace(/\r$/, "");
      this.buffer = this.buffer.slice(nl + 1);
      if (!line) continue;
      let msg;
      try {
        msg = JSON.parse(line);
      } catch {
        continue;
      }
      if (msg.id == null) continue;
      const job = this.pending.get(msg.id);
      if (!job) continue;
      this.pending.delete(msg.id);
      clearTimeout(job.timer);
      if (msg.error) {
        job.reject(Object.assign(new Error(msg.error.message || "RPC error"), msg.error));
      } else {
        job.resolve(msg.result);
      }
    }
    // A whole JSON object may arrive without a trailing newline (WS text frame).
    if (this.buffer && !this.buffer.includes("\n")) {
      try {
        const msg = JSON.parse(this.buffer);
        this.buffer = "";
        if (msg.id != null && this.pending.has(msg.id)) {
          const job = this.pending.get(msg.id);
          this.pending.delete(msg.id);
          clearTimeout(job.timer);
          if (msg.error) {
            job.reject(Object.assign(new Error(msg.error.message || "RPC error"), msg.error));
          } else {
            job.resolve(msg.result);
          }
        }
      } catch {
        // still buffering
      }
    }
  }
}

export const SIM_DUCK = {
  name: "duck-sim",
  serial: "SIM-0001",
  url: import.meta.env.VITE_MICRODUCK_SIM_URL || "ws://127.0.0.1:17432",
  transport: import.meta.env.VITE_MICRODUCK_TRANSPORT || "sim",
};
