/**
 * GET  /api/system/version  — Returns current version and latest available on npm
 * POST /api/system/version  — Triggers a deployment-aware background update
 *
 * Security: Requires admin authentication (same as other management routes).
 * Safety: Update only runs if a newer version is available on npm.
 */
import { NextRequest, NextResponse } from "next/server";
import { execFile } from "child_process";
import { promisify } from "util";
import { isAuthenticated } from "@/shared/utils/apiAuth";
import {
  ensureGitTagExists,
  getAutoUpdateConfig,
  launchAutoUpdate,
  validateAutoUpdateRuntime,
  PROJECT_ROOT,
} from "@/lib/system/autoUpdate";
import { NEWS_JSON_URL, parseActiveNewsPayload } from "@/shared/utils/releaseNotes";
import { isNewer, resolveLatestVersion } from "@/lib/system/versionCheck";
import { resolveGlobalOmniroutePath } from "@/lib/system/globalPackagePath";
// #5542 — On Windows npm is `npm.cmd`; Node ≥24 refuses to execFile a `.cmd` without
// a shell (nodejs/node#52554 → "spawn npm ENOENT"). buildNpmExecOptions enables the
// shell on win32 only; SERVICE_VERSION_PATTERN keeps the shell-joined version safe.
import { buildNpmExecOptions, SERVICE_VERSION_PATTERN } from "@/lib/services/installers/utils";

const execFileAsync = promisify(execFile);

export const dynamic = "force-dynamic";

function getCurrentVersion(): string {
  try {
    return require("../../../../../package.json").version as string;
  } catch {
    return "unknown";
  }
}

async function getNews() {
  try {
    const res = await fetch(NEWS_JSON_URL, { next: { revalidate: 3600 } });
    if (!res.ok) return null;
    const data = await res.json();
    return parseActiveNewsPayload(data);
  } catch {
    return null;
  }
}

export async function GET(req: NextRequest) {
  if (!(await isAuthenticated(req))) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const current = getCurrentVersion();
  const news = await getNews();

  // W8Mod: auto-update disabled on Termux/Android — skip npm/GitHub version lookup
  return NextResponse.json({
    current,
    latest: current,
    updateAvailable: false,
    channel: "npm",
    autoUpdateSupported: false,
    autoUpdateError: "Auto-update is disabled in W8OmniRouteTermux-Moded",
    news,
  });
}

export async function POST(req: NextRequest) {
  if (!(await isAuthenticated(req))) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  // W8Mod: auto-update disabled on Termux/Android
  return NextResponse.json(
    {
      success: false,
      error: "Auto-update is disabled in W8OmniRouteTermux-Moded. Re-run the install script to update manually.",
    },
    { status: 403 }
  );
}
