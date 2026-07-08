#!/bin/bash
set -e

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║     W8OmniRouteTermux-Moded — Quick Installer        ║"
echo "║     Patched OmniRoute for Termux/Android             ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── Step 1: Install requirements ──────────────────────────────────────────
echo "[1/4] Checking Node.js and Git..."
pkg install -y nodejs git 2>/dev/null || true

# ── Step 2: Install omniroute from npm (pre-built, fast) ──────────────────
echo "[2/4] Installing OmniRoute from npm (pre-built, ~2 min)..."
npm install -g omniroute@3.8.46

OMNIROUTE_DIR=$(npm root -g)/omniroute
echo "      Installed at: $OMNIROUTE_DIR"

# ── Step 3: Apply all Termux/Android patches ──────────────────────────────
echo "[3/4] Applying Termux/Android patches..."

node << 'PATCHEOF'
const fs   = require('fs');
const path = require('path');

const BASE   = process.env.OMNIROUTE_DIR || '';
if (!BASE) { console.log('OMNIROUTE_DIR not set'); process.exit(1); }

const CHUNKS = path.join(BASE, 'dist', '.build', 'next', 'server', 'chunks');
const SSR    = path.join(CHUNKS, 'ssr');

let stats = { playwright: 0, bind: 0, instrumentation: 0, skipped: 0 };

