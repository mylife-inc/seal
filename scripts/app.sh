# Source this file once from the repository root:
#   source app.sh
#
# Then use:
#   build
#   image
#   start
#   run_image
#   site_build
#   docs_build
#   deploy netlify
#   undeploy netlify

# Clear stale versions if this file is re-sourced in the same shell.
unalias help --help build image start run_image downloads site_build site_deps docs_build deploy undeploy clean_app code_seal_status release docker_push_portal docker_push_worker deploy_railway deploy_cloud_run deploy_digitalocean deploy_aws_apprunner deploy_portal_local 2>/dev/null || true
unset -f code_seal_help help --help command_exists build binaries_exist ensure_binaries downloads site_deps site_build image image_exists ensure_image netlify_cli ensure_netlify_login netlify_site_lookup ensure_netlify_site link_netlify_site deploy deploy_help deploy_netlify undeploy undeploy_help confirm_undeploy_netlify undeploy_netlify run_image start docs_build clean_app code_seal_status release release_help _release_validate_version _release_bump_cargo _release_assert_clean docker_push_portal docker_push_portal_help docker_push_worker docker_push_worker_help _ghcr_login_check deploy_railway deploy_railway_help deploy_cloud_run deploy_cloud_run_help deploy_digitalocean deploy_digitalocean_help deploy_aws_apprunner deploy_aws_apprunner_help deploy_portal_local deploy_portal_local_help _portal_image_ref 2>/dev/null || true

if [ -n "${BASH_SOURCE:-}" ]; then
  _codeseal_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elif [ -n "${ZSH_EVAL_CONTEXT:-}" ]; then
  _codeseal_self_dir="$(cd "$(dirname "${(%):-%x}")" && pwd)"
else
  _codeseal_self_dir="$(pwd)"
fi
# This file lives in scripts/ — CODESEAL_ROOT is its parent (the
# repo root, or $CODESEAL when installed by install.sh). Every
# derived path (cli/, compose.yml, infra/, docs/) hangs off the
# root, not off scripts/.
case "$(basename "$_codeseal_self_dir")" in
  scripts) CODESEAL_ROOT="$(dirname "$_codeseal_self_dir")" ;;
  *)       CODESEAL_ROOT="$_codeseal_self_dir" ;;
esac
unset _codeseal_self_dir

export CODESEAL_SITE_DIR="${CODESEAL_SITE_DIR:-"$CODESEAL_ROOT/docs/website"}"
export CODESEAL_DOCS_CONFIG="${CODESEAL_DOCS_CONFIG:-"$CODESEAL_ROOT/docs/code-seal/mkdocs.yml"}"
export CODESEAL_IMAGE_NAME="${CODESEAL_IMAGE_NAME:-codeseal}"
export CODESEAL_IMAGE_TAG="${CODESEAL_IMAGE_TAG:-latest}"
export CODE_SEAL_URL="${CODE_SEAL_URL:-https://codeseal.netlify.app}"
export CODESEAL_NETLIFY_SITE="${CODESEAL_NETLIFY_SITE:-codeseal}"
export CODESEAL_NETLIFY_DOMAIN="${CODESEAL_NETLIFY_DOMAIN:-codeseal.netlify.app}"
export CODESEAL_NETLIFY_ACCOUNT_SLUG="${CODESEAL_NETLIFY_ACCOUNT_SLUG:-}"
export CODESEAL_HOST_PORT="${CODESEAL_HOST_PORT:-}"
export CODESEAL_CONTAINER_PORT="${CODESEAL_CONTAINER_PORT:-5000}"

# `release` / `docker_push_portal` knobs.
#
#   CODESEAL_GH_REPO         Coordinates used to build URLs printed
#                            after `release` succeeds. Cosmetic only —
#                            doesn't change what gets pushed.
#   CODESEAL_PORTAL_IMAGE    Image ref pushed by `docker_push_portal`.
#                            Defaults to GHCR under your org.
#   CODESEAL_PORTAL_DOCKERFILE / CODESEAL_PORTAL_CONTEXT
#                            Build inputs for the portal image.
#   CODESEAL_PORTAL_PLATFORMS
#                            Comma-separated platforms for buildx
#                            multi-arch push. Default: linux/amd64,linux/arm64.
#                            Set to a single platform (e.g. linux/amd64)
#                            to skip arm64 cross-build.
export CODESEAL_GH_REPO="${CODESEAL_GH_REPO:-mylife-inc/CodeSeal}"
# Where the binaries are published. CodeSeal's own repository is private, and a
# private repository's release assets need a token to download — which makes a
# `curl … | sh` installer impossible. So artefacts go to a public repository
# that holds them for several products, tag-scoped by product.
export CODESEAL_RELEASES_REPO="${CODESEAL_RELEASES_REPO:-mylife-inc/releases}"
export CODESEAL_RELEASE_SCOPE="${CODESEAL_RELEASE_SCOPE:-codeseal}"
export CODESEAL_PORTAL_IMAGE="${CODESEAL_PORTAL_IMAGE:-ghcr.io/mylife-inc/codeseal-portal}"
export CODESEAL_PORTAL_DOCKERFILE="${CODESEAL_PORTAL_DOCKERFILE:-$CODESEAL_ROOT/infra/docker/portal/Dockerfile}"
export CODESEAL_PORTAL_CONTEXT="${CODESEAL_PORTAL_CONTEXT:-$CODESEAL_ROOT}"
export CODESEAL_PORTAL_PLATFORMS="${CODESEAL_PORTAL_PLATFORMS:-linux/amd64,linux/arm64}"

# Cloud deployment defaults. Override per-tenant before sourcing.
#
#   CODESEAL_PORTAL_DOMAIN  Hostname the Portal will be served at.
#                           Used by the cloud deployers to set the
#                           public URL the CLI registers against.
#   CODESEAL_DEPLOY_REGION  Cloud-specific region (e.g. us-east-1,
#                           us-central1, nyc3). Each deployer picks
#                           a sensible default per provider.
#   CODESEAL_DEPLOY_APP     App / service name to create or update.
export CODESEAL_PORTAL_DOMAIN="${CODESEAL_PORTAL_DOMAIN:-}"
export CODESEAL_DEPLOY_REGION="${CODESEAL_DEPLOY_REGION:-}"
export CODESEAL_DEPLOY_APP="${CODESEAL_DEPLOY_APP:-codeseal-portal}"

code_seal_help() {
  cat <<EOF
CodeSeal commands loaded from app.sh:

  help               Show this help
  --help             Show this help
  start [port]       Rebuild the SPA image and run it (no binary builds)
  build              Build sgit binaries into target/dist-binaries/{macos,linux,windows}
                     (local testing only — slow cross-builds; releases come from CI)
  ensure_binaries    Build binaries only when one or more platform binaries are missing
  site_deps          Install SPA dependencies with npm ci
  site_build         Build the SPA in docs/site
  image              Build the website Docker image from docs/site/Dockerfile
  run_image [port]   Run the Docker image locally; auto-picks a free host port
  run_image --dry-run
  deploy netlify     Build missing assets/image and deploy docs/site/dist to Netlify
  undeploy netlify   Permanently delete the Netlify project after confirmation
  docs_build         Build MkDocs documentation
  clean_app          Remove generated SPA dist and downloadable binaries
  code_seal_status   Show key paths and generated outputs

  release <version>          Cut a sgit release. Bumps cli/Cargo.toml,
                             commits, creates an annotated tag (v<version>),
                             pushes both, triggers cli-release.yml on GitHub.
  docker_push_portal [tag]   Build + push the portal + portal-migrate images
                             to GHCR. Tags with the given tag (default:
                             latest), or both v<version> + latest for semver.
  docker_push_worker [tag]   Build + push the worker image to GHCR. Run both
                             push commands when cutting a release — the
                             standalone compose stack pulls all three images.

  deploy_portal_local        Run the Portal locally via docker compose (repo-root compose.yml; needs .env).
  deploy_railway [tag]       Deploy portal:<tag> to Railway. Needs railway CLI logged in.
  deploy_cloud_run [tag]     Deploy portal:<tag> to Google Cloud Run. Needs gcloud auth.
  deploy_digitalocean [tag]  Deploy portal:<tag> to DigitalOcean App Platform. Needs doctl auth.
  deploy_aws_apprunner [tag] Deploy portal:<tag> to AWS App Runner. Needs aws CLI configured.

Environment overrides:

  CODESEAL_IMAGE_NAME=codeseal
  CODESEAL_IMAGE_TAG=latest
  CODE_SEAL_URL=https://codeseal.netlify.app
  CODESEAL_NETLIFY_SITE=codeseal        Netlify project name or site ID
  CODESEAL_NETLIFY_DOMAIN=codeseal.netlify.app
  CODESEAL_NETLIFY_ACCOUNT_SLUG=...     Optional Netlify team slug
  CODESEAL_UNDEPLOY_CONFIRM=...         Set to DELETE codeseal.netlify.app to skip prompt
  CODESEAL_HOST_PORT=5050
  CODESEAL_CONTAINER_PORT=5000
  NETLIFY_AUTH_TOKEN=...                Optional non-interactive Netlify auth
  SKIP_DOCKER=1      Build only the host macOS sgit binary

  CODESEAL_GH_REPO=mylife-inc/CodeSeal
  CODESEAL_PORTAL_IMAGE=ghcr.io/mylife-inc/codeseal-portal
  CODESEAL_PORTAL_DOCKERFILE=...        Path to portal Dockerfile (default infra/docker/portal/Dockerfile)
  CODESEAL_PORTAL_CONTEXT=...           Build context (default: repo root)
  CODESEAL_PORTAL_PLATFORMS=linux/amd64,linux/arm64
  CODESEAL_GHCR_TOKEN=...               PAT (classic, write:packages) or GH_TOKEN
                                        used for `docker login ghcr.io` if you
                                        aren't already logged in.
  CODESEAL_GHCR_USER=...                GitHub username (defaults to $USER).

Examples:

  start
  start 5050
  CODESEAL_HOST_PORT=5050 start
  deploy netlify
  undeploy netlify

  release 1.0.0                          # tag → push → CI builds 5 binaries
  docker_push_portal v1.0.0              # build + push portal:v1.0.0 + :latest
  docker_push_portal                     # push portal:latest only
  CODESEAL_PORTAL_PLATFORMS=linux/amd64 docker_push_portal v1.0.0  # skip arm64
EOF
}

