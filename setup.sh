#!/usr/bin/env bash
# Portable InvenTree QA stack bootstrap.
# Boots the compose stack, restores the seeded Postgres dump + media files
# on first run, and leaves you with a ready-to-test InvenTree at the URL
# configured in .env (default: http://inventree.localhost).
#
# Re-running is safe: the script detects an existing DB and skips restore.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -f .env ]]; then
  echo "[setup] .env not found — copying .env.example"
  cp .env.example .env
fi

# shellcheck disable=SC1091
set -a; source .env; set +a

DC="docker compose"
if ! docker compose version >/dev/null 2>&1; then
  DC="docker-compose"
fi

SUDO=""
if ! docker ps >/dev/null 2>&1; then
  SUDO="sudo"
fi

echo "[setup] starting inventree-db"
$SUDO $DC up -d inventree-db

echo "[setup] waiting for postgres to accept connections"
for i in {1..60}; do
  if $SUDO $DC exec -T inventree-db pg_isready -U "$INVENTREE_DB_USER" -d "$INVENTREE_DB_NAME" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

SEEDED=$($SUDO $DC exec -T inventree-db psql -U "$INVENTREE_DB_USER" -d "$INVENTREE_DB_NAME" -tAc \
  "SELECT 1 FROM information_schema.tables WHERE table_name='part_part' LIMIT 1" 2>/dev/null || echo "")

if [[ "$SEEDED" == "1" ]]; then
  echo "[setup] DB already has part_part — skipping seed restore"
else
  echo "[setup] restoring seed/inventree-seed.sql.gz into $INVENTREE_DB_NAME"
  gunzip -c seed/inventree-seed.sql.gz | $SUDO $DC exec -T inventree-db psql -U "$INVENTREE_DB_USER" -d "$INVENTREE_DB_NAME" >/dev/null
fi

echo "[setup] starting remaining services"
$SUDO $DC up -d

echo "[setup] waiting for inventree-server to come up"
for i in {1..90}; do
  if $SUDO $DC exec -T inventree-server test -d /home/inventree/data 2>/dev/null; then
    break
  fi
  sleep 2
done

if [[ ! -f seed/.media-restored ]]; then
  echo "[setup] restoring media files"
  $SUDO $DC exec -T inventree-server sh -c "rm -rf /home/inventree/data/media && mkdir -p /home/inventree/data"
  $SUDO $DC exec -T inventree-server tar xzf - -C /home/inventree/data < seed/inventree-media.tar.gz
  touch seed/.media-restored
else
  echo "[setup] media already restored (seed/.media-restored exists)"
fi

if [[ ! -f seed/.static-restored ]]; then
  echo "[setup] restoring static files (web frontend + admin + rest_framework)"
  $SUDO $DC exec -T inventree-server sh -c "rm -rf /home/inventree/data/static && mkdir -p /home/inventree/data"
  $SUDO $DC exec -T inventree-server tar xzf - -C /home/inventree/data < seed/inventree-static.tar.gz
  touch seed/.static-restored
  echo "[setup] restarting inventree-proxy to pick up restored static files"
  $SUDO $DC restart inventree-proxy
else
  echo "[setup] static already restored (seed/.static-restored exists)"
fi

echo ""
echo "[setup] done. InvenTree is starting at: ${INVENTREE_SITE_URL}"
echo "[setup] admin login: ${INVENTREE_ADMIN_USER} / ${INVENTREE_ADMIN_PASSWORD}"
echo "[setup] first boot may take ~60s while migrations finish."
