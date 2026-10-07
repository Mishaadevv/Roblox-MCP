// Builds the BACKROOMS game into a LIVE Roblox Studio through MCP tools.
//
// Usage:
//   1. Open Roblox Studio with an empty Baseplate.
//   2. Allow the MCPBridge plugin's localhost permission if Studio asks.
//   3. Run: node scripts/build-backrooms-mcp.mjs
//   4. Watch the game appear in Studio, then press Play.
//
// What it does (all via MCP, no file tricks inside Studio):
//   bridge_status -> create Shared folder -> create 13 scripts -> set
//   CharacterAutoLoads=false -> verify list_scripts -> playtest 15s ->
//   print Output -> save_place (best effort).
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const ROOT = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const SRC = path.join(ROOT, "backrooms", "src");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = (m) => console.log(`[mcp-build] ${m}`);

// parent service -> files (Script/LocalScript/ModuleScript by extension)
const PLAN = [
  { parent: "ServerScriptService", file: "Server/GameManager.server.lua", type: "Script", name: "GameManager" },
  { parent: "ServerScriptService", file: "Server/LevelGenerator.lua", type: "ModuleScript", name: "LevelGenerator" },
  { parent: "ServerScriptService", file: "Server/LightManager.server.lua", type: "Script", name: "LightManager" },
  { parent: "ServerScriptService", file: "Server/EntityServer.server.lua", type: "Script", name: "EntityServer" },
  { parent: "ServerScriptService", file: "Server/Pickups.server.lua", type: "Script", name: "Pickups" },
  { parent: "ReplicatedStorage.Shared", file: "Shared/Config.lua", type: "ModuleScript", name: "Config" },
  { parent: "ReplicatedStorage.Shared", file: "Shared/Util.lua", type: "ModuleScript", name: "Util" },
  { parent: "ReplicatedStorage.Shared", file: "Shared/LevelState.lua", type: "ModuleScript", name: "LevelState" },
  { parent: "ReplicatedStorage.Shared", file: "Shared/EntityState.lua", type: "ModuleScript", name: "EntityState" },
  { parent: "ReplicatedStorage.Shared", file: "Shared/Flashlights.lua", type: "ModuleScript", name: "Flashlights" },
  { parent: "StarterPlayer.StarterPlayerScripts", file: "Client/MainMenu.client.lua", type: "LocalScript", name: "MainMenu" },
  { parent: "StarterPlayer.StarterPlayerScripts", file: "Client/HUD.client.lua", type: "LocalScript", name: "HUD" },
  { parent: "StarterPlayer.StarterPlayerScripts", file: "Client/Effects.client.lua", type: "LocalScript", name: "Effects" },
];

async function call(client, name, args) {
  const res = await client.callTool({ name, arguments: args });
  if (res.isError) {
    const text = res.content?.[0]?.text ?? "unknown error";
    throw new Error(`${name} failed: ${text.slice(0, 500)}`);
  }
  return res.content?.[0]?.text ?? "";
}

async function main() {
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: [path.join(ROOT, "dist", "index.js")],
    env: { ...process.env, ROBLOX_BRIDGE_PORT: "8090" },
    stderr: "ignore",
  });
  const client = new Client({ name: "backrooms-builder", version: "1.0.0" });
  await client.connect(transport);
  log("MCP connected. Waiting for the Studio plugin (open Studio + any place)...");

  // 1. wait for plugin
  const waitMs = Number(process.env.MCP_BUILD_WAIT_MS ?? 5 * 60 * 1000);
  const deadline = Date.now() + waitMs;
  for (;;) {
    const raw = await call(client, "bridge_status", {});
    const st = JSON.parse(raw);
    if (st.pluginConnected) {
      log("Studio plugin connected.");
      break;
    }
    if (Date.now() > deadline) throw new Error("Timed out waiting for Studio. Open Roblox Studio with any place and make sure the MCPBridge toolbar toggle is ON.");
    await sleep(5000);
  }

  // 2. Shared folder
  const kids = JSON.parse(await call(client, "get_children", { path: "ReplicatedStorage" }));
  if (!kids.children.some((c) => c.Name === "Shared")) {
    await call(client, "create_instance", { className: "Folder", name: "Shared", parent: "ReplicatedStorage" });
    log("created ReplicatedStorage.Shared");
  } else {
    log("ReplicatedStorage.Shared exists");
  }

  // 3. scripts (delete-then-create = clean rebuild)
  for (const step of PLAN) {
    const source = fs.readFileSync(path.join(SRC, step.file), "utf8");
    const full = `${step.parent}.${step.name}`;
    try {
      await call(client, "delete_script", { path: full });
      log(`removed old ${full}`);
    } catch { /* didn't exist, fine */ }
    await call(client, "create_script", {
      scriptType: step.type,
      name: step.name,
      parent: step.parent,
      source,
    });
    log(`created ${full} (${source.length} chars)`);
  }

  // 4. menu-first flow: no auto character
  await call(client, "set_property", { path: "Players", property: "CharacterAutoLoads", value: false });
  log("Players.CharacterAutoLoads = false");

  // 5. verify
  const scripts = JSON.parse(await call(client, "list_scripts", {}));
  const names = new Set(scripts.map((s) => s.Path));
  const missing = PLAN.map((s) => `${s.parent}.${s.name}`).filter((p) => !names.has(p));
  if (missing.length) throw new Error("Missing after build: " + missing.join(", "));
  log(`verified ${PLAN.length} scripts in Studio`);

  // 6. playtest: generate + boot + entity, read Output
  log("playtest: Play Solo for 15s...");
  const report = JSON.parse(await call(client, "playtest", { mode: "solo", seconds: 15, outputLimit: 60 }));
  console.log("----- playtest output -----");
  for (const line of report.output ?? []) console.log("  " + line);
  console.log("---------------------------");
  const boot = (report.output ?? []).join("\n");
  if (!boot.includes("[Backrooms]")) throw new Error("No [Backrooms] boot lines in Output — generation may have failed.");
  log("boot lines present. stopped=" + report.stopped);

  // 7. save (best effort; Studio may require Ctrl+S)
  try {
    await call(client, "save_place", {});
    log("save_place OK");
  } catch (e) {
    log("save_place not available, press Ctrl+S in Studio. (" + String(e).slice(0, 120) + ")");
  }

  await client.close();
  log("DONE. Press Play in Studio, click ENTER, survive.");
}

main().catch((e) => {
  console.error("[mcp-build] FAILED:", e.message);
  process.exit(1);
});