help() {
  code_seal_help
}

--help() {
  code_seal_help
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

build() {
  bash "$CODESEAL_ROOT/scripts/build.sh" "$@"
}

binaries_exist() {
  [ -f "$CODESEAL_ROOT/target/dist-binaries/macos/sgit" ] &&
    [ -f "$CODESEAL_ROOT/target/dist-binaries/linux/sgit" ] &&
    [ -f "$CODESEAL_ROOT/target/dist-binaries/windows/sgit.exe" ]
}

port_is_busy() {
  local port="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -s --max-time 1 "http://127.0.0.1:$port/" >/dev/null 2>&1
    if [ "$?" = "0" ]; then
      return 0
    fi
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$port" <<'PY'
import socket
import sys

port = int(sys.argv[1])
with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.settimeout(0.5)
    sys.exit(0 if sock.connect_ex(("127.0.0.1", port)) == 0 else 1)
PY
    return $?
  fi
  if command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
    return $?
  fi
  if command -v nc >/dev/null 2>&1; then
    nc -z 127.0.0.1 "$port" >/dev/null 2>&1
    return $?
  fi
  return 1
}

find_free_port() {
  local port="${1:-5050}"
  while port_is_busy "$port"; do
    port=$((port + 1))
  done
  echo "$port"
}

ensure_binaries() {
  if binaries_exist; then
    echo "sgit binaries already exist under target/dist-binaries; skipping binary build."
  else
    echo "One or more sgit binaries are missing; building release binaries."
    build
  fi
}

site_deps() {
  (cd "$CODESEAL_SITE_DIR" && npm ci)
}

site_build() {
  (cd "$CODESEAL_SITE_DIR" && CODE_SEAL_URL="$CODE_SEAL_URL" npm run build)
}

image() {
  docker build \
      --build-arg CODE_SEAL_URL="$CODE_SEAL_URL" \
      -t "$CODESEAL_IMAGE_NAME:$CODESEAL_IMAGE_TAG" \
      "$CODESEAL_SITE_DIR"
}

image_exists() {
  command_exists docker &&
    docker image inspect "$CODESEAL_IMAGE_NAME:$CODESEAL_IMAGE_TAG" >/dev/null 2>&1
}

ensure_image() {
  if image_exists; then
    echo "Docker image $CODESEAL_IMAGE_NAME:$CODESEAL_IMAGE_TAG already exists; skipping image build."
  else
    echo "Docker image $CODESEAL_IMAGE_NAME:$CODESEAL_IMAGE_TAG is missing; building it."
    image
  fi
}

netlify_cli() {
  if command_exists netlify; then
    command netlify "$@"
  elif command_exists npx; then
    command npx --yes netlify-cli "$@"
  else
    echo "Netlify CLI is required. Install it or make npx available." >&2
    return 1
  fi
}

ensure_netlify_login() {
  if [ -n "${NETLIFY_AUTH_TOKEN:-}" ]; then
    echo "NETLIFY_AUTH_TOKEN is set; skipping interactive Netlify login."
    return 0
  fi
  if netlify_cli status >/dev/null 2>&1; then
    echo "Netlify CLI is already logged in."
  else
    echo "Opening Netlify login..."
    netlify_cli login
  fi
}

netlify_site_lookup() {
  if ! command_exists node; then
    echo "Node.js is required to parse Netlify site data." >&2
    return 1
  fi

  local sites_json
  if ! sites_json="$(netlify_cli sites:list --json 2>/dev/null)"; then
    return 1
  fi

  NETLIFY_SITES_JSON="$sites_json" NETLIFY_SITE_KEY="$CODESEAL_NETLIFY_SITE" node -e '
const key = (process.env.NETLIFY_SITE_KEY || "").trim();
const normalize = (value) => String(value || "")
  .trim()
  .replace(/^https?:\/\//, "")
  .replace(/\/$/, "");
const payload = JSON.parse(process.env.NETLIFY_SITES_JSON || "[]");
const sites = Array.isArray(payload) ? payload : (payload.sites || payload.items || []);
const found = sites.find((site) => {
  const candidates = [
    site.id,
    site.site_id,
    site.siteId,
    site.name,
    site.slug,
    site.custom_domain,
    site.default_domain,
    site.url,
    site.ssl_url,
  ];
  return candidates.some((value) => normalize(value) === normalize(key));
});
if (!found) process.exit(1);
console.log(found.id || found.site_id || found.siteId || found.name);
'
}

ensure_netlify_site() {
  local site_ref
  if site_ref="$(netlify_site_lookup)"; then
    export CODESEAL_NETLIFY_RESOLVED_SITE="$site_ref"
    echo "Netlify project $CODESEAL_NETLIFY_SITE exists ($CODESEAL_NETLIFY_RESOLVED_SITE)."
    return 0
  fi

  echo "Netlify project $CODESEAL_NETLIFY_SITE does not exist; creating it from $CODESEAL_SITE_DIR."
  if [ -n "$CODESEAL_NETLIFY_ACCOUNT_SLUG" ]; then
    (cd "$CODESEAL_SITE_DIR" &&
      netlify_cli sites:create \
        --name "$CODESEAL_NETLIFY_SITE" \
        --account-slug "$CODESEAL_NETLIFY_ACCOUNT_SLUG")
  else
    (cd "$CODESEAL_SITE_DIR" &&
      netlify_cli sites:create \
        --name "$CODESEAL_NETLIFY_SITE")
  fi || return $?

  if site_ref="$(netlify_site_lookup)"; then
    export CODESEAL_NETLIFY_RESOLVED_SITE="$site_ref"
  else
    unset CODESEAL_NETLIFY_RESOLVED_SITE
  fi
}

link_netlify_site() {
  if [ -n "${CODESEAL_NETLIFY_RESOLVED_SITE:-}" ]; then
    echo "Linking $CODESEAL_SITE_DIR to Netlify project $CODESEAL_NETLIFY_RESOLVED_SITE."
    (cd "$CODESEAL_SITE_DIR" &&
      netlify_cli link --id "$CODESEAL_NETLIFY_RESOLVED_SITE")
  else
    echo "Linking $CODESEAL_SITE_DIR to Netlify project $CODESEAL_NETLIFY_SITE."
    (cd "$CODESEAL_SITE_DIR" &&
      netlify_cli link --name "$CODESEAL_NETLIFY_SITE")
  fi
}

deploy_help() {
  cat <<EOF
Usage:
  deploy netlify

Deploy targets:
  netlify   Log in to Netlify, create the project if needed, link docs/site,
            build missing binaries, build docs/site, ensure Docker image exists,
            then deploy docs/site/dist to production.

Netlify settings:
  CODESEAL_NETLIFY_SITE=$CODESEAL_NETLIFY_SITE
  CODESEAL_NETLIFY_DOMAIN=$CODESEAL_NETLIFY_DOMAIN
  CODESEAL_NETLIFY_ACCOUNT_SLUG=$CODESEAL_NETLIFY_ACCOUNT_SLUG

Set CODESEAL_NETLIFY_ACCOUNT_SLUG when your Netlify login has multiple teams.
EOF
}

deploy() {
  case "${1:-}" in
    netlify)
      shift
      deploy_netlify "$@"
      ;;
    "" | -h | --help)
      deploy_help
      ;;
    *)
      echo "Unknown deploy target: $1" >&2
      deploy_help >&2
      return 2
      ;;
  esac
}

