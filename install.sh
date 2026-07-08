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

export OMNIROUTE_DIR
OMNIROUTE_DIR="$(npm root -g)/omniroute"
echo "      Installed at: $OMNIROUTE_DIR"

# ── Step 3: Apply all Termux/Android patches ──────────────────────────────
echo "[3/4] Applying Termux/Android patches..."

OMNIROUTE_DIR="$OMNIROUTE_DIR" node << 'PATCHEOF'
const fs   = require('fs');
const path = require('path');

const BASE   = process.env.OMNIROUTE_DIR;
if (!BASE || !fs.existsSync(BASE)) {
  console.error('ERROR: Cannot find omniroute at: ' + BASE);
  process.exit(1);
}

const CHUNKS = path.join(BASE, 'dist', '.build', 'next', 'server', 'chunks');
const SSR    = path.join(CHUNKS, 'ssr');

let stats = { playwright: 0, bind: 0, instrumentation: 0, driverFactory: 0, skipped: 0 };

/* ─────────────────────────────────────────────────────────────────────────
   PATCH A: Playwright → skip on Android
   Target: files named *playwright*.js
   ───────────────────────────────────────────────────────────────────────── */
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

/* ─────────────────────────────────────────────────────────────────────────
   PATCH B: sql.js named-parameter binding (TARGETED)
   Only applies to the sqljsAdapter wrapper file (src_lib_*.js or similar)
   that contains sql.js Statement lifecycle methods (prepare + free).
   NEVER applies to node_modules_sql_js_dist_sql-wasm_*.js files (WASM code).
   ───────────────────────────────────────────────────────────────────────── */
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

function patchBind(fp, fileName) {
  // NEVER patch sql.js WASM dist files — they use .bind() for WASM internals
  if (fileName.includes('sql-wasm') || fileName.startsWith('node_modules_sql_js')) return;

  let c = fs.readFileSync(fp, 'utf8');
  if (c.includes('__w8bindParams')) { stats.skipped++; return; }

  // Only target files that are the sqljsAdapter wrapper:
  // Must contain sql.js-specific adapter patterns AND be a source file
  const isSqljsAdapter = (
    (c.includes('sqljsAdapter') || c.includes('SqlJsAdapter') || c.includes('sql.js'))
    && c.includes('.prepare(')   // sql.js Statement creation
    && c.includes('.free()')     // sql.js Statement disposal
    && !fileName.startsWith('node_modules')
  );
  if (!isSqljsAdapter) return;

  c = BIND_HELPER + c;
  // Only wrap .bind() calls that are immediately followed by a closing paren (named param binding)
  // This is more targeted than global replacement
  c = c.replace(/\.bind\((\w+)\)/g, '.bind(__w8bindParams($1))');
  fs.writeFileSync(fp, c);
  stats.bind++;
  console.log('  ✔ sqljsAdapter bind: ' + fileName);
}

/* ─────────────────────────────────────────────────────────────────────────
   PATCH C: driverFactory close() → no-op for cached sql.js singleton
   Target: file containing preInitSqlJs + adapter.close
   Prevents the startup DB probe from destroying the WASM connection.
   ───────────────────────────────────────────────────────────────────────── */
function patchDriverFactory(fp) {
  let c = fs.readFileSync(fp, 'utf8');
  if (c.includes('__w8noopClose')) { stats.skipped++; return; }
  if (!c.includes('preInitSqlJs') && !c.includes('SqlJsAdapter')) return;

  // Wrap the adapter close method to be a no-op
  // Pattern: find where adapter.close is assigned/called after creating the adapter
  // Insert a no-op wrapper after adapter creation
  const closeNoOp = `
// W8Mod: prevent cached sql.js adapter from being closed
if(typeof __w8noopClose==='undefined'){var __w8noopClose=true;}
`;
  // Wrap any .close() call on the adapter with an android guard
  c = c.replace(
    /([\w$]+\.close\s*=\s*)(function\s*\([^)]*\)\s*\{)/g,
    (match, prefix, fn) => {
      if (c.includes('preInitSqlJs')) {
        return prefix + 'function(){/* W8Mod: no-op close for sql.js singleton */};//' + fn;
      }
      return match;
    }
  );
  fs.writeFileSync(fp, c);
  stats.driverFactory++;
  console.log('  ✔ driverFactory close no-op: ' + path.basename(fp));
}

/* ─────────────────────────────────────────────────────────────────────────
   PATCH D: instrumentation-node → DB pre-init at registerNodejs start
   Target: chunk containing registerNodejs + ensureDbInitialized
   ───────────────────────────────────────────────────────────────────────── */
function patchInstrumentation(fp) {
  let c = fs.readFileSync(fp, 'utf8');
  if (c.includes('__w8dbPreInit')) { stats.skipped++; return; }
  if (!c.includes('registerNodejs') || !c.includes('ensureDbInitialized')) return;
  c = c.replace(
    /(async function registerNodejs\(\)\{)/,
    '$1if(process.platform===\'android\'){try{Object.defineProperty(process,\'platform\',{value:\'linux\',configurable:true});}catch(e){}}try{await ensureDbInitialized();}catch(__w8dbPreInit){console.warn("[w8-init]",__w8dbPreInit?.message);}'
  );
  fs.writeFileSync(fp, c);
  stats.instrumentation++;
  console.log('  ✔ instrumentation: ' + path.basename(fp));
}

/* ── Walk chunk directories ──────────────────────────────────────────── */
function walkDir(dir) {
  if (!fs.existsSync(dir)) return;
  const files = fs.readdirSync(dir).filter(f => f.endsWith('.js'));
  for (const file of files) {
    const fp = path.join(dir, file);
    try {
      if (file.includes('playwright')) patchPlaywright(fp);
      patchBind(fp, file);
      patchDriverFactory(fp);
      patchInstrumentation(fp);
    } catch (e) { /* skip unreadable */ }
  }
}

walkDir(CHUNKS);
walkDir(SSR);

console.log('');
console.log('  Patch summary:');
console.log('    playwright fixes   : ' + stats.playwright);
console.log('    sqljsAdapter bind  : ' + stats.bind);
console.log('    driverFactory noop : ' + stats.driverFactory);
console.log('    instrumentation    : ' + stats.instrumentation);
console.log('    already patched    : ' + stats.skipped);
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
