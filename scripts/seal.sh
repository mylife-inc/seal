#!/usr/bin/env bash
# seal — the CodeSeal operator command.
#
# Installed by scripts/install.sh as a `seal` launcher on PATH that
# execs this file from $CODESEAL/scripts/seal.sh. Works equally well
# from a full source checkout (scripts/seal.sh next to compose
# files + infra/).
#
# Subcommands:
#   seal up                      Start the whole stack locally (docker compose)
#   seal down [-v]               Stop the stack (-v also deletes volumes/data)
#   seal logs [service…]         Tail stack logs (default: portal worker)
#   seal status                  Show container status
#   seal env [path]              Generate a .env with random secrets
#   seal deploy <platform> […]   Deploy the stack to a cloud platform
#   seal update                  Re-download infra/ + scripts/ into $CODESEAL
#   seal version                 Show seal home, compose file, sgit version
#   seal help                    This help
#
# Deploy platforms:
#   railway [workspace]   Full stack via infra/deploy/railway/rail.sh
#   fly                   Full stack via infra/deploy/fly/deploy-fly.sh
#   render                Prints Render Blueprint instructions
#   aws                   Terraform scaffold (infra/deploy/terraform/aws)
#   vercel                Prints the "not a fit" notice
#   cloudrun | digitalocean | apprunner
#                         Single-image portal deploys via app.sh helpers
#
# Layout expectations (created by install.sh, or a source checkout):
#   $SEAL_HOME/
#   ├── compose.standalone.yml   (pull-based stack; install.sh path)
#   ├── compose.yml              (build-based stack; source-checkout path)
#   ├── .env                     (created on first `seal up` via `seal env`)
#   ├── scripts/  (app.sh, seal.sh, create-env.sh, install.sh, …)
#   └── infra/deploy/  (railway/, fly/, render/, terraform/, vercel/)
set -euo pipefail

# ── Resolve the seal home ────────────────────────────────────────────
# Priority: $CODESEAL (set by install.sh in your shell profile),
# else the parent of this script's directory (source checkout).
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEAL_HOME="${CODESEAL:-$(dirname "$SELF_DIR")}"

# Pick the compose file: a source checkout has compose.yml (built
# from source, needs the full tree); an install.sh home has only
# compose.standalone.yml (pulls GHCR images). Prefer standalone when
# both exist UNLESS the caller forces otherwise — the standalone
# stack is what `seal` is for; developers hacking on CodeSeal itself
# use `source scripts/app.sh && deploy_portal_local`.
compose_file() {
  if [ -n "${SEAL_COMPOSE_FILE:-}" ]; then
    printf '%s\n' "$SEAL_COMPOSE_FILE"
  elif [ -f "$SEAL_HOME/compose.standalone.yml" ]; then
    printf '%s\n' "$SEAL_HOME/compose.standalone.yml"
  elif [ -f "$SEAL_HOME/compose.yml" ]; then
    printf '%s\n' "$SEAL_HOME/compose.yml"
  else
    return 1
  fi
}

need() { command -v "$1" >/dev/null 2>&1 || { echo "seal: missing required command: $1" >&2; exit 1; }; }

need_compose() {
  need docker
  docker compose version >/dev/null 2>&1 || {
    echo "seal: 'docker compose' (v2) not available. Install Docker Desktop or docker-compose-plugin." >&2
    exit 1
  }
}

ensure_env() {
  if [ ! -f "$SEAL_HOME/.env" ]; then
    echo "seal: no .env in $SEAL_HOME — generating one with random secrets…"
    "$SEAL_HOME/scripts/create-env.sh" "$SEAL_HOME/.env"
  fi
}

cmd_up() {
  need_compose
  local cf
  cf="$(compose_file)" || {
    echo "seal: no compose file found in $SEAL_HOME." >&2
    echo "  Run 'seal update' to (re)download the CodeSeal assets." >&2
    exit 1
  }
  ensure_env
  echo "seal: starting stack from $cf"
  (cd "$SEAL_HOME" && docker compose -f "$cf" up -d "$@")
  echo
  echo "Portal:  http://localhost:${PORTAL_PORT:-3000}"
  echo "Logs:    seal logs"
  echo "Stop:    seal down"
  if grep -q '^BOOTSTRAP_ADMIN_PASSWORD=' "$SEAL_HOME/.env" 2>/dev/null; then
    echo
    echo "First login (remove BOOTSTRAP_* from .env afterwards):"
    grep '^BOOTSTRAP_ADMIN_EMAIL=\|^BOOTSTRAP_ADMIN_PASSWORD=' "$SEAL_HOME/.env" | sed 's/^/  /'
  fi
}

cmd_down() {
  need_compose
  local cf
  cf="$(compose_file)" || { echo "seal: no compose file in $SEAL_HOME." >&2; exit 1; }
  (cd "$SEAL_HOME" && docker compose -f "$cf" down "$@")
}