deploy_netlify() {
  if [ "$#" -gt 0 ]; then
    echo "deploy netlify does not accept extra arguments: $*" >&2
    return 2
  fi

  ensure_netlify_login &&
    ensure_netlify_site &&
    link_netlify_site &&
    site_build &&
    ensure_image &&
    (cd "$CODESEAL_SITE_DIR" &&
      CODE_SEAL_URL="$CODE_SEAL_URL" netlify_cli deploy \
        --prod \
        --no-build \
        --dir dist \
        --site "${CODESEAL_NETLIFY_RESOLVED_SITE:-$CODESEAL_NETLIFY_SITE}" \
        --message "CodeSeal deploy $(date -u +%Y-%m-%dT%H:%M:%SZ)")

  local status=$?
  if [ "$status" = "0" ]; then
    echo "Netlify production deploy complete: https://$CODESEAL_NETLIFY_DOMAIN"
  fi
  return "$status"
}

undeploy_help() {
  cat <<EOF
Usage:
  undeploy netlify

This permanently deletes the Netlify project that matches:
  CODESEAL_NETLIFY_SITE=$CODESEAL_NETLIFY_SITE
  CODESEAL_NETLIFY_DOMAIN=$CODESEAL_NETLIFY_DOMAIN

Safety:
  You must type: DELETE $CODESEAL_NETLIFY_DOMAIN

For non-interactive use:
  CODESEAL_UNDEPLOY_CONFIRM="DELETE $CODESEAL_NETLIFY_DOMAIN" undeploy netlify
EOF
}

undeploy() {
  case "${1:-}" in
    netlify)
      shift
      undeploy_netlify "$@"
      ;;
    "" | -h | --help)
      undeploy_help
      ;;
    *)
      echo "Unknown undeploy target: $1" >&2
      undeploy_help >&2
      return 2
      ;;
  esac
}

confirm_undeploy_netlify() {
  local expected="DELETE $CODESEAL_NETLIFY_DOMAIN"
  if [ "${CODESEAL_UNDEPLOY_CONFIRM:-}" = "$expected" ]; then
    echo "CODESEAL_UNDEPLOY_CONFIRM matched; skipping interactive undeploy prompt."
    return 0
  fi

  if [ ! -t 0 ]; then
    echo "Refusing to delete Netlify project without interactive confirmation." >&2
    echo "Set CODESEAL_UNDEPLOY_CONFIRM=\"$expected\" to run non-interactively." >&2
    return 1
  fi

  echo "This will permanently delete Netlify project $CODESEAL_NETLIFY_SITE."
  echo "The public site https://$CODESEAL_NETLIFY_DOMAIN will stop serving this project."
  printf "Type '%s' to continue: " "$expected"
  local answer
  read -r answer
  if [ "$answer" != "$expected" ]; then
    echo "Undeploy aborted."
    return 1
  fi
}

undeploy_netlify() {
  if [ "$#" -gt 0 ]; then
    echo "undeploy netlify does not accept extra arguments: $*" >&2
    return 2
  fi

  ensure_netlify_login || return $?

  local site_ref
  if ! site_ref="$(netlify_site_lookup)"; then
    echo "Netlify project $CODESEAL_NETLIFY_SITE was not found; nothing to delete."
    return 0
  fi
  export CODESEAL_NETLIFY_RESOLVED_SITE="$site_ref"

  confirm_undeploy_netlify || return $?

  (cd "$CODESEAL_SITE_DIR" &&
    netlify_cli sites:delete "$CODESEAL_NETLIFY_RESOLVED_SITE" --force) || return $?

  rm -f "$CODESEAL_SITE_DIR/.netlify/state.json" 2>/dev/null || true
  rmdir "$CODESEAL_SITE_DIR/.netlify" 2>/dev/null || true
  unset CODESEAL_NETLIFY_RESOLVED_SITE
  echo "Netlify project deleted: $CODESEAL_NETLIFY_SITE ($site_ref)"
}

run_image() {
  local dry_run=0
  local requested_port="${1:-$CODESEAL_HOST_PORT}"
  local host_port="$requested_port"
  if [ "${1:-}" = "--dry-run" ]; then
    dry_run=1
    requested_port="$CODESEAL_HOST_PORT"
    host_port="$requested_port"
  fi
  if [ -z "$host_port" ]; then
    host_port="$(find_free_port 5050)"
  elif port_is_busy "$host_port"; then
    echo "Host port $host_port is already in use." >&2
    if [ -n "$requested_port" ]; then
      echo "Choose another port, for example: start $((host_port + 1))" >&2
      return 1
    fi
    host_port="$(find_free_port "$host_port")"
  fi
  if [ -z "$CODESEAL_CONTAINER_PORT" ]; then
    CODESEAL_CONTAINER_PORT=5000
  fi
  echo "Starting $CODESEAL_IMAGE_NAME:$CODESEAL_IMAGE_TAG at http://localhost:$host_port"
  echo "Docker command: docker run -d --name codeseal --rm -e PORT=$CODESEAL_CONTAINER_PORT -p $host_port:$CODESEAL_CONTAINER_PORT $CODESEAL_IMAGE_NAME:$CODESEAL_IMAGE_TAG"
  if [ "$dry_run" = "1" ]; then
    return 0
  fi
  command docker run -d --name codeseal --rm \
    -e PORT="$CODESEAL_CONTAINER_PORT" \
    -p "$host_port:$CODESEAL_CONTAINER_PORT" \
    "$CODESEAL_IMAGE_NAME:$CODESEAL_IMAGE_TAG"
}

start() {
  local host_port="${1:-$CODESEAL_HOST_PORT}"
  if [ -n "$host_port" ] && port_is_busy "$host_port"; then
    echo "Host port $host_port is already in use." >&2
    echo "Choose another port, for example: start $(find_free_port "$((host_port + 1))")" >&2
    return 1
  fi
  site_build &&
    image &&
    run_image "$host_port"
}

docs_build() {
  (cd "$CODESEAL_ROOT" && mkdocs build -f "$CODESEAL_DOCS_CONFIG" --strict)
}

clean_app() {
  rm -rf "$CODESEAL_SITE_DIR/dist"
}

code_seal_status() {
  cat <<EOF
CODESEAL_ROOT=$CODESEAL_ROOT
CODESEAL_SITE_DIR=$CODESEAL_SITE_DIR
CODESEAL_IMAGE=$CODESEAL_IMAGE_NAME:$CODESEAL_IMAGE_TAG
CODE_SEAL_URL=$CODE_SEAL_URL
CODESEAL_HOST_PORT=$CODESEAL_HOST_PORT
CODESEAL_CONTAINER_PORT=$CODESEAL_CONTAINER_PORT

Release outputs:
EOF
  find "$CODESEAL_ROOT/target/dist-binaries" -maxdepth 2 -type f 2>/dev/null | sort || true
}

# ─────────────────────────────────────────────────────────────────────
# Release pipeline helpers — `release` + `docker_push_portal`.
#
# `release <version>`:
#   1. Validate <version> is semver (X.Y.Z[-suffix])
#   2. Refuse a dirty working tree
#   3. Refuse if v<version> tag already exists locally or on origin
#   4. Bump cli/Cargo.toml, regenerate Cargo.lock via `cargo check`
#   5. Commit the bump
#   6. Push commits
#   7. Create annotated tag v<version> and push the tag
#   8. Print the URL to watch the cli-release.yml workflow
#
# `docker_push_portal [tag]`:
#   1. Verify `docker buildx` is available (multi-arch path)
#   2. Verify (or perform) `docker login ghcr.io`
#   3. `docker buildx build --platform $PLATFORMS --push` with the
#      portal Dockerfile and the repo root as context. The portal
#      Dockerfile expects to see `portal/` at the build context root.
#   4. When called with a semver-shaped tag, pushes both that tag
#      AND `:latest`. Pre-release tags (e.g. v1.0.0-rc.1) do NOT
#      get `:latest`, mirroring the GitHub release behavior.
# ─────────────────────────────────────────────────────────────────────