/* ── Patch A: Playwright → skip on Android ───────────────────────────── */
function patchPlaywright(fp) {
  let c = fs.readFileSync(fp, 'utf8');
  if (c.includes("process.platform==='android'")) { stats.skipped++; return; }
  // full-SSE pattern
  c = c.replace(
    /let c=await (\w+)\.y\(["'](playwright(?:-core)?)["']\)/g,
    "let c=(process.platform==='android'?{}:await $1.y('$2'))"
  );
  // SSR pattern
  c = c.replace(
    /await (\w+)\.y\(["'](playwright(?:-core)?)["']\)/g,
    "(process.platform==='android'?{}:await $1.y('$2'))"
  );
  fs.writeFileSync(fp, c);
  stats.playwright++;
  console.log('  ✔ playwright: ' + path.basename(fp));
}

/* ── Patch B: sql.js named-parameter binding ─────────────────────────── */
const BIND_HELPER = `
function __w8bindParams(p){
  if(!p||Array.isArray(p))return p;
  const o={};
  for(const[k,v]of Object.entries(p)){
    const px=k[0];
    o[(px==='@'||px==='$'||px===':')?k:'@'+k]=v;
  }
  return o;
}
`;

function patchBind(fp) {
  let c = fs.readFileSync(fp, 'utf8');
  if (c.includes('__w8bindParams')) { stats.skipped++; return; }
  c = BIND_HELPER + c;
  c = c.replace(/\.bind\((\w+)\)/g, '.bind(__w8bindParams($1))');
  fs.writeFileSync(fp, c);
  stats.bind++;
}

/* ── Patch C: DB pre-init in registerNodejs ──────────────────────────── */
function patchInstrumentation(fp) {
  let c = fs.readFileSync(fp, 'utf8');
  if (c.includes('__w8dbPreInit')) { stats.skipped++; return; }
  if (!c.includes('registerNodejs') || !c.includes('ensureDbInitialized')) return;
  c = c.replace(
    /(async function registerNodejs\(\)\{)/,
    '$1const __w8dbPreInit=true;try{await ensureDbInitialized();}catch(e){console.warn("[w8]",e?.message);}'
  );
  fs.writeFileSync(fp, c);
  stats.instrumentation++;
  console.log('  ✔ instrumentation: ' + path.basename(fp));
}

/* ── Walk chunks dir ─────────────────────────────────────────────────── */
function walkDir(dir) {
  if (!fs.existsSync(dir)) return;
  for (const file of fs.readdirSync(dir).filter(f => f.endsWith('.js'))) {
    const fp = path.join(dir, file);
    try {
      if (file.includes('playwright')) patchPlaywright(fp);
      patchBind(fp);
      patchInstrumentation(fp);
    } catch (e) { /* skip unreadable */ }
  }
}

walkDir(CHUNKS);
walkDir(SSR);

console.log('');
console.log('  Patch summary:');
console.log('    playwright fixes : ' + stats.playwright);
console.log('    bind fixes       : ' + stats.bind);
console.log('    instrumentation  : ' + stats.instrumentation);
console.log('    already patched  : ' + stats.skipped);
PATCHEOF

# Export the install dir so the heredoc can use it
export OMNIROUTE_DIR
node << 'PATCHEOF'
const fs   = require('fs');
const path = require('path');
const BASE = process.env.OMNIROUTE_DIR || '';
const CHUNKS = path.join(BASE, 'dist', '.build', 'next', 'server', 'chunks');
const SSR    = path.join(CHUNKS, 'ssr');

let stats = { playwright: 0, bind: 0, instrumentation: 0, skipped: 0 };

function patchPlaywright(fp) {
  let c = fs.readFileSync(fp, 'utf8');
  if (c.includes("process.platform==='android'")) { stats.skipped++; return; }
  c = c.replace(
    /let c=await (\w+)\.y\(["'](playwright(?:-core)?)["']\)/g,
    "let c=(process.platform==='android'?{}:await $1.y('$2'))"
  );
  c = c.replace(
    /await (\w+)\.y\(["'](playwright(?:-core)?)["']\)/g,
    "(process.platform==='android'?{}:await $1.y('$2'))"
  );
  fs.writeFileSync(fp, c);
  stats.playwright++;
  console.log('  ✔ playwright: ' + path.basename(fp));
}

const BIND_HELPER = `
function __w8bindParams(p){
  if(!p||Array.isArray(p))return p;
  const o={};
  for(const[k,v]of Object.entries(p)){const px=k[0];o[(px==='@'||px==='$'||px===':')?k:'@'+k]=v;}
  return o;
}
`;

function patchBind(fp) {
  let c = fs.readFileSync(fp, 'utf8');
  if (c.includes('__w8bindParams')) { stats.skipped++; return; }
  c = BIND_HELPER + c;
  c = c.replace(/\.bind\((\w+)\)/g, '.bind(__w8bindParams($1))');
  fs.writeFileSync(fp, c);
  stats.bind++;
}

function patchInstrumentation(fp) {
  let c = fs.readFileSync(fp, 'utf8');
  if (c.includes('__w8dbPreInit')) { stats.skipped++; return; }
  if (!c.includes('registerNodejs') || !c.includes('ensureDbInitialized')) return;
  c = c.replace(
    /(async function registerNodejs\(\)\{)/,
    '$1const __w8dbPreInit=true;try{await ensureDbInitialized();}catch(e){console.warn("[w8]",e?.message);}'
  );
  fs.writeFileSync(fp, c);
  stats.instrumentation++;
  console.log('  ✔ instrumentation: ' + path.basename(fp));
}

function walkDir(dir) {
  if (!fs.existsSync(dir)) return;
  for (const file of fs.readdirSync(dir).filter(f => f.endsWith('.js'))) {
    const fp = path.join(dir, file);
    try {
      if (file.includes('playwright')) patchPlaywright(fp);
      patchBind(fp);
      patchInstrumentation(fp);
    } catch (e) {}
  }
}

walkDir(CHUNKS);
walkDir(SSR);

console.log('');
console.log('  Patch summary:');
console.log('    playwright fixes : ' + stats.playwright);
console.log('    bind fixes       : ' + stats.bind);
console.log('    instrumentation  : ' + stats.instrumentation);
console.log('    already patched  : ' + stats.skipped);
PATCHEOF

# ── Step 4: Done ──────────────────────────────────────────────────────────
echo ""
echo "[4/4] Verifying install..."
omniroute --version 2>/dev/null || true

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✅ W8OmniRouteTermux-Moded installed successfully!  ║"
echo "║                                                      ║"
echo "║  Start the server:  omniroute serve                  ║"
echo "║  Dashboard:         http://localhost:20128           ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
