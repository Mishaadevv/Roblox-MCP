import { spawn, execFile } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";

export interface StudioStatus {
  running: boolean;
  pids: number[];
  exePath: string | null;
  version: string | null;
}

function versionsRoot(): string {
  if (process.platform === "win32") {
    const local = process.env.LOCALAPPDATA ?? path.join(os.homedir(), "AppData", "Local");
    return path.join(local, "Roblox", "Versions");
  }
  if (process.platform === "darwin") {
    return "/Applications/RobloxStudio.app/Contents/MacOS";
  }
  return "/opt/roblox-studio";
}

/** Path to the Studio bootstrapper (self-updates, then launches the real exe). */
export function findStudioInstaller(): string | null {
  if (process.platform !== "win32") return null;
  const local = process.env.LOCALAPPDATA ?? path.join(os.homedir(), "AppData", "Local");
  const cand = path.join(local, "Roblox", "Versions", "RobloxStudioInstaller.exe");
  return fs.existsSync(cand) ? cand : null;
}

export function findStudioExe(): string | null {
  const envPath = process.env.ROBLOX_STUDIO_PATH;
  if (envPath && fs.existsSync(envPath)) return envPath;

  if (process.platform === "win32") {
    const root = versionsRoot();
    if (!fs.existsSync(root)) return null;
    const entries = fs.readdirSync(root);
    // newest version first (lexicographic works for version-xxx dirs)
    entries.sort().reverse();
    for (const e of entries) {
      const cand = path.join(root, e, "RobloxStudioBeta.exe");
      if (fs.existsSync(cand)) return cand;
    }
    return null;
  }
  if (process.platform === "darwin") {
    const cand = "/Applications/RobloxStudio.app/Contents/MacOS/RobloxStudio";
    return fs.existsSync(cand) ? cand : null;
  }
  return null;
}

function psList(exeName: string): Promise<number[]> {
  return new Promise((resolve) => {
    if (process.platform === "win32") {
      execFile("tasklist", ["/FI", `IMAGENAME eq ${exeName}`, "/FO", "CSV", "/NH"], (err, stdout) => {
        if (err) return resolve([]);
        const pids: number[] = [];
        for (const line of stdout.split("\n")) {
          const m = line.match(/"([^"]+)"\s*,\s*"(\d+)"/);
          if (m && m[1].toLowerCase() === exeName.toLowerCase()) pids.push(Number(m[2]));
        }
        resolve(pids);
      });
    } else {
      execFile("pgrep", ["-f", exeName], (err, stdout) => {
        if (err) return resolve([]);
        resolve(stdout.split("\n").map((s) => Number(s.trim())).filter(Boolean));
      });
    }
  });
}

export async function studioStatus(): Promise<StudioStatus> {
  const exe = findStudioExe();
  const exeName = process.platform === "win32" ? "RobloxStudioBeta.exe" : "RobloxStudio";
  const pids = await psList(exeName);
  let version: string | null = null;
  if (exe) {
    const m = exe.match(/version-([^\\/]+)/);
    if (m) version = m[1];
  }
  return { running: pids.length > 0, pids, exePath: exe, version };
}

export async function launchStudio(args: string[] = []): Promise<{ pid: number | null; exePath: string; args: string[] }> {
  let exe = findStudioExe();
  if (!exe) {
    // Fallback: launch the Studio bootstrapper (self-updates, then drops
    // RobloxStudioBeta.exe into Versions/). Poll until the real exe appears.
    const stub = findStudioInstaller();
    if (!stub) {
      throw new Error(
        "RobloxStudioBeta.exe not found. Install Roblox Studio or set ROBLOX_STUDIO_PATH env to its full path."
      );
    }
    const installer = spawn(stub, [], { detached: true, stdio: "ignore" });
    installer.unref();
    const deadline = Date.now() + 180_000;
    while (Date.now() < deadline) {
      await new Promise((r) => setTimeout(r, 3000));
      exe = findStudioExe();
      if (exe) break;
    }
    if (!exe) {
      throw new Error(
        "Studio installer is still updating (RobloxStudioBeta.exe not present yet). Wait a minute and retry, or set ROBLOX_STUDIO_PATH."
      );
    }
  }
  const child = spawn(exe, args, { detached: true, stdio: "ignore", windowsVerbatimArguments: false });
  child.unref();
  // give OS a moment to register the process
  await new Promise((r) => setTimeout(r, 1200));
  return { pid: child.pid ?? null, exePath: exe, args };
}