release_help() {
  cat <<'EOF'
release <version>

  Cut and publish a CodeSeal sgit release, end to end, from this repository.
  Pass the bare version, NOT the v-prefixed tag:
    release 1.0.0
    release 1.0.1-rc.1

  Checked first, so a failure costs seconds rather than minutes:
    - semver is well formed
    - working tree is clean
    - gh is installed and logged in
    - v<version> does not already exist locally or on origin
    - codeseal-v<version> is not already published

  Then, all-or-nothing:
    - cargo test
    - bump cli/Cargo.toml, regenerate Cargo.lock, commit
    - build x86_64-apple-darwin natively
    - build x86_64-unknown-linux-musl in a container
    - verify each binary reports <version> — a failed build leaves the
      PREVIOUS binary in place, and shipping it looks identical to success
    - package both, generate and check SHA256SUMS
    - package scripts/ + infra/ + compose.standalone.yml as the operator
      assets, and assert the archive contains what install.sh looks for
    - push the branch, create and push tag v<version>
    - publish codeseal-v<version> to the public artefact repository

  Binaries are built and verified BEFORE the tag is pushed. A tag pointing at
  a commit whose binaries do not build is worse than no tag.

  Override the destination with CODESEAL_RELEASES_REPO / CODESEAL_RELEASE_SCOPE.
EOF
}

_release_validate_version() {
  # Accept bare semver (X.Y.Z) with optional -SUFFIX. Reject anything else.
  local v="$1"
  case "$v" in
    v*)
      echo "release: pass the bare version WITHOUT the 'v' prefix (got '$v')." >&2
      return 1
      ;;
  esac
  if [[ ! "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9._-]+)?$ ]]; then
    echo "release: '$v' is not a valid semver (expected X.Y.Z or X.Y.Z-suffix)." >&2
    return 1
  fi
}

_release_assert_clean() {
  if [ -n "$(git -C "$CODESEAL_ROOT" status --porcelain)" ]; then
    echo "release: working tree is dirty. Commit or stash before releasing." >&2
    git -C "$CODESEAL_ROOT" status --short >&2
    return 1
  fi
}

_release_bump_cargo() {
  local v="$1"
  local manifest="$CODESEAL_ROOT/cli/Cargo.toml"
  if [ ! -f "$manifest" ]; then
    echo "release: $manifest not found." >&2
    return 1
  fi

  # Only the FIRST `version = "..."` line — that is the [package] entry, and
  # Cargo's format guarantees it precedes any [dependencies].
  local current
  current=$(awk -F'"' '/^version = "/ { print $2; exit }' "$manifest")
  if [ -z "$current" ]; then
    echo "release: couldn't read current version from $manifest." >&2
    return 1
  fi
  if [ "$current" = "$v" ]; then
    echo "release: cli/Cargo.toml is already at $v — skipping bump."
    return 0
  fi

  echo "release: bumping cli/Cargo.toml: $current → $v"

  # awk, not sed.
  #
  # This was `sed -i '' -E "0,/^version = .../s//.../"`, and `0,/re/` is a GNU
  # extension. BSD sed — which is what macOS ships — accepts it, exits 0, and
  # changes nothing. The bump announced itself, `cargo check` passed on the
  # unchanged file, the function returned success, and the build produced a
  # binary carrying the OLD version. Nothing in the chain noticed.
  #
  # awk behaves identically on both, so there is no GNU/BSD branch to get
  # wrong.
  local tmp
  tmp=$(mktemp) || return 1
  awk -v new="$v" '
    !done && /^version = "/ { sub(/"[^"]*"/, "\"" new "\""); done = 1 }
    { print }
  ' "$manifest" > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$manifest" || { rm -f "$tmp"; return 1; }

  # Read it back. A rewrite that silently did nothing is the failure this
  # function just had, and the only way to be sure is to look.
  local after
  after=$(awk -F'"' '/^version = "/ { print $2; exit }' "$manifest")
  if [ "$after" != "$v" ]; then
    echo "release: bump did not take — $manifest still reads '$after'." >&2
    return 1
  fi

  # Regenerate Cargo.lock. `cargo check` is the cheapest invocation that
  # updates the lock without a full compile.
  (cd "$CODESEAL_ROOT/cli" && cargo check --quiet) || {
    echo "release: cargo check failed after version bump." >&2
    return 1
  }
}

# Build one target and echo the path of the binary it produced.
#
# macOS builds natively. Linux builds inside a container: the host toolchain has
# no musl linker, and a cross build there dies partway through the dependency
# tree. That failure is easy to miss — piping cargo into `tail` returns tail's
# exit status, so a broken build reports success and leaves the PREVIOUS binary
# on disk. Nothing here pipes cargo anywhere, for that reason.
_release_build_target() {
  local target="$1"

  case "$target" in
    *-apple-darwin)
      echo "release: building $target natively…" >&2
      ( cd "$CODESEAL_ROOT/cli" && cargo build --release --target "$target" ) >&2 || return 1
      echo "$CODESEAL_ROOT/cli/target/$target/release/sgit"
      ;;
    x86_64-unknown-linux-musl)
      echo "release: building $target in a container…" >&2
      command_exists docker || { echo "release: docker is required to build $target" >&2; return 1; }
      docker run --rm \
        -v "$CODESEAL_ROOT/cli:/src" -w /src \
        -v "$CODESEAL_ROOT/cli/.cargo-musl:/usr/local/cargo/registry" \
        rust:alpine sh -c "
          set -e
          apk add --no-cache musl-dev openssl-dev pkgconfig >/dev/null
          export CARGO_TARGET_DIR=/src/target-musl
          cargo build --release --target $target
        " >&2 || return 1
      echo "$CODESEAL_ROOT/cli/target-musl/$target/release/sgit"
      ;;
    aarch64-unknown-linux-musl)
      # A real cross-compile, not emulation.
      #
      # `rust:alpine` under `--platform linux/arm64` would work and would run
      # every rustc invocation through QEMU, turning a two-minute build into a
      # long one. `rust-musl-cross` is an x86_64 image carrying an aarch64 musl
      # toolchain, so the compiler runs at native speed and only the output is
      # foreign.
      echo "release: cross-compiling $target in a container…" >&2
      command_exists docker || { echo "release: docker is required to build $target" >&2; return 1; }
      docker run --rm \
        -v "$CODESEAL_ROOT/cli:/src" -w /src \
        -v "$CODESEAL_ROOT/cli/.cargo-musl-arm64:/root/.cargo/registry" \
        messense/rust-musl-cross:aarch64-musl sh -c "
          set -e
          export CARGO_TARGET_DIR=/src/target-musl-arm64
          cargo build --release --target $target
        " >&2 || return 1
      echo "$CODESEAL_ROOT/cli/target-musl-arm64/$target/release/sgit"
      ;;
    *)
      echo "release: no build recipe for $target" >&2
      return 1
      ;;
  esac
}

# Prove the binary we are about to ship is the one we just built.
#
# A failed build leaves the previous binary in place, and a release carrying it
# looks identical to a good one until someone hits the missing fix.
# What this is guarding against: a build that failed and left the *previous*
# release's binary sitting in target/, which then gets packaged and published
# as the new version. Nothing about that looks wrong until somebody installs it.
#
# Asking the binary its version is the strong check, and it needs the binary to
# run. Two of the four targets cannot run on an x86_64 Mac — the arm64 Darwin
# build, and the arm64 Linux one without QEMU — so those get a weaker check,
# and it says so out loud. A verification that silently degrades is worse than
# one that is absent: it reports success it did not establish.
_release_verify_binary() {
  local bin="$1" version="$2" target="$3" reported=""

  [ -f "$bin" ] || { echo "release: $target produced no binary at $bin" >&2; return 1; }

  # Always: is this even the architecture we asked for? Cheap, and it catches
  # the case where a cross-build silently fell back to the host.
  local arch_ok=""
  case "$target" in
    x86_64-apple-darwin)         file "$bin" | grep -q "Mach-O 64-bit executable x86_64" && arch_ok=1 ;;
    aarch64-apple-darwin)        file "$bin" | grep -q "Mach-O 64-bit executable arm64"  && arch_ok=1 ;;
    x86_64-unknown-linux-musl)   file "$bin" | grep -q "ELF 64-bit LSB .*x86-64"         && arch_ok=1 ;;
    aarch64-unknown-linux-musl)  file "$bin" | grep -q "ELF 64-bit LSB .*ARM aarch64"    && arch_ok=1 ;;
  esac
  if [ -z "$arch_ok" ]; then
    echo "release: $target produced the wrong architecture:" >&2
    echo "release:   $(file -b "$bin")" >&2
    return 1
  fi

  # Then the version, by running it where that is possible.
  case "$target" in
    x86_64-apple-darwin)
      reported=$("$bin" --version 2>/dev/null | awk '{print $2}') ;;
    x86_64-unknown-linux-musl)
      reported=$(docker run --rm -v "$bin:/sgit:ro" alpine:3.20 /sgit --version 2>/dev/null | awk '{print $2}') ;;
  esac

  if [ -n "$reported" ]; then
    if [ "$reported" != "$version" ]; then
      echo "release: $target reports version '$reported', expected '$version'." >&2
      echo "release: the build probably failed and left an older binary behind." >&2
      return 1
    fi
    echo "release: $target -> sgit $reported (ran it)" >&2
    return 0
  fi

  # Cannot run it here. Look for the version Cargo compiled in instead.
  #
  # Weaker on purpose and not nothing: a stale binary carries the version it
  # was built as, so the string we are looking for is precisely the one it
  # would not contain.
  #
  # A substring match, because that is how the version appears — Rust packs
  # string literals together with no separator, so the binary holds
  # `sgit/1.0.4failed to build HTTP client…` and `Cli1.0.4CodeSeal CLI`, and
  # nothing that is a line of its own. Matching whole lines found nothing and
  # rejected a binary that was perfectly correct.
  #
  # The cost of a substring match is a dependency that happens to carry the
  # same version number, which would let a stale binary through. That is a
  # narrower hole than the one this closes.
  command_exists strings || {
    echo "release: cannot verify $target — this host can neither run it nor read" >&2
    echo "release: its strings. Install binutils, or cut this target on its own" >&2
    echo "release: architecture." >&2
    return 1
  }
  if ! strings -a "$bin" 2>/dev/null | grep -qF "$version"; then
    echo "release: $target does not contain the string '$version'." >&2
    echo "release: it is probably a binary left over from an earlier build." >&2
    return 1
  fi
  echo "release: $target -> $version (architecture + embedded version; this host cannot run it)" >&2
}

