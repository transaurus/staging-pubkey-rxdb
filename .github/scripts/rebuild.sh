#!/usr/bin/env bash
set -euo pipefail

# Rebuild script for pubkey/rxdb
# Runs from docs-src/ in the existing source tree (no clone).
# docs-src/src/components/ imports '../../../' (rxdb root) and '../../../plugins/core'.
# Since the staging repo is a snapshot of docs-src, the rxdb root is not present.
# We clone rxdb to a temp dir, build it, then copy translated content there to build.

REPO_URL="https://github.com/pubkey/rxdb"
BRANCH="master"
ORIGINAL_DIR="$(pwd)"

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

# --- Clone rxdb source for root-level deps (needed for babel build and plugin stubs) ---
TEMP_DIR="/tmp/rxdb-rebuild-$$"
echo "[INFO] Cloning rxdb to $TEMP_DIR for root deps..."
git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$TEMP_DIR"

# --- Install root rxdb dependencies ---
echo "[INFO] Installing root rxdb dependencies..."
cd "$TEMP_DIR"
npm install --ignore-scripts

# --- Build rxdb to dist/cjs/ using babel ---
echo "[INFO] Building rxdb CJS (babel compile)..."
NODE_ENV=es5 ./node_modules/.bin/babel src --out-dir dist/cjs --extensions .ts --copy-files

# --- Create plugins/ stub directory ---
echo "[INFO] Creating plugins/ stub files..."
mkdir -p plugins/core plugins/utils plugins/storage-dexie plugins/local-documents
echo "module.exports = require('../../dist/cjs/index.js');" > plugins/core/index.js
echo "module.exports = require('../../dist/cjs/plugins/utils/index.js');" > plugins/utils/index.js
echo "module.exports = require('../../dist/cjs/plugins/storage-dexie/index.js');" > plugins/storage-dexie/index.js
echo "module.exports = require('../../dist/cjs/plugins/local-documents/index.js');" > plugins/local-documents/index.js

# --- Copy translated docs-src content into the temp rxdb tree ---
# This ensures '../../../' relative imports from src/components/ resolve to rxdb root
echo "[INFO] Copying translated content into temp rxdb tree..."
rsync -a --delete \
    --exclude='node_modules' \
    --exclude='build' \
    --exclude='.git' \
    "$ORIGINAL_DIR/" "$TEMP_DIR/docs-src/"

# --- Install docs-src dependencies ---
cd "$TEMP_DIR/docs-src"
echo "[INFO] Installing docs-src dependencies..."
npm install

# --- Build Docusaurus site ---
echo "[INFO] Building Docusaurus site..."
npm run build

# --- Copy build output back to original directory ---
echo "[INFO] Copying build output back..."
cp -r "$TEMP_DIR/docs-src/build" "$ORIGINAL_DIR/"

# --- Cleanup ---
rm -rf "$TEMP_DIR"

echo "[DONE] Build complete."