/** Open a local .rbxl/.rbxlx place in Studio (launches Studio if needed). */
export async function openPlaceFile(placePath: string): Promise<{ pid: number | null; exePath: string }> {
  const abs = path.resolve(placePath);
  if (!fs.existsSync(abs)) throw new Error(`Place file not found: ${abs}`);
  if (!/\.(rbxl|rbxlx)$/i.test(abs)) throw new Error(`Not a .rbxl/.rbxlx file: ${abs}`);
  // Official CLI: --task EditFile --localPlaceFile "path"
  return launchStudio(["--task", "EditFile", "--localPlaceFile", abs]);
}

export async function openPublishedPlace(placeId: number, universeId: number, task = "EditPlace"): Promise<{ pid: number | null; exePath: string }> {
  if (!Number.isFinite(placeId) || !Number.isFinite(universeId)) throw new Error("placeId and universeId must be numbers");
  return launchStudio(["--task", task, "--placeId", String(placeId), "--universeId", String(universeId)]);
}

export async function closeStudio(force = true): Promise<{ killed: number[] }> {
  const { pids } = await studioStatus();
  if (pids.length === 0) return { killed: [] };
  if (process.platform === "win32") {
    await new Promise<void>((resolve) => {
      execFile("taskkill", force ? ["/F", "/IM", "RobloxStudioBeta.exe"] : ["/IM", "RobloxStudioBeta.exe"], () => resolve());
    });
  } else {
    for (const pid of pids) {
      try { process.kill(pid, force ? "SIGKILL" : "SIGTERM"); } catch { /* ignore */ }
    }
  }
  return { killed: pids };
}

/** Scan a directory for .rbxl/.rbxlx files (default: cwd/places + Documents/Roblox). */
export function listPlaceFiles(dirs?: string[]): { path: string; name: string; size: number; mtime: string }[] {
  const candidates = dirs?.length
    ? dirs
    : [
        path.join(process.cwd(), "places"),
        path.join(os.homedir(), "Documents", "ROBLOX", "AutoSaves"),
        path.join(os.homedir(), "Documents", "Roblox"),
      ];
  const out: { path: string; name: string; size: number; mtime: string }[] = [];
  for (const d of candidates) {
    if (!fs.existsSync(d)) continue;
    const walk = (dir: string, depth: number) => {
      if (depth > 3) return;
      let entries: fs.Dirent[] = [];
      try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
      for (const e of entries) {
        const full = path.join(dir, e.name);
        if (e.isDirectory()) { walk(full, depth + 1); continue; }
        if (/\.(rbxl|rbxlx)$/i.test(e.name)) {
          try {
            const st = fs.statSync(full);
            out.push({ path: full, name: e.name, size: st.size, mtime: st.mtime.toISOString() });
          } catch { /* ignore */ }
        }
      }
    };
    // if it's a file itself, include it
    try {
      const st = fs.statSync(d);
      if (st.isFile() && /\.(rbxl|rbxlx)$/i.test(d)) {
        out.push({ path: d, name: path.basename(d), size: st.size, mtime: st.mtime.toISOString() });
        continue;
      }
    } catch { /* ignore */ }
    walk(d, 0);
  }
  return out.sort((a, b) => b.mtime.localeCompare(a.mtime)).slice(0, 100);
}