cmd_logs() {
  need_compose
  local cf
  cf="$(compose_file)" || { echo "seal: no compose file in $SEAL_HOME." >&2; exit 1; }
  local -a services=("$@")
  [ ${#services[@]} -gt 0 ] || services=(portal worker)
  (cd "$SEAL_HOME" && docker compose -f "$cf" logs -f "${services[@]}")
}

cmd_status() {
  need_compose
  local cf
  cf="$(compose_file)" || { echo "seal: no compose file in $SEAL_HOME." >&2; exit 1; }
  (cd "$SEAL_HOME" && docker compose -f "$cf" ps)
}

cmd_env() {
  "$SEAL_HOME/scripts/create-env.sh" "${1:-$SEAL_HOME/.env}"
}

# Source app.sh lazily — only deploy subcommands need its helpers,
# and sourcing mutates the shell namespace (functions, env exports).
_load_app_sh() {
  # shellcheck disable=SC1091
  CODESEAL_QUIET=1 . "$SEAL_HOME/scripts/app.sh"
}

cmd_deploy() {
  local platform="${1:-}"
  shift || true
  case "$platform" in
    railway)
      # Optional positional workspace, else env var must be set.
      if [ -n "${1:-}" ] && [[ "${1}" != --* ]]; then
        export RAILWAY_WORKSPACE="$1"
        shift
      fi
      ensure_env
      ENV_FILE="$SEAL_HOME/.env" exec "$SEAL_HOME/infra/deploy/railway/rail.sh" --env-file "$SEAL_HOME/.env" "$@"
      ;;
    fly)
      ensure_env
      ENV_FILE="$SEAL_HOME/.env" exec "$SEAL_HOME/infra/deploy/fly/deploy-fly.sh" "$@"
      ;;
    render)
      echo "Render deploys via Blueprint import — no CLI bootstrap."
      echo "  Blueprint: $SEAL_HOME/infra/deploy/render/render.yaml"
      echo "  Dashboard → Blueprints → New Blueprint Instance → paste/upload it."
      ;;
    aws)
      need terraform
      (cd "$SEAL_HOME/infra/deploy/terraform/aws" && terraform init && terraform apply)
      ;;
    vercel)
      exec "$SEAL_HOME/infra/deploy/vercel/deploy-vercel-portal.sh" "$@"
      ;;
    cloudrun)
      _load_app_sh
      deploy_cloud_run "$@"
      ;;
    digitalocean)
      _load_app_sh
      deploy_digitalocean "$@"
      ;;
    apprunner)
      _load_app_sh
      deploy_aws_apprunner "$@"
      ;;
    *)
      echo "Usage: seal deploy {railway [workspace]|fly|render|aws|vercel|cloudrun|digitalocean|apprunner}" >&2
      exit 1
      ;;
  esac
}

cmd_update() {
  need curl
  need tar
  local repo="${CODESEAL_GH_REPO:-mylife-inc/CodeSeal}"
  local ref="${CODESEAL_GH_REF:-main}"
  local tmp
  tmp="$(mktemp -d -t seal-update)" || exit 1
  trap 'rm -rf "$tmp"' EXIT
  echo "seal: downloading $repo@$ref …"
  curl -fsSL "https://github.com/${repo}/archive/refs/heads/${ref}.tar.gz" -o "$tmp/src.tar.gz" || {
    echo "seal: download failed. Private repo? Clone it instead and set CODESEAL to the checkout." >&2
    exit 1
  }
  tar -xzf "$tmp/src.tar.gz" -C "$tmp"
  local srcdir
  srcdir="$(find "$tmp" -maxdepth 1 -type d -name "*-${ref}" | head -1)"
  [ -n "$srcdir" ] || { echo "seal: unexpected tarball layout." >&2; exit 1; }
  mkdir -p "$SEAL_HOME"
  rm -rf "$SEAL_HOME/scripts" "$SEAL_HOME/infra"
  cp -R "$srcdir/scripts" "$SEAL_HOME/scripts"
  cp -R "$srcdir/infra"   "$SEAL_HOME/infra"
  cp "$srcdir/compose.standalone.yml" "$SEAL_HOME/compose.standalone.yml"
  [ -f "$srcdir/.env.example" ] && cp "$srcdir/.env.example" "$SEAL_HOME/.env.example"
  chmod +x "$SEAL_HOME"/scripts/*.sh "$SEAL_HOME"/infra/deploy/deploy.sh \
           "$SEAL_HOME"/infra/deploy/*/*.sh 2>/dev/null || true
  echo "seal: updated $SEAL_HOME (scripts/, infra/, compose.standalone.yml)"
}

cmd_version() {
  echo "seal home:    $SEAL_HOME"
  echo "compose file: $(compose_file 2>/dev/null || echo '<none — run seal update>')"
  if command -v sgit >/dev/null 2>&1; then
    echo "sgit:         $(sgit --version 2>/dev/null | head -1)"
  else
    echo "sgit:         not installed (run scripts/install.sh)"
  fi
}

cmd_help() {
  sed -n '2,36p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

main() {
  local cmd="${1:-help}"
  shift || true
  case "$cmd" in
    up)       cmd_up "$@" ;;
    down)     cmd_down "$@" ;;
    logs)     cmd_logs "$@" ;;
    status|ps) cmd_status "$@" ;;
    env)      cmd_env "$@" ;;
    deploy)   cmd_deploy "$@" ;;
    update)   cmd_update "$@" ;;
    version|--version|-v) cmd_version ;;
    help|--help|-h) cmd_help ;;
    *)
      echo "seal: unknown command '$cmd'" >&2
      cmd_help >&2
      exit 1
      ;;
  esac
}

main "$@"
