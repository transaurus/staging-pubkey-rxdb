#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/pubkey/rxdb"
BRANCH="master"
REPO_DIR="source-repo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Clone (skip if already exists) ---
if [ ! -d "$REPO_DIR" ]; then
    git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$REPO_DIR"
fi

cd "$REPO_DIR"

# --- Node version: 24.14.0 (from .nvmrc) ---
REQUIRED_NODE="24.14.0"
CURRENT_NODE=$(node --version 2>/dev/null | sed 's/v//')
if [ "$CURRENT_NODE" != "$REQUIRED_NODE" ]; then
    echo "[INFO] Installing Node $REQUIRED_NODE via n..."
    sudo n "$REQUIRED_NODE"
    export PATH="/usr/local/bin:$PATH"
fi
echo "[INFO] Node: $(node --version)"
echo "[INFO] npm: $(npm --version)"

# --- Install root rxdb dependencies (needed for rxjs, js-base64, babel, etc.) ---
echo "[INFO] Installing root rxdb dependencies..."
npm install --ignore-scripts

# --- Build rxdb to dist/cjs/ using babel ---
# docs-src imports from '../../../' and '../../../plugins/core'
echo "[INFO] Building rxdb CJS (babel compile)..."
NODE_ENV=es5 ./node_modules/.bin/babel src --out-dir dist/cjs --extensions .ts --copy-files

# --- Create plugins/ stub directory ---
# docs-src/src/components/ imports '../../../plugins/core' → source-repo/plugins/core
# The package.json exports map ./plugins/core → ./dist/cjs/index.js
echo "[INFO] Creating plugins/ stub files..."
mkdir -p plugins/core plugins/utils plugins/storage-dexie plugins/local-documents
echo "module.exports = require('../../dist/cjs/index.js');" > plugins/core/index.js
echo "module.exports = require('../../dist/cjs/plugins/utils/index.js');" > plugins/utils/index.js
echo "module.exports = require('../../dist/cjs/plugins/storage-dexie/index.js');" > plugins/storage-dexie/index.js
echo "module.exports = require('../../dist/cjs/plugins/local-documents/index.js');" > plugins/local-documents/index.js

# --- Navigate to docs-src and install dependencies ---
cd docs-src
echo "[INFO] Installing docs-src dependencies..."
npm install

# --- Apply fixes.json if present ---
FIXES_JSON="$SCRIPT_DIR/fixes.json"
if [ -f "$FIXES_JSON" ]; then
    echo "[INFO] Applying content fixes..."
    node -e "
    const fs = require('fs');
    const path = require('path');
    const fixes = JSON.parse(fs.readFileSync('$FIXES_JSON', 'utf8'));
    for (const [file, ops] of Object.entries(fixes.fixes || {})) {
        if (!fs.existsSync(file)) { console.log('  skip (not found):', file); continue; }
        let content = fs.readFileSync(file, 'utf8');
        for (const op of ops) {
            if (op.type === 'replace' && content.includes(op.find)) {
                content = content.split(op.find).join(op.replace || '');
                console.log('  fixed:', file, '-', op.comment || '');
            }
        }
        fs.writeFileSync(file, content);
    }
    for (const [file, cfg] of Object.entries(fixes.newFiles || {})) {
        const c = typeof cfg === 'string' ? cfg : cfg.content;
        fs.mkdirSync(path.dirname(file), {recursive: true});
        fs.writeFileSync(file, c);
        console.log('  created:', file);
    }
    "
fi

echo "[DONE] Repository is ready for docusaurus commands."
