#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { Bridge } from "./bridge.js";
import { registerTools } from "./tools.js";
import { studioStatus } from "./studio.js";

async function main() {
  const bridge = new Bridge();
  const port = await bridge.listen();
  console.error(`[roblox-mcp] HTTP bridge on http://127.0.0.1:${port} (health: /health, poll: /poll, result: /result, debug: POST /command)`);

  try {
    const s = await studioStatus();
    console.error(`[roblox-mcp] Studio: ${s.running ? `running (pids ${s.pids.join(",")})` : "not running"} exe=${s.exePath ?? "not found"}`);
  } catch (e) {
    console.error(`[roblox-mcp] Studio check failed: ${e instanceof Error ? e.message : e}`);
  }

  if (process.env.ROBLOX_MCP_API_KEY) {
    console.error(`[roblox-mcp] API key auth ENABLED. In Studio command bar run: _G.MCP_SetApiKey("${process.env.ROBLOX_MCP_API_KEY}")`);
  } else {
    console.error(`[roblox-mcp] No API key (open LAN-less localhost). Set ROBLOX_MCP_API_KEY to require one.`);
  }

  const server = new McpServer({ name: "roblox-mcp", version: "0.1.0" });
  registerTools(server, bridge);

  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error(`[roblox-mcp] MCP stdio server ready (50 tools). Open Roblox Studio + enable MCPBridge plugin.`);

  const shutdown = () => {
    bridge.close();
    process.exit(0);
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}

main().catch((e) => {
  console.error(`[roblox-mcp] fatal: ${e instanceof Error ? e.stack ?? e.message : e}`);
  process.exit(1);
});
