import http from "node:http";
import { randomUUID } from "node:crypto";

export interface BridgeCommand {
  id: string;
  method: string;
  params: Record<string, unknown>;
  createdAt: number;
}

interface PendingWaiter {
  resolve: (v: unknown) => void;
  reject: (e: Error) => void;
  timer: NodeJS.Timeout;
}

interface PollWaiter {
  res: http.ServerResponse;
  timer: NodeJS.Timeout;
}

/**
 * HTTP bridge between MCP tools and the Roblox Studio plugin.
 *
 * Plugin flow (Luau, HttpService):
 *   GET  /health          -> { ok, service, version, queueLength }
 *   GET  /poll?timeoutMs= -> long-poll, returns { command } or { command: null }
 *   POST /result          -> { id, ok, output, error }
 *
 * Debug flow (curl):
 *   POST /command { method, params, timeoutMs } -> waits for plugin, returns result
 */
export class Bridge {
  private server: http.Server | null = null;
  port: number;
  private queue: BridgeCommand[] = [];
  private pending = new Map<string, PendingWaiter>();
  private pollWaiters: PollWaiter[] = [];
  private lastPluginSeen = 0;
  private apiKey: string;
  readonly version = "0.1.0";

  constructor(port = Number(process.env.ROBLOX_BRIDGE_PORT ?? 8090), apiKey = process.env.ROBLOX_MCP_API_KEY ?? "") {
    this.port = port;
    this.apiKey = apiKey;
  }

  get pluginConnected(): boolean {
    return Date.now() - this.lastPluginSeen < 60_000;
  }

  get lastSeen(): number {
    return this.lastPluginSeen;
  }

  private checkAuth(req: http.IncomingMessage): boolean {
    if (!this.apiKey) return true;
    const url = new URL(req.url ?? "/", "http://localhost");
    const q = url.searchParams.get("apiKey") ?? url.searchParams.get("api_key");
    const h = req.headers["x-api-key"];
    return q === this.apiKey || h === this.apiKey;
  }

  private readBody(req: http.IncomingMessage): Promise<unknown> {
    return new Promise((resolve, reject) => {
      let data = "";
      req.on("data", (c) => {
        data += c;
        if (data.length > 4_000_000) reject(new Error("Body too large"));
      });
      req.on("end", () => {
        if (!data) return resolve({});
        try {
          resolve(JSON.parse(data));
        } catch (e) {
          reject(new Error("Invalid JSON body"));
        }
      });
      req.on("error", reject);
    });
  }

  private json(res: http.ServerResponse, status: number, body: unknown) {
    const payload = JSON.stringify(body);
    res.writeHead(status, {
      "Content-Type": "application/json",
      "Content-Length": Buffer.byteLength(payload),
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "*",
      "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
    });
    res.end(payload);
  }

