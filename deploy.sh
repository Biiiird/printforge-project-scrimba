#!/usr/bin/env bash
# Redeploy PrintForge. Run from the repo root on the dev machine.
#   ./deploy.sh
set -euo pipefail

SSH_KEY="${SSH_KEY:-$HOME/.ssh/printforge_deploy}"
SSH_USER="${SSH_USER:-albert}"
SSH_HOST="${SSH_HOST:-13.63.230.109}"
APP_DIR="${APP_DIR:-/opt/printforge}"
PORT="${PORT:-3001}"
DOMAIN="${DOMAIN:-printforge.soloalbert.com}"

SSH=(ssh -i "$SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$SSH_USER@$SSH_HOST")

echo "==> 1/4 sync source -> $SSH_HOST:$APP_DIR"
# Excluded paths are also protected from --delete.
# printforge.db is NEVER synced: it is seeded server-side and its ownership
# (albert:printforge) must survive. --no-perms stops rsync rewriting the
# destination dir mode, which would strip the setgid bit.
rsync -a --delete --no-o --no-g --no-perms \
  --exclude node_modules --exclude .next --exclude .git --exclude printforge_mockup \
  --exclude printforge.db \
  -e "ssh -i $SSH_KEY -o BatchMode=yes -o StrictHostKeyChecking=accept-new" \
  ./ "$SSH_USER@$SSH_HOST:$APP_DIR/"

echo "==> 2/4 install deps, seed DB, build"
# The service runs as user 'printforge' and writes runtime caches into .next
# (.next/cache/images, favicon.ico.body) owned printforge:printforge mode 644.
# The deploy user cannot overwrite those, so .next is wiped and rebuilt clean:
# build artifacts belong to the deployer, runtime cache is disposable.
# The service is stopped first so it never serves a half-written .next.
# Downtime is only the stop/swap/start (a few seconds), not the whole build.
"${SSH[@]}" bash -se <<REMOTE
set -euo pipefail
cd "$APP_DIR"
npm install --no-audit --fund=false
npx tsx lib/seeds/seed_models.ts
npx tsx lib/seeds/seed_categories.ts
# Build into a staging dir while the old version keeps serving, so a failed
# build never takes the site down. Only swap once the build has succeeded.
rm -rf "$APP_DIR/.next-staging"
NEXT_DIST_DIR=.next-staging npm run build
# Build succeeded: now take the brief outage to swap it in.
sudo -n systemctl stop printforge
rm -rf "$APP_DIR/.next"
mv "$APP_DIR/.next-staging" "$APP_DIR/.next"
# The DB is seeded in place (CREATE TABLE IF NOT EXISTS + INSERT OR REPLACE),
# so the file is never recreated and keeps its albert:printforge ownership.
REMOTE

echo "==> 3/4 start service"
# systemd reports 'active' before Next binds the socket, so poll HTTP instead
"${SSH[@]}" bash -se <<REMOTE
set -euo pipefail
sudo -n systemctl start printforge
for i in \$(seq 1 30); do
  curl -sf -o /dev/null "http://127.0.0.1:$PORT/" && { echo "    app ready after \${i}s"; exit 0; }
  sleep 1
done
echo "    app did not come up:"; journalctl -u printforge -n 30 --no-pager; exit 1
REMOTE

echo "==> 4/4 verify through nginx"
fail=0
for p in / /about /3d-models /3d-models/1 "/3d-models/categories/functional"; do
  code=$(curl -sS -o /dev/null -w '%{http_code}' "https://$DOMAIN$p")
  printf '    %3s  %s\n' "$code" "$p"
  [[ "$code" == "200" ]] || fail=1
done
[[ $fail -eq 0 ]] && echo "==> DEPLOY OK" || { echo "==> DEPLOY FAILED"; exit 1; }
