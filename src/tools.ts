import { z } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Bridge } from "./bridge.js";
import {
  studioStatus,
  launchStudio,
  openPlaceFile,
  openPublishedPlace,
  closeStudio,
  listPlaceFiles,
} from "./studio.js";

function okText(data: unknown): { content: { type: "text"; text: string }[] } {
  return { content: [{ type: "text" as const, text: typeof data === "string" ? data : JSON.stringify(data, null, 2) }] };
}

async function viaBridge(bridge: Bridge, method: string, params: Record<string, unknown>, timeoutMs?: number) {
  const t = typeof timeoutMs === "number" && timeoutMs > 0 ? timeoutMs : undefined;
  const out = await bridge.execute(method, params, t);
  return okText(out);
}

function needPluginHint(e: unknown): string {
  const msg = e instanceof Error ? e.message : String(e);
  if (msg.includes("Plugin timeout")) {
    return `${msg}\n\nHint: open Roblox Studio with any place, install plugin/MCPBridge.luau into Plugins folder (see README), enable HTTP requests, and make sure the toolbar toggle is ON. Check bridge_status.`;
  }
  return msg;
}

export function registerTools(server: McpServer, bridge: Bridge) {
  // ---------- Studio lifecycle (no plugin needed) ----------

  server.tool("studio_status", "Check if Roblox Studio is running, its PIDs, exe path and version.", {}, async () => {
    return okText(await studioStatus());
  });

  server.tool(
    "studio_launch",
    "Launch Roblox Studio (optionally opening a local .rbxl/.rbxlx file or a published place). No plugin required.",
    {
      placeFile: z.string().optional().describe("Absolute or relative path to .rbxl/.rbxlx file to open"),
      placeId: z.number().optional().describe("Published place ID to open (requires universeId)"),
      universeId: z.number().optional().describe("Universe ID that owns placeId"),
    },
    async ({ placeFile, placeId, universeId }) => {
      if (placeFile) return okText(await openPlaceFile(placeFile));
      if (placeId !== undefined && universeId !== undefined) return okText(await openPublishedPlace(placeId, universeId));
      return okText(await launchStudio());
    }
  );

  server.tool(
    "studio_open_place",
    "Open a place in Roblox Studio: either a local .rbxl/.rbxlx file or a published placeId+universeId.",
    {
      placeFile: z.string().optional(),
      placeId: z.number().optional(),
      universeId: z.number().optional(),
    },
    async ({ placeFile, placeId, universeId }) => {
      if (placeFile) return okText(await openPlaceFile(placeFile));
      if (placeId !== undefined && universeId !== undefined) return okText(await openPublishedPlace(placeId, universeId));
      throw new Error("Provide placeFile OR (placeId + universeId).");
    }
  );

  server.tool("studio_close", "Close all running Roblox Studio instances (taskkill).", {}, async () => {
    return okText(await closeStudio(true));
  });

  server.tool(
    "studio_list_places",
    "List local .rbxl/.rbxlx place files in common folders (or given dirs).",
    { dirs: z.array(z.string()).optional().describe("Directories to scan (max depth 3)") },
    async ({ dirs }) => okText(listPlaceFiles(dirs ?? undefined))
  );

  server.tool("bridge_status", "Check HTTP bridge status and whether the Studio plugin is connected.", {}, async () => {
    const s = await studioStatus();
    return okText({
      bridgePort: bridge.port,
      pluginConnected: bridge.pluginConnected,
      lastPluginSeen: bridge.lastSeen ? new Date(bridge.lastSeen).toISOString() : null,
      studio: s,
    });
  });

  // ---------- Escape hatch: arbitrary Luau ----------

  server.tool(
    "execute_luau",
    "Execute arbitrary Luau code inside Roblox Studio (Command-Bar equivalent, with undo support). Return value / prints are captured. This unlocks EVERYTHING: Toolbox, tools, services, physics, etc. Multi-line allowed.",
    {
      code: z.string().describe("Luau code to run in Studio plugin context. `game`, `workspace`, services available. Use `return ...` to get data back."),
      timeoutMs: z.number().optional().describe("Wait timeout in ms (default 30000)"),
    },
    async ({ code, timeoutMs }) => {
      try {
        return await viaBridge(bridge, "execute_luau", { code }, timeoutMs ?? undefined);
      } catch (e) {
        throw new Error(needPluginHint(e));
      }
    }
  );

  // ---------- Scene inspection / editing ----------

  server.tool(
    "get_scene",
    "List scene tree (descendants) from a root with ClassName/Name/Path. Use for viewing the scene, finding GUI, checking builds.",
    {
      root: z.string().optional().describe("Dotted path like 'Workspace', 'Lighting', 'ReplicatedStorage'. Default 'game' (top services)."),
      maxDepth: z.number().optional().describe("Max depth (default 3, max 10)"),
      maxNodes: z.number().optional().describe("Max nodes (default 300, max 2000)"),
      includeProperties: z.boolean().optional().describe("Include key properties (Position, Size, etc.)"),
    },
    async (a) => {
      try {
        return await viaBridge(bridge, "get_scene", { ...a });
      } catch (e) {
        throw new Error(needPluginHint(e));
      }
    }
  );

  server.tool("get_instance", "Get properties of one instance by dotted path (e.g. 'Workspace.SpawnLocation').", {
    path: z.string(),
  }, async ({ path }) => {
    try {
      return await viaBridge(bridge, "get_instance", { path });
    } catch (e) {
      throw new Error(needPluginHint(e));
    }
  });

  server.tool(
    "create_instance",
    "Create any Instance (Part, Model, Folder, PointLight, SelectionBox, etc.) with optional parent, name and properties. Values support Roblox types via {__type:'Vector3'|'Color3'|'UDim2'|'CFrame'|'BrickColor', value:...} or plain JSON.",
    {
      className: z.string().describe("e.g. Part, Model, Folder, Script, ScreenGui, TextButton, PointLight"),
      name: z.string().optional(),
      parent: z.string().optional().describe("Dotted parent path, default Workspace"),
      properties: z.record(z.any()).optional(),
    },
    async (a) => {
      try {
        return await viaBridge(bridge, "create_instance", { ...a });
      } catch (e) {
        throw new Error(needPluginHint(e));
      }
    }
  );

  server.tool("set_property", "Set a single property on an instance (e.g. Workspace.Part Anchored=true, Color, Position).", {
    path: z.string(),
    property: z.string(),
    value: z.any(),
  }, async (a) => {
    try {
      return await viaBridge(bridge, "set_property", { ...a });
    } catch (e) {
      throw new Error(needPluginHint(e));
    }
  });

  server.tool("set_properties", "Set multiple properties on an instance at once.", {
    path: z.string(),
    properties: z.record(z.any()),
  }, async (a) => {
    try {
      return await viaBridge(bridge, "set_properties", { ...a });
    } catch (e) {
      throw new Error(needPluginHint(e));
    }
  });

  server.tool("delete_instance", "Delete an instance by path.", { path: z.string() }, async (a) => {
    try {
      return await viaBridge(bridge, "delete_instance", { ...a });
    } catch (e) {
      throw new Error(needPluginHint(e));
    }
  });

  server.tool("rename_instance", "Rename an instance.", {
    path: z.string(),
    newName: z.string(),
  }, async (a) => {
    try {
      return await viaBridge(bridge, "rename_instance", { ...a });
    } catch (e) {
      throw new Error(needPluginHint(e));
    }
  });

  server.tool("reparent_instance", "Move an instance to a new parent.", {
    path: z.string(),
    newParent: z.string().describe("Dotted path of new parent, e.g. 'ReplicatedStorage'"),
  }, async (a) => {
    try {
      return await viaBridge(bridge, "reparent_instance", { ...a });
    } catch (e) {
      throw new Error(needPluginHint(e));
    }
  });

  server.tool("duplicate_instance", "Duplicate (clone) an instance, optionally with a new name.", {
    path: z.string(),
    newName: z.string().optional(),
  }, async (a) => {
    try {
      return await viaBridge(bridge, "duplicate_instance", { ...a });
    } catch (e) {
      throw new Error(needPluginHint(e));
    }
  });

  server.tool("get_selection", "Get current Studio selection (paths).", {}, async () => {
    try {
      return await viaBridge(bridge, "get_selection", {});
    } catch (e) {
      throw new Error(needPluginHint(e));
    }
  });

  server.tool("set_selection", "Set Studio selection to given instance paths.", {
    paths: z.array(z.string()),
  }, async (a) => {
    try {
      return await viaBridge(bridge, "set_selection", { ...a });
    } catch (e) {
      throw new Error(needPluginHint(e));
    }
  });

  // ---------- Scripts ----------

  server.tool("list_scripts", "List all Script/LocalScript/ModuleScript under a root (default game).", {
    root: z.string().optional(),
  }, async (a) => {
    try {
      return await viaBridge(bridge, "list_scripts", { ...a });
    } catch (e) {
      throw new Error(needPluginHint(e));
    }
  });

  server.tool("read_script", "Read Source of a script by path (e.g. 'ServerScriptService.MyScript', 'Workspace.Part.Script').", {
    path: z.string(),
  }, async (a) => {
    try {
      return await viaBridge(bridge, "read_script", { ...a });
    } catch (e) {
      throw new Error(needPluginHint(e));
    }
  });

  server.tool("write_script", "Overwrite Source of an existing script.", {
    path: z.string(),
    source: z.string(),
  }, async (a) => {
    try {
      return await viaBridge(bridge, "write_script", { ...a });
    } catch (e) {
      throw new Error(needPluginHint(e));
    }
  });

  server.tool(
    "create_script",
    "Create a new Script/LocalScript/ModuleScript with source code.",
    {
      scriptType: z.enum(["Script", "LocalScript", "ModuleScript"]).describe("Class of script to create"),
      name: z.string(),
      parent: z.string().describe("Dotted parent path, e.g. 'ServerScriptService', 'StarterPlayer.StarterPlayerScripts'"),
      source: z.string().optional().describe("Initial Luau source"),
    },
    async (a) => {
      try {
        return await viaBridge(bridge, "create_script", { ...a });
      } catch (e) {
        throw new Error(needPluginHint(e));
      }
    }
  );

  server.tool("delete_script", "Delete a script by path.", { path: z.string() }, async (a) => {
    try {
      return await viaBridge(bridge, "delete_script", { ...a });
    } catch (e) {
      throw new Error(needPluginHint(e));
    }
  });

  server.tool("grep_scripts", "Search script sources for a Lua pattern / substring.", {
    pattern: z.string(),
    root: z.string().optional(),
  }, async (a) => {
    try {
      return await viaBridge(bridge, "grep_scripts", { ...a });
    } catch (e) {
      throw new Error(needPluginHint(e));
    }
  });

  // ---------- Output / playtest ----------

  server.tool("get_output", "Get recent Studio Output log lines captured by the plugin.", {
    limit: z.number().optional(),
  }, async (a) => {
    try {
      return await viaBridge(bridge, "get_output", { ...a });
    } catch (e) {
      throw new Error(needPluginHint(e));
    }
  });

  server.tool("clear_output", "Clear the plugin-captured output buffer.", {}, async () => {
    try {
      return await viaBridge(bridge, "clear_output", {});
    } catch (e) {
      throw new Error(needPluginHint(e));
    }
  });

  server.tool("play_solo", "Start Play Solo playtest (F5). Agent can then check behavior via get_output / get_play_state / execute_luau.", {}, async () => {
    try {
      return await viaBridge(bridge, "play_solo", {});
    } catch (e) {
      throw new Error(needPluginHint(e));
    }
  });

  server.tool("run_game", "Start Run mode (F8, server-only simulation without player).", {}, async () => {
    try {
      return await viaBridge(bridge, "run_game", {});
    } catch (e) {
      throw new Error(needPluginHint(e));
    }
  });

  server.tool("stop_playtest", "Stop any running playtest / Run mode.", {}, async () => {
    try {
      return await viaBridge(bridge, "stop_playtest", {});
    } catch (e) {
      throw new Error(needPluginHint(e));
    }
  });

  server.tool("get_play_state", "Get current playtest state (isPlaying, isRunning, mode).", {}, async () => {
    try {
      return await viaBridge(bridge, "get_play_state", {});
    } catch (e) {
      throw new Error(needPluginHint(e));
    }
  });

  // ---------- GUI / Toolbox / world ----------

  server.tool(
    "create_gui",
    "Build GUI quickly: creates ScreenGui (in StarterGui) with nested elements (Frame/TextButton/TextLabel/ImageLabel...). Each child: {className, name, properties, children}.",
    {
      name: z.string().describe("ScreenGui name"),
      parent: z.string().optional().describe("Default 'StarterGui'"),
      properties: z.record(z.any()).optional().describe("e.g. {ResetOnSpawn:false, IgnoreGuiInset:true}"),
      children: z.array(z.any()).optional().describe("Nested element specs"),
    },
    async (a) => {
      try {
        return await viaBridge(bridge, "create_gui", { ...a });
      } catch (e) {
        throw new Error(needPluginHint(e));
      }
    }
  );

  server.tool(
    "insert_asset",
    "Insert a Toolbox/model asset by numeric asset ID into the game (InsertService:LoadAsset). E.g. free models, meshes.",
    {
      assetId: z.number().describe("Numeric catalog asset ID"),
      parent: z.string().optional().describe("Parent path, default Workspace"),
    },
    async (a) => {
      try {
        return await viaBridge(bridge, "insert_asset", { ...a }, 60000);
      } catch (e) {
        throw new Error(needPluginHint(e));
      }
    }
  );

  server.tool("save_place", "Save the current place (to its file). Optionally pass filePath hint for logging.", {
    filePath: z.string().optional(),
  }, async (a) => {
    try {
      return await viaBridge(bridge, "save_place", { ...a }, 60000);
    } catch (e) {
      throw new Error(needPluginHint(e));
    }
  });

  server.tool("get_camera", "Get current Studio camera (CFrame components, Focus, FieldOfView).", {}, async () => {
    try {
      return await viaBridge(bridge, "get_camera", {});
    } catch (e) {
      throw new Error(needPluginHint(e));
    }
  });

  server.tool("set_camera", "Move Studio camera (position+focus as {x,y,z} or CFrame table, fov number).", {
    position: z.any().optional(),
    focus: z.any().optional(),
    fov: z.number().optional(),
  }, async (a) => {
    try {
      return await viaBridge(bridge, "set_camera", { ...a });
    } catch (e) {
      throw new Error(needPluginHint(e));
    }
  });

  server.tool("get_lighting", "Get key Lighting properties (ClockTime, Brightness, Ambient, etc.).", {}, async () => {
    try {
      return await viaBridge(bridge, "get_lighting", {});
    } catch (e) {
      throw new Error(needPluginHint(e));
    }
  });

  server.tool("set_lighting", "Set Lighting properties (ClockTime, Brightness, Ambient, OutdoorAmbient, FogEnd, ...).", {
    properties: z.record(z.any()),
  }, async (a) => {
    try {
      return await viaBridge(bridge, "set_lighting", { ...a });
    } catch (e) {
      throw new Error(needPluginHint(e));
    }
  });

  server.tool("get_workspace_info", "Get Workspace stats: child count, part count, gravity, streaming, place name.", {}, async () => {
    try {
      return await viaBridge(bridge, "get_workspace_info", {});
    } catch (e) {
      throw new Error(needPluginHint(e));
    }
  });

  server.tool("undo", "Undo last Studio change (ChangeHistoryService).", {}, async () => {
    try {
      return await viaBridge(bridge, "undo", {});
    } catch (e) {
      throw new Error(needPluginHint(e));
    }
  });

  server.tool("redo", "Redo last undone Studio change.", {}, async () => {
    try {
      return await viaBridge(bridge, "redo", {});
    } catch (e) {
      throw new Error(needPluginHint(e));
    }
  });
}