  /** Enqueue a command for the Studio plugin and wait for its result. */
  execute(method: string, params: Record<string, unknown> = {}, timeoutMs = Number(process.env.ROBLOX_TIMEOUT_MS ?? 30000)): Promise<unknown> {
    const id = randomUUID();
    const cmd: BridgeCommand = { id, method, params, createdAt: Date.now() };
    this.queue.push(cmd);
    this.flushPollWaiters();

    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        // remove from queue if still waiting
        this.queue = this.queue.filter((c) => c.id !== id);
        reject(new Error(`Plugin timeout after ${timeoutMs}ms (method=${method}). Is Roblox Studio open with the MCPBridge plugin enabled and connected?`));
      }, timeoutMs);
      this.pending.set(id, { resolve, reject, timer });
    });
  }

  private flushPollWaiters() {
    while (this.pollWaiters.length > 0 && this.queue.length > 0) {
      const w = this.pollWaiters.shift()!;
      clearTimeout(w.timer);
      const cmd = this.queue.shift()!;
      this.json(w.res, 200, { command: cmd });
    }
  }

  private completeResult(id: string, ok: boolean, output: unknown, error?: string) {
    const p = this.pending.get(id);
    if (!p) return false;
    clearTimeout(p.timer);
    this.pending.delete(id);
    if (ok) p.resolve(output);
    else p.reject(new Error(typeof error === "string" && error ? error : "Plugin reported failure"));
    return true;
  }

  async listen(): Promise<number> {
    // Try ports port..port+9 (default 8090..8099, also probe 8081..8090 compat)
    const candidates: number[] = [];
    for (let i = 0; i < 10; i++) candidates.push(this.port + i);
    if (!candidates.includes(8081)) candidates.push(8081);

    let lastErr: unknown = null;
    for (const p of candidates) {
      try {
        await this.listenOn(p);
        this.port = p;
        return p;
      } catch (e) {
        lastErr = e;
      }
    }
    throw lastErr instanceof Error ? lastErr : new Error("Could not bind bridge port");
  }

  private listenOn(port: number): Promise<void> {
    return new Promise((resolve, reject) => {
      const server = http.createServer(async (req, res) => {
        try {
          if (req.method === "OPTIONS") {
            res.writeHead(204, {
              "Access-Control-Allow-Origin": "*",
              "Access-Control-Allow-Headers": "*",
              "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
            });
            res.end();
            return;
          }
          const url = new URL(req.url ?? "/", "http://localhost");
          const path = url.pathname;

          if (path === "/health" && req.method === "GET") {
            this.json(res, 200, {
              ok: true,
              service: "roblox-mcp-bridge",
              version: this.version,
              queueLength: this.queue.length,
              pluginConnected: this.pluginConnected,
              lastPluginSeen: this.lastPluginSeen,
              port,
            });
            return;
          }

          if (path === "/status" && req.method === "GET") {
            this.json(res, 200, {
              pluginConnected: this.pluginConnected,
              lastPluginSeen: this.lastPluginSeen,
              queueLength: this.queue.length,
              pendingCount: this.pending.size,
              port,
            });
            return;
          }

          if (!this.checkAuth(req)) {
            this.json(res, 401, { ok: false, error: "Invalid API key. Set _G.MCP_SetApiKey(key) in Studio command bar." });
            return;
          }

          if (path === "/poll" && req.method === "GET") {
            this.lastPluginSeen = Date.now();
            if (this.queue.length > 0) {
              const cmd = this.queue.shift()!;
              this.json(res, 200, { command: cmd });
              return;
            }
            const timeoutMs = Math.min(Math.max(Number(url.searchParams.get("timeoutMs") ?? 25000) || 25000, 1000), 30000);
            const timer = setTimeout(() => {
              this.pollWaiters = this.pollWaiters.filter((w) => w.res !== res);
              try {
                this.json(res, 200, { command: null });
              } catch { /* client gone */ }
            }, timeoutMs);
            this.pollWaiters.push({ res, timer });
            req.on("close", () => {
              clearTimeout(timer);
              this.pollWaiters = this.pollWaiters.filter((w) => w.res !== res);
            });
            return;
          }

          if (path === "/result" && req.method === "POST") {
            this.lastPluginSeen = Date.now();
            const body = (await this.readBody(req)) as { id?: string; ok?: boolean; output?: unknown; error?: string };
            if (!body.id) {
              this.json(res, 400, { ok: false, error: "Missing id" });
              return;
            }
            const found = this.completeResult(body.id, body.ok !== false, body.output, body.error);
            this.json(res, 200, { ok: true, delivered: found });
            return;
          }

          if (path === "/command" && req.method === "POST") {
            const body = (await this.readBody(req)) as { method?: string; params?: Record<string, unknown>; timeoutMs?: number };
            if (!body.method) {
              this.json(res, 400, { ok: false, error: "Missing method" });
              return;
            }
            try {
              const out = await this.execute(body.method, body.params ?? {}, body.timeoutMs ?? 30000);
              this.json(res, 200, { ok: true, output: out });
            } catch (e) {
              this.json(res, 504, { ok: false, error: e instanceof Error ? e.message : String(e) });
            }
            return;
          }

          this.json(res, 404, { ok: false, error: `Unknown route ${req.method} ${path}` });
        } catch (e) {
          try {
            this.json(res, 500, { ok: false, error: e instanceof Error ? e.message : String(e) });
          } catch { /* ignore */ }
        }
      });
      server.on("error", reject);
      server.listen(port, "127.0.0.1", () => {
        this.server = server;
        server.off("error", reject);
        resolve();
      });
    });
  }

  close() {
    for (const w of this.pollWaiters) {
      clearTimeout(w.timer);
      try { this.json(w.res, 200, { command: null }); } catch { /* ignore */ }
    }
    this.pollWaiters = [];
    this.server?.close();
  }
}