release() {
  if [ "$#" -lt 1 ]; then
    release_help
    return 1
  fi
  local v="$1"
  _release_validate_version "$v" || return 1
  _release_assert_clean || return 1

  local tag="v$v"
  local scoped="${CODESEAL_RELEASE_SCOPE}-${tag}"

  # Everything that can be checked cheaply is checked before anything that
  # takes minutes.
  command_exists gh || { echo "release: gh is required. Install it, then 'gh auth login'." >&2; return 1; }

  # Three of the four targets are built in containers, so a daemon that is not
  # answering ends the release — better here than four minutes in, after the
  # version bump has been committed.
  #
  # `docker info` rather than `command_exists docker`: the client is almost
  # always installed and the question is whether anything is listening. On this
  # machine the answer was no for a while — Docker Desktop is installed but not
  # running, and its context is what `docker` defaults to, while Colima holds
  # the live socket somewhere else entirely.
  command_exists docker || { echo "release: docker is required to build the Linux targets." >&2; return 1; }
  if ! docker info >/dev/null 2>&1; then
    echo "release: the docker daemon is not reachable." >&2
    echo "release:   current context: $(docker context show 2>/dev/null)" >&2
    echo "release:   DOCKER_HOST:     ${DOCKER_HOST:-(unset)}" >&2
    if [ -S "$HOME/.colima/default/docker.sock" ]; then
      echo "release: colima is running. Point docker at it:" >&2
      echo "release:   export DOCKER_HOST=\"unix://\$HOME/.colima/default/docker.sock\"" >&2
    else
      echo "release: start a daemon (colima start, or open Docker Desktop)." >&2
    fi
    return 1
  fi
  gh auth status >/dev/null 2>&1 || { echo "release: not logged in to GitHub. Run 'gh auth login'." >&2; return 1; }

  # Can this token write to the releases repository?
  #
  # Being logged in is not the same as being allowed. A fine-grained token
  # scoped to one repository authenticates perfectly and then 403s on any
  # other, which is how v1.0.4 got built, verified, committed, pushed and
  # tagged before failing at the last step — leaving a tag with no artefacts
  # behind it.
  #
  # `push` on the releases repo is the permission `gh release create` needs.
  # Asking costs one API call; not asking costs three minutes and a bad tag.
  local can_push
  can_push=$(gh api "repos/$CODESEAL_RELEASES_REPO" --jq '.permissions.push' 2>/dev/null)
  if [ "$can_push" != "true" ]; then
    echo "release: this GitHub token cannot publish to $CODESEAL_RELEASES_REPO." >&2
    echo "         Nothing has been built or tagged." >&2
    echo "" >&2
    echo "  A fine-grained token scoped to a single repository will do this:" >&2
    echo "  it authenticates, and then 403s on everything it was not granted." >&2
    echo "" >&2
    echo "  Export one with write access to $CODESEAL_RELEASES_REPO and retry:" >&2
    echo "    GH_TOKEN=<token> release $v" >&2
    return 1
  fi

  if git -C "$CODESEAL_ROOT" rev-parse --verify "refs/tags/$tag" >/dev/null 2>&1; then
    echo "release: tag $tag already exists locally. 'git tag -d $tag' to redo it." >&2
    return 1
  fi
  if git -C "$CODESEAL_ROOT" ls-remote --tags --exit-code origin "refs/tags/$tag" >/dev/null 2>&1; then
    echo "release: tag $tag already exists on origin. Pick a different version." >&2
    return 1
  fi
  if gh release view "$scoped" --repo "$CODESEAL_RELEASES_REPO" >/dev/null 2>&1; then
    echo "release: $scoped is already published to $CODESEAL_RELEASES_REPO." >&2
    return 1
  fi

  echo "release: running the test suite…"
  ( cd "$CODESEAL_ROOT/cli" && cargo test --quiet ) || {
    echo "release: tests failed. Nothing was tagged or published." >&2
    return 1
  }

  _release_bump_cargo "$v" || return 1

  if [ -n "$(git -C "$CODESEAL_ROOT" status --porcelain)" ]; then
    echo "release: committing version bump…"
    git -C "$CODESEAL_ROOT" add cli/Cargo.toml || return 1
    # The lockfile SHOULD be committed for a binary crate, but a repository
    # that ignores it should not be unable to cut a release — `git add` on an
    # ignored path fails, and that aborted the run after the bump had already
    # been written.
    if git -C "$CODESEAL_ROOT" check-ignore -q cli/Cargo.lock 2>/dev/null; then
      echo "release: cli/Cargo.lock is gitignored — not committing it."
      echo "release: a binary crate's lockfile pins what a rebuild resolves; consider tracking it."
    else
      git -C "$CODESEAL_ROOT" add cli/Cargo.lock || return 1
    fi
    git -C "$CODESEAL_ROOT" commit -m "release: bump sgit to $v" || return 1
  fi

  local branch
  branch=$(git -C "$CODESEAL_ROOT" branch --show-current)
  [ -n "$branch" ] || { echo "release: refusing to release from a detached HEAD." >&2; return 1; }

  # Build and verify BEFORE tagging. A tag pointing at a commit whose binaries
  # do not build is worse than no tag: it looks releasable.
  local stage
  stage=$(mktemp -d) || return 1

  local target bin
  # Every host a CI runner might be, because the installer picks by the host's
  # architecture and not by what is being built. v1.0.4 shipped two of these,
  # and three of four publish jobs 404'd asking for the other two: `macos-latest`
  # is Apple Silicon now, so the x86_64 Darwin binary that *was* published never
  # got requested at all.
  for target in \
    x86_64-apple-darwin \
    aarch64-apple-darwin \
    x86_64-unknown-linux-musl \
    aarch64-unknown-linux-musl
  do
    bin=$(_release_build_target "$target") || { rm -rf "$stage"; return 1; }
    _release_verify_binary "$bin" "$v" "$target" || { rm -rf "$stage"; return 1; }

    mkdir -p "$stage/w" && cp "$bin" "$stage/w/sgit" && chmod +x "$stage/w/sgit"
    ( cd "$stage/w" && tar -czf "$stage/sgit-$tag-$target.tar.gz" sgit ) || { rm -rf "$stage"; return 1; }
    rm -rf "$stage/w"
  done

  # The operator assets: scripts/, infra/, compose.standalone.yml.
  #
  # install.sh downloads these into $CODESEAL so `seal up` and the cloud
  # deployers work without cloning a private repository. Publishing them in the
  # same release as the binary is what keeps the two in step — the scripts you
  # get always match the sgit you got.
  #
  # v1.0.0 shipped without them. The installer degraded politely, said so, and
  # left $CODESEAL empty and the `seal` launcher pointing at a file that was
  # never delivered.
  echo "release: packaging operator assets…"
  local assets="codeseal-assets-$tag.tar.gz"
  ( cd "$CODESEAL_ROOT" && tar -czf "$stage/$assets" scripts infra compose.standalone.yml ) || {
    echo "release: could not package operator assets." >&2
    rm -rf "$stage"
    return 1
  }

  # Its own checksum file, because install.sh fetches `<asset>.sha256` for this
  # one and refuses to extract without it.
  ( cd "$stage" && shasum -a 256 "$assets" > "$assets.sha256" ) || { rm -rf "$stage"; return 1; }

  # Extract it and check what the installer checks, rather than what is
  # convenient to check.
  #
  # The first version of this asserted that `scripts/seal.sh` appeared in
  # `tar -tzf`, which it did — and the release still broke, because the
  # installer looked for `codeseal-assets/scripts/` and the archive was flat.
  # A test that inspects the archive its own way can agree with itself while
  # disagreeing with the only consumer that matters.
  local probe
  probe=$(mktemp -d) || { rm -rf "$stage"; return 1; }
  tar -xzf "$stage/$assets" -C "$probe" || { rm -rf "$stage" "$probe"; return 1; }

  local root=""
  if [ -d "$probe/codeseal-assets/scripts" ]; then
    root="$probe/codeseal-assets"
  elif [ -d "$probe/scripts" ]; then
    root="$probe"
  else
    echo "release: assets archive has no scripts/ at either accepted level:" >&2
    ls -1 "$probe" >&2
    rm -rf "$stage" "$probe"
    return 1
  fi

  local missing=""
  for want in scripts/seal.sh scripts/app.sh scripts/create-env.sh compose.standalone.yml infra; do
    [ -e "$root/$want" ] || missing="$missing $want"
  done
  rm -rf "$probe"

  if [ -n "$missing" ]; then
    echo "release: operator assets are missing:$missing" >&2
    rm -rf "$stage"
    return 1
  fi

  # Names must match what install.sh computes from `uname`, or the download
  # 404s and reads as a broken release.
  ( cd "$stage" && shasum -a 256 sgit-*.tar.gz > SHA256SUMS && shasum -a 256 -c SHA256SUMS ) || {
    echo "release: checksum generation failed." >&2
    rm -rf "$stage"
    return 1
  }

  echo "release: pushing commits on $branch…"
  git -C "$CODESEAL_ROOT" push origin "$branch" || { rm -rf "$stage"; return 1; }

  echo "release: tagging $tag…"
  git -C "$CODESEAL_ROOT" tag -a "$tag" -m "$tag" || { rm -rf "$stage"; return 1; }
  git -C "$CODESEAL_ROOT" push origin "$tag" || {
    echo "release: tag push failed. The tag exists LOCALLY but not on origin." >&2
    rm -rf "$stage"
    return 1
  }

  echo "release: publishing $scoped to $CODESEAL_RELEASES_REPO…"
  ( cd "$stage" && gh release create "$scoped" \
      --repo "$CODESEAL_RELEASES_REPO" \
      --title "CodeSeal $tag" \
      --notes "CodeSeal CLI (sgit) $tag. Built from $CODESEAL_GH_REPO at $tag; the source is private, and these binaries, their checksums and the installer are the public artefacts." \
      sgit-*.tar.gz SHA256SUMS "$assets" "$assets.sha256" ) || {
    echo "release: publishing failed. The tag IS pushed; artefacts are in $stage." >&2
    echo "release: retry with: cd $stage && gh release create $scoped --repo $CODESEAL_RELEASES_REPO sgit-*.tar.gz SHA256SUMS $assets $assets.sha256" >&2
    return 1
  }

  rm -rf "$stage"

  cat <<EOF

release: $scoped published.
  https://github.com/$CODESEAL_RELEASES_REPO/releases/tag/$scoped

Install it anywhere:
  curl -fsSL https://raw.githubusercontent.com/$CODESEAL_RELEASES_REPO/main/$CODESEAL_RELEASE_SCOPE/install.sh | sh
EOF
}

