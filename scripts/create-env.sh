#!/usr/bin/env bash
set -euo pipefail

OUT_FILE="${1:-.env}"
ADMIN_EMAIL="${BOOTSTRAP_ADMIN_EMAIL:-admin@example.com}"
CODESEAL_VERSION="${CODESEAL_VERSION:-latest}"
PUBLIC_URL="${CODESEAL_PUBLIC_URL:-http://localhost:3000}"

if [[ -e "$OUT_FILE" && "${FORCE:-}" != "1" ]]; then
  echo "Refusing to overwrite existing $OUT_FILE. Set FORCE=1 to overwrite." >&2
  exit 1
fi

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }; }
need openssl

cat > "$OUT_FILE" <<EOF2
CODESEAL_VERSION=$CODESEAL_VERSION
PORTAL_PORT=3000

POSTGRES_PASSWORD=$(openssl rand -hex 32)
REDIS_PASSWORD=$(openssl rand -hex 32)
SESSION_SECRET=$(openssl rand -hex 64)
ENCRYPTION_PEPPER=$(openssl rand -hex 64)
CODESEAL_WORKER_SECRET=$(openssl rand -hex 32)
INVITATION_TOKEN_SECRET=$(openssl rand -hex 32)

CODESEAL_PUBLIC_URL=$PUBLIC_URL
OPEN_SIGN_UP=false
DEFAULT_INVITATION_TTL_HOURS=168
LOG_LEVEL=info

BOOTSTRAP_ADMIN_EMAIL=$ADMIN_EMAIL
BOOTSTRAP_ADMIN_PASSWORD=$(openssl rand -hex 16)
EOF2

chmod 600 "$OUT_FILE"
echo "Created $OUT_FILE"
echo "Save this bootstrap password now:"
grep '^BOOTSTRAP_ADMIN_PASSWORD=' "$OUT_FILE"
echo "After first successful admin login, remove BOOTSTRAP_ADMIN_EMAIL and BOOTSTRAP_ADMIN_PASSWORD from production service variables."
