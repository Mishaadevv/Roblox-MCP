// Self-contained bridge protocol test — no Roblox Studio, no external server.
// Starts a real Bridge from dist/, simulates the Studio plugin (poll + result)
// and an agent command, asserting the full roundtrip.
import { Bridge } from "../dist/bridge.js";

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const b = new Bridge(8090);
const port = await b.listen();
const BASE = `http://127.0.0.1:${port}`;
console.log("bridge on", port);

const health = await (await fetch(`${BASE}/health`)).json();
if (!health.ok || health.service !== "roblox-mcp-bridge") throw new Error("bad /health: " + JSON.stringify(health));
console.log("health OK");

// fake Studio plugin: long-poll, execute (echo), post result
const plugin = (async () => {
  const poll = await fetch(`${BASE}/poll?timeoutMs=10000`);
  const { command } = await poll.json();
  if (!command?.id) throw new Error("plugin got no command");
  console.log("plugin got:", command.method, command.id);
  await sleep(100); // simulate Luau execution time
  const res = await fetch(`${BASE}/result`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ id: command.id, ok: true, output: { echo: command.params, simulated: true } }),
  });
  const posted = await res.json();
  if (!posted.delivered) throw new Error("result not delivered");
  console.log("plugin posted result OK");
})();

await sleep(300);

// fake agent: synchronous command, waits for plugin like a real MCP tool call
const started = Date.now();
const cmd = await fetch(`${BASE}/command`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ method: "get_workspace_info", params: { root: "Workspace" }, timeoutMs: 12000 }),
});
const body = await cmd.json();
if (!body.ok || !body.output?.simulated) throw new Error("bad /command response: " + JSON.stringify(body));
console.log(`agent roundtrip OK in ${Date.now() - started}ms:`, JSON.stringify(body.output));

await plugin;

// status should show the plugin was recently seen
const status = await (await fetch(`${BASE}/status`)).json();
if (!status.pluginConnected) throw new Error("expected pluginConnected=true, got: " + JSON.stringify(status));
console.log("status OK:", JSON.stringify(status));

b.close();
console.log("BRIDGE TEST PASSED");
process.exit(0);