_ghcr_login_check() {
  # Cheap probe: try `docker manifest inspect` against a known-public
  # image in the same registry. If unauthenticated requests work
  # we're done; otherwise prompt for a login.
  if docker info 2>/dev/null | grep -q "ghcr.io"; then
    return 0
  fi
  if [ -n "${CODESEAL_GHCR_TOKEN:-}" ]; then
    local user="${CODESEAL_GHCR_USER:-${USER:-}}"
    if [ -z "$user" ]; then
      echo "docker_push_portal: CODESEAL_GHCR_TOKEN set but CODESEAL_GHCR_USER / \$USER unknown." >&2
      return 1
    fi
    echo "docker_push_portal: logging in to ghcr.io as $user (via CODESEAL_GHCR_TOKEN)…"
    echo "$CODESEAL_GHCR_TOKEN" | docker login ghcr.io -u "$user" --password-stdin || return 1
    return 0
  fi
  # Not logged in and no token to use. Show the hint and fail closed.
  cat >&2 <<'EOF'
docker_push_portal: not logged in to ghcr.io.

Pick ONE:
  1. Interactive login (recommended for human runs):
       docker login ghcr.io
     Username: <your GitHub handle>
     Password: <a Personal Access Token with `write:packages`>

  2. One-shot via env var:
       export CODESEAL_GHCR_TOKEN=ghp_XXXX...
       export CODESEAL_GHCR_USER=<your GitHub handle>   # optional, defaults to $USER

PAT scope required: `write:packages` (classic) or
`packages:write` + `contents:read` (fine-grained, with this repo selected).
EOF
  return 1
}

docker_push_portal_help() {
  cat <<EOF
docker_push_portal [tag]

  Build the CodeSeal Portal Docker image and push it to GHCR.

  When called WITH a tag:
    docker_push_portal v1.0.0      # builds + pushes :v1.0.0 (and :latest if it's a stable tag)
    docker_push_portal v1.0.0-rc.1 # builds + pushes :v1.0.0-rc.1 only (no :latest)
  When called WITHOUT a tag:
    docker_push_portal             # builds + pushes :latest only

  Image: $CODESEAL_PORTAL_IMAGE
  Dockerfile: $CODESEAL_PORTAL_DOCKERFILE
  Context: $CODESEAL_PORTAL_CONTEXT
  Platforms: $CODESEAL_PORTAL_PLATFORMS

  Requires: docker buildx, ghcr.io login (or \$CODESEAL_GHCR_TOKEN).
EOF
}

