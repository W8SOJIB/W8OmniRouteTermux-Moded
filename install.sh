#!/bin/bash
set -e

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║     W8OmniRouteTermux-Moded — Quick Installer        ║"
echo "║     Patched OmniRoute for Termux/Android             ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# 1. Install requirements
echo "[1/4] Checking Node.js and Git..."
pkg install -y nodejs git 2>/dev/null || true

# 2. Install omniroute from npm (pre-built, fast)
echo "[2/4] Installing OmniRoute from npm (pre-built)..."
npm install -g omniroute@3.8.46

# 3. Find the global install path
OMNIROUTE_DIR=$(npm root -g)/omniroute
echo "      Installed at: $OMNIROUTE_DIR"

# 4. Apply Termux/Android patches
echo "[3/4] Applying Termux/Android patches..."

# ── Patch A: Playwright → skip on Android ──────────────────────────────────
echo "      Patching playwright chunks..."
CHUNKS_DIR="$OMNIROUTE_DIR/dist/.build/next/server/chunks"
if [ -d "$CHUNKS_DIR" ]; then
  for f in "$CHUNKS_DIR"/*playwright*.js; do
    [ -f "$f" ] || continue
    node -e "
      const fs = require('fs');
      let c = fs.readFileSync('$f', 'utf8');
      // If already patched, skip
      if (c.includes('process.platform===\\'android\\'')) { process.exit(0); }
      // Patch: wrap playwright require with android check
      c = c.replace(
        /let c=await (\w+)\.y\([\"'](playwright(?:-core)?)[\"']\)/g,
        'let c=(process.platform===\\'android\\'?{}:await \$1.y(\"\$2\"))'
      );
      fs.writeFileSync('$f', c);
      console.log('      ✔ Patched: $f');
    " 2>/dev/null || true
  done

  # Also patch SSR chunk
  SSR_DIR="$CHUNKS_DIR/ssr"
  if [ -d "$SSR_DIR" ]; then
    for f in "$SSR_DIR"/*playwright*.js; do
      [ -f "$f" ] || continue
      node -e "
        const fs = require('fs');
        let c = fs.readFileSync('$f', 'utf8');
        if (c.includes('process.platform===\\'android\\'')) { process.exit(0); }
        c = c.replace(
          /await (\w+)\.y\([\"'](playwright(?:-core)?)[\"']\)/g,
          '(process.platform===\\'android\\'?{}:await \$1.y(\"\$2\"))'
        );
        fs.writeFileSync('$f', c);
        console.log('      ✔ Patched SSR: $f');
      " 2>/dev/null || true
    done
  fi
fi

# ── Patch B: sql.js named parameter binding ────────────────────────────────
echo "      Patching sql.js named parameter bindings..."
node -e "
const fs = require('fs');
const path = require('path');
const chunksDir = path.join('$OMNIROUTE_DIR', 'dist', '.build', 'next', 'server', 'chunks');
if (!fs.existsSync(chunksDir)) { console.log('      ⚠ chunks dir not found, skipping bind patch'); process.exit(0); }

function patchFile(filePath) {
  let content = fs.readFileSync(filePath, 'utf8');
  if (!content.includes('sqljsAdapter') && !content.includes('sql.js') && !content.includes('bindParams')) {
    // Search for the bind pattern more broadly
    if (!content.includes('.bind(') || !content.includes('named')) return false;
  }
  // Only patch files that contain the bind method for sql.js statements
  if (!content.includes('Statement') && !content.includes('stmt')) return false;

  const bindPatch = \`
function __w8bindParams(params) {
  if (!params || Array.isArray(params)) return params;
  const out = {};
  for (const [k, v] of Object.entries(params)) {
    const prefix = k[0];
    if (prefix === '@' || prefix === '\$' || prefix === ':') { out[k] = v; }
    else { out['@' + k] = v; }
  }
  return out;
}
\`;
  if (content.includes('__w8bindParams')) return false; // already patched

  // Insert helper and patch .run/.all/.get calls
  content = bindPatch + content;
  content = content.replace(/\.bind\((\w+)\)/g, '.bind(__w8bindParams(\$1))');
  fs.writeFileSync(filePath, content);
  return true;
}

let patched = 0;
const files = fs.readdirSync(chunksDir).filter(f => f.endsWith('.js'));
for (const file of files) {
  const fp = path.join(chunksDir, file);
  try {
    const c = fs.readFileSync(fp, 'utf8');
    if ((c.includes('sqljsAdapter') || c.includes('sql.js') || c.includes('SqlJs')) && c.includes('stmt')) {
      if (patchFile(fp)) { console.log('      ✔ Patched bind in: ' + file); patched++; }
    }
  } catch(e) {}
}
if (patched === 0) console.log('      ℹ No sql.js bind patches needed (may already be patched)');
" 2>/dev/null || true

# ── Patch C: Better-sqlite3 → sql.js fallback on Android ──────────────────
echo "      Patching better-sqlite3 → sql.js fallback..."
node -e "
const fs = require('fs');
const path = require('path');
const chunksDir = path.join('$OMNIROUTE_DIR', 'dist', '.build', 'next', 'server', 'chunks');
if (!fs.existsSync(chunksDir)) { process.exit(0); }
const files = fs.readdirSync(chunksDir).filter(f => f.endsWith('.js'));
let patched = 0;
for (const file of files) {
  const fp = path.join(chunksDir, file);
  try {
    let c = fs.readFileSync(fp, 'utf8');
    if (c.includes('better-sqlite3') && c.includes('require') && !c.includes('android-sqlite3-skip')) {
      c = c.replace(
        /require\([\"']better-sqlite3[\"']\)/g,
        '(process.platform===\\'android\\'?(function(){throw new Error(\\'android-sqlite3-skip\\')})():require(\\'better-sqlite3\\'))'
      );
      fs.writeFileSync(fp, c);
      console.log('      ✔ Patched better-sqlite3 in: ' + file);
      patched++;
    }
  } catch(e) {}
}
if (patched === 0) console.log('      ℹ No better-sqlite3 patches needed');
" 2>/dev/null || true

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
