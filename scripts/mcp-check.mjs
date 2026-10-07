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
for (const must of ["studio_launch", "studio_close", "execute_luau", "get_scene", "create_gui", "insert_asset", "play_solo"]) {
  if (!names.includes(must)) throw new Error("missing tool: " + must);
}
console.log("tool schemas OK");

for (const name of ["bridge_status", "studio_status"]) {
  const res = await client.callTool({ name, arguments: {} });
  const text = res.content?.[0]?.text ?? "";
  console.log(`${name}:`, text.slice(0, 200).replace(/\n/g, " "));
  if (res.isError) throw new Error(`${name} returned error: ${text}`);
}

// full roundtrip with a simulated Studio plugin
const pluginSim = (async () => {
  const poll = await fetch(`${BASE}/poll?timeoutMs=15000`);
  const { command } = await poll.json();
  if (!command?.id) throw new Error("simulated plugin got no command");
  await fetch(`${BASE}/result`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ id: command.id, ok: true, output: { returned: [42], printed: ["hello from studio"] } }),
  });
})();

await sleep(500);
const round = await client.callTool({
  name: "execute_luau",
  arguments: { code: "print('hi') return 42", timeoutMs: 12000 },
});
const roundText = round.content?.[0]?.text ?? "";
console.log("execute_luau roundtrip:", roundText.slice(0, 300));
if (round.isError || !roundText.includes("42")) throw new Error("roundtrip failed: " + roundText);
await pluginSim;

await client.close();
console.log("MCP_CHECK_DONE");
process.exit(0);