docker_push_portal() {
  local raw_tag="${1:-latest}"
  # Strip leading 'v' for the registry tag if present, but keep both
  # forms ready so we tag :v1.0.0 (matches the GitHub release).
  local primary_tag="$raw_tag"
  local also_latest="false"
  if [[ "$primary_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    also_latest="true"   # stable semver → also tag :latest
  elif [[ "$primary_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+- ]]; then
    also_latest="false"  # pre-release → do NOT move :latest
  elif [ "$primary_tag" = "latest" ]; then
    also_latest="false"  # already latest; don't double-tag
  fi

  command_exists docker || { echo "docker_push_portal: docker not on PATH." >&2; return 1; }
  if ! docker buildx version >/dev/null 2>&1; then
    echo "docker_push_portal: 'docker buildx' is required for multi-arch push." >&2
    echo "  Install Docker Desktop, or set CODESEAL_PORTAL_PLATFORMS=linux/amd64 to fall back to single-arch (still needs buildx for --push)." >&2
    return 1
  fi
  [ -f "$CODESEAL_PORTAL_DOCKERFILE" ] || {
    echo "docker_push_portal: Dockerfile not found at $CODESEAL_PORTAL_DOCKERFILE" >&2
    return 1
  }
  _ghcr_login_check || return 1

  # Build the --tag list. buildx accepts repeated -t flags.
  local -a tag_args=(-t "${CODESEAL_PORTAL_IMAGE}:${primary_tag}")
  if [ "$also_latest" = "true" ]; then
    tag_args+=(-t "${CODESEAL_PORTAL_IMAGE}:latest")
  fi

  echo "docker_push_portal: building $CODESEAL_PORTAL_IMAGE"
  echo "  tags:       ${tag_args[*]}"
  echo "  platforms:  $CODESEAL_PORTAL_PLATFORMS"
  echo "  dockerfile: $CODESEAL_PORTAL_DOCKERFILE"
  echo "  context:    $CODESEAL_PORTAL_CONTEXT"

  # Make sure a buildx builder exists (Docker Desktop auto-creates
  # one; CI / fresh Linux installs sometimes don't).
  if ! docker buildx inspect >/dev/null 2>&1; then
    echo "docker_push_portal: bootstrapping a buildx builder…"
    docker buildx create --use --name codeseal-builder >/dev/null || return 1
  fi

  docker buildx build \
    --platform "$CODESEAL_PORTAL_PLATFORMS" \
    --file "$CODESEAL_PORTAL_DOCKERFILE" \
    "${tag_args[@]}" \
    --push \
    "$CODESEAL_PORTAL_CONTEXT" || {
      echo "docker_push_portal: build/push failed." >&2
      return 1
    }

  # Also push the companion MIGRATE image (the Dockerfile's `builder`
  # stage — it carries the Prisma CLI + migrations/ directory). The
  # standalone compose stack (compose.standalone.yml) runs it as a
  # one-shot before the portal boots; the slim runtime image can't
  # run `prisma migrate deploy` itself (node-binary-only, no npx).
  local migrate_image="${CODESEAL_PORTAL_IMAGE}-migrate"
  local -a migrate_tags=(-t "${migrate_image}:${primary_tag}")
  [ "$also_latest" = "true" ] && migrate_tags+=(-t "${migrate_image}:latest")

  echo "docker_push_portal: building $migrate_image (builder stage)"
  docker buildx build \
    --platform "$CODESEAL_PORTAL_PLATFORMS" \
    --file "$CODESEAL_PORTAL_DOCKERFILE" \
    --target builder \
    "${migrate_tags[@]}" \
    --push \
    "$CODESEAL_PORTAL_CONTEXT" || {
      echo "docker_push_portal: migrate-image build/push failed." >&2
      return 1
    }

  echo
  echo "docker_push_portal: pushed:"
  printf '  %s\n' "${CODESEAL_PORTAL_IMAGE}:${primary_tag}"
  [ "$also_latest" = "true" ] && printf '  %s\n' "${CODESEAL_PORTAL_IMAGE}:latest"
  printf '  %s\n' "${migrate_image}:${primary_tag}"
  [ "$also_latest" = "true" ] && printf '  %s\n' "${migrate_image}:latest"
  echo
  echo "  https://github.com/${CODESEAL_GH_REPO}/pkgs/container/${CODESEAL_PORTAL_IMAGE##*/}"
}

docker_push_worker_help() {
  cat <<EOF
docker_push_worker [tag]

  Build + push the CodeSeal worker image to GHCR. Same tag semantics
  as docker_push_portal (stable semver also moves :latest).

  Image: ${CODESEAL_PORTAL_IMAGE%-portal}-worker
  Dockerfile: infra/docker/worker/Dockerfile

  The standalone compose stack needs BOTH images on GHCR; cut a
  release with:
    docker_push_portal v1.0.0 && docker_push_worker v1.0.0
EOF
}

docker_push_worker() {
  local raw_tag="${1:-latest}"
  local primary_tag="$raw_tag"
  local also_latest="false"
  if [[ "$primary_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    also_latest="true"
  fi

  local worker_image="${CODESEAL_PORTAL_IMAGE%-portal}-worker"
  local worker_dockerfile="$CODESEAL_ROOT/infra/docker/worker/Dockerfile"

  command_exists docker || { echo "docker_push_worker: docker not on PATH." >&2; return 1; }
  docker buildx version >/dev/null 2>&1 || {
    echo "docker_push_worker: 'docker buildx' is required." >&2
    return 1
  }
  [ -f "$worker_dockerfile" ] || {
    echo "docker_push_worker: Dockerfile not found at $worker_dockerfile" >&2
    return 1
  }
  _ghcr_login_check || return 1

  local -a tag_args=(-t "${worker_image}:${primary_tag}")
  [ "$also_latest" = "true" ] && tag_args+=(-t "${worker_image}:latest")

  echo "docker_push_worker: building $worker_image"
  if ! docker buildx inspect >/dev/null 2>&1; then
    docker buildx create --use --name codeseal-builder >/dev/null || return 1
  fi
  docker buildx build \
    --platform "$CODESEAL_PORTAL_PLATFORMS" \
    --file "$worker_dockerfile" \
    "${tag_args[@]}" \
    --push \
    "$CODESEAL_PORTAL_CONTEXT" || {
      echo "docker_push_worker: build/push failed." >&2
      return 1
    }

  echo
  echo "docker_push_worker: pushed:"
  printf '  %s\n' "${worker_image}:${primary_tag}"
  [ "$also_latest" = "true" ] && printf '  %s\n' "${worker_image}:latest"
}

# ─────────────────────────────────────────────────────────────────────
# Cloud deploy helpers — one command per provider.
#
# Philosophy: each helper assumes the user has the provider's CLI
# installed AND authenticated. We do NOT manage credentials. If the
# CLI isn't logged in, we print the exact command they need to run
# and abort. Each helper is a thin wrapper around the provider's
# "deploy this image" command, so they're easy to read and easy to
# customise per tenant.
#
# All helpers default to deploying $CODESEAL_PORTAL_IMAGE:<tag>
# (default tag: latest). Build + push the image first with
# `docker_push_portal v1.0.0`, then call these.
#
# What none of these do for you:
#   - Provision Postgres + Redis. These are managed-DB add-ons on
#     every cloud; you point the Portal at them via env vars
#     (DATABASE_URL, REDIS_URL). Each helper documents this.
#   - Set DNS. The cloud's default hostname works for testing; you
#     point a custom domain at it later.
#   - Create secrets (SESSION_SECRET, ADMIN_KEY_WRAPPER, etc.).
#     We list what's required and you set them via the cloud CLI.
# ─────────────────────────────────────────────────────────────────────

_portal_image_ref() {
  local tag="${1:-latest}"
  printf '%s:%s\n' "$CODESEAL_PORTAL_IMAGE" "$tag"
}

# ─── Local Portal (docker compose) ────────────────────────────────

deploy_portal_local_help() {
  cat <<'EOF'
deploy_portal_local

  Bring up the Portal locally with docker compose from the repo root.
  Uses compose.yml (env-check + postgres + redis + portal-migrate +
  portal + worker — all built from source).

  Pre-conditions:
    - docker + docker compose installed
    - a `.env` at the repo root (copy .env.example and fill secrets;
      generate URL-safe values with `openssl rand -hex 32`)
    - free ports: 5432, 6379, 3000

  After it's up:
    - Portal at  http://localhost:3000
    - Worker logs:  docker compose logs -f worker

  No source checkout? Use compose.standalone.yml instead — it pulls
  pre-built images from GHCR:
    curl -fsSLO https://raw.githubusercontent.com/mylife-inc/CodeSeal/main/compose.standalone.yml
    # create .env (see the header comment inside the file), then:
    docker compose -f compose.standalone.yml up -d
EOF
}

deploy_portal_local() {
  command_exists docker || { echo "deploy_portal_local: docker not on PATH" >&2; return 1; }
  if ! docker compose version >/dev/null 2>&1; then
    echo "deploy_portal_local: 'docker compose' (v2) not available. Install Docker Desktop or compose-plugin." >&2
    return 1
  fi
  local compose_file="$CODESEAL_ROOT/compose.yml"
  if [ ! -f "$compose_file" ]; then
    echo "deploy_portal_local: $compose_file not found." >&2
    echo "Running outside a CodeSeal checkout? Use the standalone stack instead:" >&2
    echo "  curl -fsSLO https://raw.githubusercontent.com/${CODESEAL_GH_REPO}/main/compose.standalone.yml" >&2
    echo "  # create .env (see the file's header comment), then:" >&2
    echo "  docker compose -f compose.standalone.yml up -d" >&2
    return 1
  fi
  if [ ! -f "$CODESEAL_ROOT/.env" ]; then
    echo "deploy_portal_local: $CODESEAL_ROOT/.env is missing." >&2
    echo "  cp .env.example .env   # then replace every placeholder" >&2
    echo "  # generate URL-safe secrets: openssl rand -hex 32" >&2
    return 1
  fi
  echo "deploy_portal_local: using $compose_file"
  (cd "$CODESEAL_ROOT" && docker compose -f compose.yml up -d) || return 1
  echo
  echo "Portal:  http://localhost:3000"
  echo "Tail:    (cd $CODESEAL_ROOT && docker compose logs -f portal worker)"
  echo "Stop:    (cd $CODESEAL_ROOT && docker compose down)"
}

# ─── Railway ──────────────────────────────────────────────────────

deploy_railway_help() {
  cat <<'EOF'
deploy_railway [workspace] [rail.sh args…]

  Deploy the FULL CodeSeal stack to Railway (portal + worker +
  migrate images from GHCR, plus managed Postgres + Redis, plus
  env-var wiring). Delegates to infra/deploy/railway/rail.sh.

  Pre-conditions:
    - Install:   npm i -g @railway/cli
    - Login:     railway login
    - Workspace: pass it as the first argument, or export
                 RAILWAY_WORKSPACE beforehand. (No `railway link`
                 needed — rail.sh creates/links the project itself.)
    - .env:      defaults to $CODESEAL_ROOT/.env; generate one with
                 scripts/create-env.sh if missing.

  Examples:
    deploy_railway my-workspace
    RAILWAY_WORKSPACE=my-workspace deploy_railway
    CODESEAL_VERSION=v1.0.0 deploy_railway my-workspace
EOF
}

deploy_railway() {
  # Optional positional workspace (anything not starting with --).
  if [ -n "${1:-}" ] && [ "${1#--}" = "$1" ]; then
    export RAILWAY_WORKSPACE="$1"
    shift
  fi
  local rail="$CODESEAL_ROOT/infra/deploy/railway/rail.sh"
  [ -f "$rail" ] || {
    echo "deploy_railway: $rail not found. Run 'seal update' (or pull the repo)." >&2
    return 1
  }
  local env_file="${ENV_FILE:-$CODESEAL_ROOT/.env}"
  if [ ! -f "$env_file" ]; then
    echo "deploy_railway: no env file at $env_file." >&2
    echo "  Generate one: $CODESEAL_ROOT/scripts/create-env.sh $env_file" >&2
    return 1
  fi
  "$rail" --env-file "$env_file" "$@"
}

# ─── Google Cloud Run ─────────────────────────────────────────────

deploy_cloud_run_help() {
  cat <<'EOF'
deploy_cloud_run [tag]

  Deploy the Portal image to Google Cloud Run.

  Pre-conditions:
    - Install:   https://cloud.google.com/sdk/docs/install
    - Login:     gcloud auth login
    - Project:   gcloud config set project YOUR_PROJECT_ID
    - Region:    export CODESEAL_DEPLOY_REGION=us-central1  (default)

  Cloud Run pulls the image directly from GHCR (public). For private
  images, set up Artifact Registry mirroring instead. Postgres +
  Redis come from Cloud SQL + Memorystore — point the Portal at
  them via env vars in the deploy command below.
EOF
}

deploy_cloud_run() {
  local tag="${1:-latest}"
  command_exists gcloud || {
    echo "deploy_cloud_run: gcloud CLI not found. Install: https://cloud.google.com/sdk/docs/install" >&2
    return 1
  }
  local active
  active=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null)
  if [ -z "$active" ]; then
    echo "deploy_cloud_run: gcloud not authenticated. Run: gcloud auth login" >&2
    return 1
  fi
  local region="${CODESEAL_DEPLOY_REGION:-us-central1}"
  local image
  image=$(_portal_image_ref "$tag")
  echo "deploy_cloud_run: deploying $image to Cloud Run (region $region, service '$CODESEAL_DEPLOY_APP')"
  gcloud run deploy "$CODESEAL_DEPLOY_APP" \
    --image="$image" \
    --region="$region" \
    --port=3000 \
    --allow-unauthenticated \
    --platform=managed \
    --memory=512Mi \
    --cpu=1 \
    || {
      echo "deploy_cloud_run: failed. Common fixes:" >&2
      echo "  - enable Cloud Run API: gcloud services enable run.googleapis.com" >&2
      echo "  - make GHCR image public, or set up Artifact Registry mirroring" >&2
      return 1
    }
  echo
  echo "Next: set --set-env-vars DATABASE_URL=... REDIS_URL=... SESSION_SECRET=..."
  echo "      via 'gcloud run services update' or the console."
}

# ─── DigitalOcean App Platform ────────────────────────────────────

deploy_digitalocean_help() {
  cat <<'EOF'
deploy_digitalocean [tag]

  Deploy the Portal image to DigitalOcean App Platform.

  Pre-conditions:
    - Install:   https://docs.digitalocean.com/reference/doctl/how-to/install/
    - Login:     doctl auth init  (paste a personal access token)
    - Region:    export CODESEAL_DEPLOY_REGION=nyc3  (default)

  The first run creates a new app from a minimal spec, deploys
  $CODESEAL_PORTAL_IMAGE:<tag>, and prints the live URL. Subsequent
  runs trigger a re-deploy.

  Database + Redis: add managed-database resources from the App
  Platform dashboard once the app exists.
EOF
}

deploy_digitalocean() {
  local tag="${1:-latest}"
  command_exists doctl || {
    echo "deploy_digitalocean: doctl not found. Install: https://docs.digitalocean.com/reference/doctl/" >&2
    return 1
  }
  if ! doctl account get >/dev/null 2>&1; then
    echo "deploy_digitalocean: doctl not authenticated. Run: doctl auth init" >&2
    return 1
  fi
  local region="${CODESEAL_DEPLOY_REGION:-nyc3}"
  local image
  image=$(_portal_image_ref "$tag")
  # Write a minimal spec to a temp file. The image_url syntax for
  # GHCR is "ghcr.io/owner/name:tag" — App Platform pulls public
  # registries natively. For private images, set registry_type to
  # GHCR and add a registry_credentials block (not done here).
  local spec
  spec=$(mktemp -t codeseal-do-spec.XXXXXX.yaml) || return 1
  cat > "$spec" <<EOF
name: $CODESEAL_DEPLOY_APP
region: $region
services:
  - name: portal
    image:
      registry_type: DOCKER_HUB
      registry: ghcr.io
      repository: ${CODESEAL_PORTAL_IMAGE#ghcr.io/}
      tag: $tag
    http_port: 3000
    instance_size_slug: basic-xxs
    instance_count: 1
    health_check:
      http_path: /api/live
EOF
  echo "deploy_digitalocean: deploying $image (region $region, app '$CODESEAL_DEPLOY_APP')"
  # Look up existing app by name to decide create-vs-update.
  local app_id
  app_id=$(doctl apps list --format ID,Spec.Name --no-header \
            | awk -v n="$CODESEAL_DEPLOY_APP" '$2 == n { print $1 }')
  if [ -n "$app_id" ]; then
    doctl apps update "$app_id" --spec "$spec" || { rm -f "$spec"; return 1; }
  else
    doctl apps create --spec "$spec" || { rm -f "$spec"; return 1; }
  fi
  rm -f "$spec"
  echo
  echo "Next: doctl apps list   # → grab the live URL"
  echo "      attach managed Postgres + Redis from the App Platform UI"
  echo "      set env vars (DATABASE_URL, REDIS_URL, SESSION_SECRET, ADMIN_KEY_WRAPPER)"
}

# ─── AWS App Runner ───────────────────────────────────────────────

deploy_aws_apprunner_help() {
  cat <<'EOF'
deploy_aws_apprunner [tag]

  Deploy the Portal image to AWS App Runner.

  Pre-conditions:
    - Install:   https://aws.amazon.com/cli/
    - Configure: aws configure   (or use SSO / instance profile)
    - Region:    export CODESEAL_DEPLOY_REGION=us-east-1  (default)
    - GHCR access: App Runner can pull public GHCR images directly.
      For private images, set up ECR mirroring instead.

  This deployer creates (or updates) an App Runner service. RDS +
  ElastiCache for Postgres + Redis are NOT created — provision them
  separately and pass connection strings via env vars.

  WARNING: App Runner deploys can take 5-10 minutes.
EOF
}

deploy_aws_apprunner() {
  local tag="${1:-latest}"
  command_exists aws || {
    echo "deploy_aws_apprunner: aws CLI not found. Install: https://aws.amazon.com/cli/" >&2
    return 1
  }
  if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo "deploy_aws_apprunner: aws not authenticated. Run: aws configure" >&2
    return 1
  fi
  local region="${CODESEAL_DEPLOY_REGION:-us-east-1}"
  local image
  image=$(_portal_image_ref "$tag")
  # Look for an existing service by name in this region.
  local arn
  arn=$(aws apprunner list-services --region "$region" \
        --query "ServiceSummaryList[?ServiceName=='$CODESEAL_DEPLOY_APP'].ServiceArn | [0]" \
        --output text 2>/dev/null)
  if [ "$arn" = "None" ] || [ -z "$arn" ]; then
    echo "deploy_aws_apprunner: creating service '$CODESEAL_DEPLOY_APP' in $region"
    aws apprunner create-service \
      --region "$region" \
      --service-name "$CODESEAL_DEPLOY_APP" \
      --source-configuration "{
        \"ImageRepository\": {
          \"ImageIdentifier\": \"$image\",
          \"ImageRepositoryType\": \"ECR_PUBLIC\",
          \"ImageConfiguration\": { \"Port\": \"3000\" }
        },
        \"AutoDeploymentsEnabled\": false
      }" \
      --instance-configuration "Cpu=1024,Memory=2048" \
      || {
        echo "deploy_aws_apprunner: create failed." >&2
        echo "deploy_aws_apprunner: note App Runner requires ECR or ECR Public — for GHCR" >&2
        echo "  images set up a sync into ECR first (see AWS docs)." >&2
        return 1
      }
  else
    echo "deploy_aws_apprunner: updating service ($arn) to image $image"
    aws apprunner update-service \
      --region "$region" \
      --service-arn "$arn" \
      --source-configuration "{
        \"ImageRepository\": {
          \"ImageIdentifier\": \"$image\",
          \"ImageRepositoryType\": \"ECR_PUBLIC\",
          \"ImageConfiguration\": { \"Port\": \"3000\" }
        }
      }" \
      || return 1
  fi
  echo
  echo "Next: provision RDS Postgres + ElastiCache Redis, then"
  echo "      aws apprunner update-service ... --source-configuration with env vars."
}

# Stay quiet when sourced from a shell profile (install.sh wires
# `CODESEAL_QUIET=1 . "$CODESEAL/scripts/app.sh"` into ~/.zshrc).
[ -n "${CODESEAL_QUIET:-}" ] || echo "CodeSeal commands loaded. Run: help"
