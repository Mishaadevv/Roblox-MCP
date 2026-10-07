// End-to-end MCP check: spawns dist/index.js over stdio, lists tools,
// calls bridge_status + studio_status (no Studio needed for these),
// then performs a FULL roundtrip: fake Studio plugin answers an
// execute_luau tool call through the real bridge.
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const PORT = Number(process.env.ROBLOX_BRIDGE_PORT ?? 8091);
const BASE = `http://127.0.0.1:${PORT}`;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const transport = new StdioClientTransport({
  command: process.execPath,
  args: ["dist/index.js"],
  env: { ...process.env, ROBLOX_BRIDGE_PORT: String(PORT) },
  stderr: "ignore",
});
const client = new Client({ name: "mcp-check", version: "0.1.0" });

await client.connect(transport);
const { tools } = await client.listTools();
console.log("TOOLS_COUNT=" + tools.length);
const names = tools.map((t) => t.name);
const bad = tools.filter((t) => !t.inputSchema);
if (bad.length) throw new Error("tools without schema: " + bad.map((t) => t.name).join(","));
for (const must of ["studio_launch", "studio_close", "execute_luau", "get_scene", "create_gui", "insert_asset", "play_solo",
  "toolbox_search", "toolbox_info", "bulk_create", "find_instances", "get_children",
  "playtest", "get_performance", "teleport_player", "respawn_player", "kill_player"]) {
  if (!names.includes(must)) throw new Error("missing tool: " + must);
}
console.log("tool schemas OK");

for (const name of ["bridge_status", "studio_status"]) {
  const res = await client.callTool({ name, arguments: {} });
  const text = res.content?.[0]?.text ?? "";
  console.log(`${name}:`, text.slice(0, 200).replace(/\n/g, " "));
  if (res.isError) throw new Error(`${name} returned error: ${text}`);
}

// full roundtrips with a simulated Studio plugin (answers 3 commands)
const pluginSim = (async () => {
  for (let i = 0; i < 3; i++) {
    const poll = await fetch(`${BASE}/poll?timeoutMs=15000`);
    const { command } = await poll.json();
    if (!command?.id) throw new Error("simulated plugin got no command");
    await fetch(`${BASE}/result`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id: command.id, ok: true, output: { returned: [42], printed: ["hello from studio"] } }),
    });
  }
})();

await sleep(500);
const round = await client.callTool({
  name: "execute_luau",
  arguments: { code: "print('hi') return 42", timeoutMs: 12000 },
});
const roundText = round.content?.[0]?.text ?? "";
console.log("execute_luau roundtrip:", roundText.slice(0, 300));
if (round.isError || !roundText.includes("42")) throw new Error("roundtrip failed: " + roundText);

const bulk = await client.callTool({
  name: "bulk_create",
  arguments: { items: [{ className: "Part", name: "A" }, { className: "Part", name: "B" }], timeoutMs: 12000 },
});
if (bulk.isError) throw new Error("bulk_create failed: " + bulk.content?.[0]?.text);
console.log("bulk_create roundtrip OK");

const found = await client.callTool({
  name: "find_instances",
  arguments: { className: "Part", limit: 5, timeoutMs: 12000 },
});
if (found.isError) throw new Error("find_instances failed");
console.log("find_instances roundtrip OK");
await pluginSim;

// server-side toolbox search (live catalog API, no plugin)
const tb = await client.callTool({ name: "toolbox_search", arguments: { keyword: "wooden chair", limit: 3 } });
const tbText = tb.content?.[0]?.text ?? "";
console.log("toolbox_search:", tbText.slice(0, 300));
if (tb.isError || !tbText.includes("assetId")) throw new Error("toolbox_search failed: " + tbText);

await client.close();
console.log("MCP_CHECK_DONE");
process.exit(0);
