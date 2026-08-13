#!/bin/sh
# install.sh — one-command CodeSeal setup.
#
# Standalone POSIX sh (works on macOS bash 3.2, Alpine ash, dash).
#
#   curl -fsSL https://raw.githubusercontent.com/mylife-inc/releases/main/codeseal/install.sh | sh
#
# What it does, in order:
#   1. Installs the `sgit` binary from the latest GitHub release
#      (SHA-256 verified; sigstore verification optional).
#   2. Creates the CodeSeal home directory — $CODESEAL, defaulting
#      to ~/Dev/config/codeseal — where per-project configs and
#      identity keys live.
#   3. Downloads the repo's `scripts/` + `infra/` folders and
#      `compose.standalone.yml` into $CODESEAL, so you can run the
#      whole stack and the cloud deployers WITHOUT cloning the repo.
#      Also generates $CODESEAL/.env with random secrets (chmod 600)
#      so you can inspect/edit every variable before anything runs.
#   4. Installs the `seal` command next to sgit. After install:
#        seal up                  # run the whole stack locally
#        seal down                # stop it
#        seal deploy railway W    # deploy to Railway workspace W
#        seal deploy aws          # terraform scaffold
#        seal help                # everything else
#   5. Adds an idempotent block to your shell profile that exports
#      $CODESEAL and quietly sources $CODESEAL/scripts/app.sh, so
#      the operator functions (release, docker_push_portal,
#      deploy_cloud_run, …) are available in every new shell.
#
# Env overrides:
#   CODESEAL            — home directory (default ~/Dev/config/codeseal)
#   SGIT_VERSION        — install a specific sgit version, e.g. v1.0.0.
#                         Default: the newest stable codeseal-* release.
#   SGIT_INSTALL_DIR    — binary dir. Default: /usr/local/bin (sudo
#                         fallback) else ~/.local/bin.
#   SGIT_REPO           — GitHub repo coordinates (owner/name).
#   SGIT_SKIP_VERIFY=1  — skip SHA-256 verification (NOT recommended).
#   SGIT_VERIFY_COSIGN=1— also verify the sigstore signature (needs cosign).
#   SGIT_ONLY=1         — install just the sgit binary; skip steps 2-5.
#   CODESEAL_SKIP_PROFILE=1 — do steps 1-4 but don't touch the shell profile.
#
# Exit codes: 0 ok · 1 usage/detection · 2 download · 3 integrity · 4 install

set -eu

# The PUBLIC artefact repository — not the source repository.
#
# CodeSeal's source is private, and a private repository's release assets need
# a token to download, which makes `curl … | sh` impossible. So binaries and
# the operator assets are published into a public repository that holds
# artefacts for several projects.
#
# That sharing is why every tag here is scoped: `latest` in a repository shared
# by several products is not necessarily ours.
DEFAULT_REPO="mylife-inc/releases"
REPO="${SGIT_REPO:-$DEFAULT_REPO}"
SCOPE="${SGIT_SCOPE:-codeseal}"

# Where a signature was MADE, which is not where the file was downloaded from.
#
# Sigstore binds a signature to the workflow identity that produced it. That
# workflow runs in the source repository; the artefact is republished here.
# Checking the download location instead would accept a signature made by any
# workflow in the artefact repository — including one for a different product.
SIGNING_REPO="${SGIT_SIGNING_REPO:-mylife-inc/CodeSeal}"
VERSION="${SGIT_VERSION:-latest}"
INSTALL_DIR="${SGIT_INSTALL_DIR:-}"
SKIP_VERIFY="${SGIT_SKIP_VERIFY:-0}"
VERIFY_COSIGN="${SGIT_VERIFY_COSIGN:-0}"
SGIT_ONLY="${SGIT_ONLY:-0}"
SKIP_PROFILE="${CODESEAL_SKIP_PROFILE:-0}"

if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RED=$(printf '\033[31m'); C_GREEN=$(printf '\033[32m')
  C_YELLOW=$(printf '\033[33m'); C_BOLD=$(printf '\033[1m')
  C_RESET=$(printf '\033[0m')
else
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_BOLD=""; C_RESET=""
fi

info()  { printf '%s[codeseal-install]%s %s\n' "$C_BOLD" "$C_RESET" "$*" >&2; }
warn()  { printf '%s[codeseal-install]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()   { printf '%s[codeseal-install]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
ok()    { printf '%s[codeseal-install]%s %s\n' "$C_GREEN" "$C_RESET" "$*" >&2; }
# `$1` is the message and `$2` the exit code — so the message must be `$1`,
# not `$*`. With `$*` every call that passed a code printed it as part of the
# text: "…install it with SGIT_VERSION=v1.0.0-rc.1 2".
die()   { _msg="$1"; shift; err "${_msg}"; exit "${1:-1}"; }
have()  { command -v "$1" >/dev/null 2>&1; }

# ──────────────────────────────────────────────────────────────────
# Step 1 — sgit binary (same machinery as the old install-sgit.sh)
# ──────────────────────────────────────────────────────────────────

detect_target() {
  uname_s=$(uname -s 2>/dev/null || echo Unknown)
  uname_m=$(uname -m 2>/dev/null || echo Unknown)
  case "${uname_s}" in
    Linux)   os="unknown-linux-musl" ;;
    Darwin)  os="apple-darwin" ;;
    MINGW*|MSYS*|CYGWIN*)
      die "Windows detected. Download the .zip manually from https://github.com/${REPO}/releases/latest"
      ;;
    *)       die "Unsupported OS: ${uname_s}" ;;
  esac
  case "${uname_m}" in
    x86_64|amd64)  arch="x86_64" ;;
    arm64|aarch64) arch="aarch64" ;;
    *)             die "Unsupported architecture: ${uname_m}" ;;
  esac
  echo "${arch}-${os}"
}

fetch() {
  url="$1"; dst="$2"
  if have curl; then
    curl -fLSs --proto '=https' --tlsv1.2 --retry 3 -o "${dst}" "${url}" || return 2
  elif have wget; then
    wget --quiet --https-only --tries=3 -O "${dst}" "${url}" || return 2
  else
    die "Need either 'curl' or 'wget' on PATH." 1
  fi
}

resolve_version() {
  if [ "${VERSION}" != "latest" ]; then
    echo "${VERSION}"
    return 0
  fi

  # `/releases/latest` is the newest release in the whole repository, which in
  # a shared one may belong to another product entirely. Ask for the list and
  # take the newest tag carrying our scope.
  #
  # Pre-releases are skipped — somebody running an install one-liner wants the
  # stable version. A pinned SGIT_VERSION still installs whatever it names,
  # which is how a release candidate gets tested. `v1.0.0-rc.1` does not match
  # below: the closing quote has to follow the digits.
  # The request and the parse are separate, so a failed request cannot be
  # reported as an empty result.
  #
  # They used to be one pipeline, and a 403 produced "Found no stable release
  # in mylife-inc/releases" — a sentence about the wrong thing entirely. The
  # release was there; the API had refused to say so. That message sent us
  # looking for a missing release for as long as it took to read a CI log.
  if ! releases=$(fetch_stdout "https://api.github.com/repos/${REPO}/releases?per_page=100"); then
    die "Could not ask GitHub which ${SCOPE} releases exist.
    The request to api.github.com failed — commonly rate limiting, which is
    per-IP and applies to anonymous requests even on a public repository.
    Set GITHUB_TOKEN (Actions injects one) to raise the limit, or pin a
    version with SGIT_VERSION to skip the lookup entirely." 2
  fi

  version=$(
    printf '%s' "${releases}" |
      sed -n 's/.*"tag_name": *"'"${SCOPE}"'-\(v[0-9][0-9.]*\)".*/\1/p' |
      head -1
  )

  [ -n "${version}" ] || die "Found no stable ${SCOPE} release in ${REPO}.
    There may be a pre-release: see https://github.com/${REPO}/releases
    and install it with SGIT_VERSION=v1.0.0-rc.1" 2

  echo "${version}"
}

# `fetch` writes to a file; this one writes to stdout, for the API query.
#
# Authenticated whenever a token is around, because the anonymous GitHub API
# is rate-limited *by IP* and CI runners share heavily-used address pools. Four
# jobs of one matrix installing at once is enough: one gets through and the
# rest get 403, on a public repository that needs no credential to read.
#
# GITHUB_TOKEN is injected into every Actions job, so this costs nothing to
# arrange and lifts the limit from 60 requests an hour to 1000.
fetch_stdout() {
  url="$1"
  token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
  if have curl; then
    if [ -n "${token}" ]; then
      curl -fLSs --proto '=https' --tlsv1.2 --retry 3 \
        -H "Authorization: Bearer ${token}" "${url}"
    else
      curl -fLSs --proto '=https' --tlsv1.2 --retry 3 "${url}"
    fi
  elif have wget; then
    if [ -n "${token}" ]; then
      wget -qO- --header="Authorization: Bearer ${token}" "${url}"
    else
      wget -qO- "${url}"
    fi
  else
    die "Need either 'curl' or 'wget' on PATH." 1
  fi
}

pick_install_dir() {
  if [ -n "${INSTALL_DIR}" ]; then
    echo "${INSTALL_DIR}"
  elif [ -w /usr/local/bin ]; then
    echo /usr/local/bin
  elif have sudo && [ -d /usr/local/bin ]; then
    echo /usr/local/bin
  else
    mkdir -p "$HOME/.local/bin"
    echo "$HOME/.local/bin"
  fi
}

verify_sha256() {
  archive="$1"; sums="$2"
  if [ "${SKIP_VERIFY}" = "1" ]; then
    warn "SGIT_SKIP_VERIFY=1 — skipping integrity check (NOT recommended)."
    return 0
  fi
  if have sha256sum; then sum_cmd="sha256sum"
  elif have shasum;   then sum_cmd="shasum -a 256"
  else
    err "Neither sha256sum nor shasum found — cannot verify integrity."
    return 3
  fi
  # `shasum` writes "<hash>  <name>" or "<hash>  ./<name>" depending on how the
  # glob reached it, and both forms are published by things we control. Matching
  # only the bare name meant a SHA256SUMS generated with `shasum ./*.tar.gz`
  # verified nothing and failed closed — an install refused over a leading dot,
  # reported as "Could not find <archive> in SHA256SUMS".
  expected=$(awk -v name="$(basename "${archive}")" '
    { entry = $2; sub(/^\.\//, "", entry); if (entry == name) { print $1; exit } }
  ' "${sums}")
  [ -n "${expected}" ] || { err "Could not find ${archive} in SHA256SUMS."; return 3; }
  actual=$(${sum_cmd} "${archive}" | awk '{print $1}')
  if [ "${expected}" != "${actual}" ]; then
    err "SHA-256 mismatch! expected=${expected} actual=${actual}"
    return 3
  fi
  ok "SHA-256 verified."
}

verify_cosign() {
  archive="$1"; sig="$2"; cert="$3"
  [ "${VERIFY_COSIGN}" = "1" ] || return 0
  if ! have cosign; then
    warn "SGIT_VERIFY_COSIGN=1 but cosign is not on PATH. Skipping."
    return 0
  fi
  info "Verifying cosign signature…"
  cosign verify-blob \
    --certificate "${cert}" \
    --signature "${sig}" \
    --certificate-identity-regexp "^https://github.com/${SIGNING_REPO}/" \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com \
    "${archive}" >/dev/null 2>&1 \
    || { err "cosign signature verification FAILED."; return 3; }
  ok "Sigstore signature verified."
}

install_sgit() {
  info "Resolving target triple…"
  target=$(detect_target)
  info "Target: ${target}"

  info "Resolving release tag…"
  tag=$(resolve_version)
  info "Tag: ${tag}"

  asset="sgit-${tag}-${target}.tar.gz"
  base_url="https://github.com/${REPO}/releases/download/${SCOPE}-${tag}"

  info "Downloading ${asset}…"
  fetch "${base_url}/${asset}" "${tmpdir}/${asset}" \
    || die "Failed to download ${base_url}/${asset}. Check that the release exists." 2
  info "Downloading SHA256SUMS…"
  fetch "${base_url}/SHA256SUMS" "${tmpdir}/SHA256SUMS" \
    || die "Failed to download SHA256SUMS." 2
  verify_sha256 "${tmpdir}/${asset}" "${tmpdir}/SHA256SUMS" || die "Integrity check failed." 3

  if [ "${VERIFY_COSIGN}" = "1" ]; then
    fetch "${base_url}/${asset}.sig"  "${tmpdir}/${asset}.sig"  || die "Failed to fetch signature." 2
    fetch "${base_url}/${asset}.cert" "${tmpdir}/${asset}.cert" || die "Failed to fetch certificate." 2
    verify_cosign "${tmpdir}/${asset}" "${tmpdir}/${asset}.sig" "${tmpdir}/${asset}.cert" \
      || die "Signature check failed." 3
  fi

  # `--no-same-owner --no-same-permissions` where the tar supports them: an
  # archive can ask for setuid bits and for an owner, and neither is anything a
  # release archive legitimately needs. The `-f -` probe is how we find out
  # without depending on GNU vs BSD tar.
  if tar --no-same-owner --no-same-permissions -tzf "${tmpdir}/${asset}" >/dev/null 2>&1; then
    ( cd "${tmpdir}" && tar --no-same-owner --no-same-permissions -xzf "${asset}" ) \
      || die "Failed to extract ${asset}." 4
  else
    ( cd "${tmpdir}" && tar -xzf "${asset}" ) || die "Failed to extract ${asset}." 4
  fi

  # A regular file, and not a symlink pointing somewhere interesting. `-f`
  # alone follows links, so a hostile archive could have `sgit -> /etc/passwd`
  # and pass this check before being copied over something.
  [ -f "${tmpdir}/sgit" ] && [ ! -L "${tmpdir}/sgit" ] \
    || die "Archive did not contain a regular 'sgit' binary." 4
  chmod +x "${tmpdir}/sgit"

  bin_dir=$(pick_install_dir)
  info "Installing sgit to ${bin_dir}/sgit…"
  if [ -w "${bin_dir}" ]; then
    mv "${tmpdir}/sgit" "${bin_dir}/sgit"
  elif have sudo; then
    sudo install -m 0755 "${tmpdir}/sgit" "${bin_dir}/sgit" || die "sudo install failed." 4
  else
    die "${bin_dir} is not writable and sudo is not available. Set SGIT_INSTALL_DIR." 4
  fi
  ok "Installed sgit ${tag} → ${bin_dir}/sgit"
}

# ──────────────────────────────────────────────────────────────────
# Step 2 — $CODESEAL home directory
# ──────────────────────────────────────────────────────────────────

setup_home() {
  # Respect a pre-set CODESEAL; otherwise the maintainer-preferred
  # visible config tree (NOT a hidden ~/.codeseal dotfolder).
  CODESEAL="${CODESEAL:-$HOME/Dev/config/codeseal}"
  mkdir -p "${CODESEAL}"
  ok "CodeSeal home: ${CODESEAL}"
}

# ──────────────────────────────────────────────────────────────────
# Step 3 — download scripts/ + infra/ + compose.standalone.yml
# ──────────────────────────────────────────────────────────────────

download_assets() {
  # These used to come from `github.com/<source repo>/archive/main.tar.gz`,
  # which cannot work: the source repository is private, so an anonymous fetch
  # gets a 404 and the installer failed at step 3 for everybody who was not
  # already a collaborator.
  #
  # They are published as their own archive in the same release as the binary,
  # so the scripts you get always match the sgit you got.
  assets_asset="codeseal-assets-${tag}.tar.gz"
  assets_url="https://github.com/${REPO}/releases/download/${SCOPE}-${tag}/${assets_asset}"

  info "Downloading operator assets into \$CODESEAL…"
  if ! fetch "${assets_url}" "${tmpdir}/${assets_asset}"; then
    warn "No operator assets published for ${tag}."
    warn "sgit is installed and works; 'seal up' and the cloud deployers are not available."
    return 0
  fi

  fetch "${assets_url}.sha256" "${tmpdir}/${assets_asset}.sha256" \
    || die "Operator assets published without a checksum — refusing to extract." 3
  verify_sha256_single "${tmpdir}/${assets_asset}" "${tmpdir}/${assets_asset}.sha256" \
    || die "Operator assets failed their integrity check." 3

  if tar --no-same-owner --no-same-permissions -tzf "${tmpdir}/${assets_asset}" >/dev/null 2>&1; then
    ( cd "${tmpdir}" && tar --no-same-owner --no-same-permissions -xzf "${assets_asset}" ) \
      || die "Failed to extract operator assets." 4
  else
    ( cd "${tmpdir}" && tar -xzf "${assets_asset}" ) || die "Failed to extract operator assets." 4
  fi

  # Accept both layouts.
  #
  # The archive may wrap its contents in `codeseal-assets/`, or lay them out at
  # the top level. Requiring the wrapper made the installer die on an archive
  # that was otherwise perfectly good — checksum verified, every file present,
  # nested one directory differently than expected.
  #
  # What actually matters is that `scripts/` is there, because that is what the
  # `seal` launcher execs into.
  if [ -d "${tmpdir}/codeseal-assets/scripts" ]; then
    srcdir="${tmpdir}/codeseal-assets"
  elif [ -d "${tmpdir}/scripts" ]; then
    srcdir="${tmpdir}"
  else
    err "Operator assets are missing scripts/ — found:"
    ls -1 "${tmpdir}" >&2
    die "Cannot install operator assets." 4
  fi

  rm -rf "${CODESEAL}/scripts" "${CODESEAL}/infra"
  cp -R "${srcdir}/scripts" "${CODESEAL}/scripts"
  cp -R "${srcdir}/infra"   "${CODESEAL}/infra"
  cp "${srcdir}/compose.standalone.yml" "${CODESEAL}/compose.standalone.yml"
  [ -f "${srcdir}/.env.example" ] && cp "${srcdir}/.env.example" "${CODESEAL}/.env.example"
  chmod +x "${CODESEAL}"/scripts/*.sh 2>/dev/null || true
  chmod +x "${CODESEAL}"/infra/deploy/deploy.sh "${CODESEAL}"/infra/deploy/*/*.sh 2>/dev/null || true
  ok "Installed scripts/, infra/, compose.standalone.yml → ${CODESEAL}"
}

# Verify one file against a bare `<sha256>  <name>` line.
verify_sha256_single() {
  file="$1"; sumfile="$2"
  expected=$(cut -d" " -f1 < "${sumfile}")
  if have sha256sum; then
    actual=$(sha256sum "${file}" | cut -d" " -f1)
  elif have shasum; then
    actual=$(shasum -a 256 "${file}" | cut -d" " -f1)
  else
    err "Neither sha256sum nor shasum found — cannot verify integrity."
    return 3
  fi
  [ "${expected}" = "${actual}" ] || {
    err "Checksum mismatch:"
    err "  expected ${expected}"
    err "  actual   ${actual}"
    return 3
  }
  ok "Checksum verified."
}

# ──────────────────────────────────────────────────────────────────
# Step 3b — generate $CODESEAL/.env with random secrets
#
# Created at INSTALL time (not lazily on first `seal up`) so users
# can open it, inspect every variable, and change values before
# anything runs. Never overwrites an existing .env.
# ──────────────────────────────────────────────────────────────────

generate_env() {
  if [ -f "${CODESEAL}/.env" ]; then
    info "Keeping existing ${CODESEAL}/.env (not overwriting)."
    return 0
  fi
  if ! have openssl; then
    warn "openssl not found — skipping .env generation. Run 'seal env' later."
    return 0
  fi
  "${CODESEAL}/scripts/create-env.sh" "${CODESEAL}/.env" >/dev/null 2>&1 || {
    warn ".env generation failed — run 'seal env' later."
    return 0
  }
  ok "Generated ${CODESEAL}/.env (random secrets, chmod 600)."
  info "Inspect/edit it before 'seal up': \${EDITOR:-vi} ${CODESEAL}/.env"
  if grep -q '^BOOTSTRAP_ADMIN_PASSWORD=' "${CODESEAL}/.env"; then
    info "Bootstrap admin credentials (note them — first Portal login):"
    grep '^BOOTSTRAP_ADMIN_EMAIL=\|^BOOTSTRAP_ADMIN_PASSWORD=' "${CODESEAL}/.env" | sed 's/^/  /' >&2
  fi
}

# ──────────────────────────────────────────────────────────────────
# Step 4 — the `seal` launcher
# ──────────────────────────────────────────────────────────────────

install_seal() {
  bin_dir=$(pick_install_dir)
  launcher="${tmpdir}/seal"
  cat > "${launcher}" <<LAUNCHER
#!/bin/sh
# seal launcher — installed by CodeSeal install.sh.
# Resolves \$CODESEAL (falling back to the install-time location)
# and execs the real implementation inside it.
export CODESEAL="\${CODESEAL:-${CODESEAL}}"
exec "\${CODESEAL}/scripts/seal.sh" "\$@"
LAUNCHER
  chmod +x "${launcher}"
  if [ -w "${bin_dir}" ]; then
    mv "${launcher}" "${bin_dir}/seal"
  elif have sudo; then
    sudo install -m 0755 "${launcher}" "${bin_dir}/seal" || die "sudo install failed." 4
  else
    die "${bin_dir} is not writable and sudo is not available." 4
  fi
  ok "Installed seal → ${bin_dir}/seal"
}

# ──────────────────────────────────────────────────────────────────
# Step 5 — shell-profile wiring (idempotent, marker-delimited)
# ──────────────────────────────────────────────────────────────────

wire_profile() {
  [ "${SKIP_PROFILE}" = "1" ] && { warn "CODESEAL_SKIP_PROFILE=1 — skipping shell profile."; return 0; }
  case "${SHELL:-}" in
    */zsh)  profile="$HOME/.zshrc" ;;
    */bash) profile="$HOME/.bashrc" ;;
    *)      profile="$HOME/.profile" ;;
  esac
  if [ -f "${profile}" ] && grep -q '>>> codeseal >>>' "${profile}" 2>/dev/null; then
    info "Shell profile already wired (${profile})."
    return 0
  fi
  cat >> "${profile}" <<PROFILE

# >>> codeseal >>>
# Added by CodeSeal install.sh — exports the config home and loads
# the operator functions (release, docker_push_portal, deploy_*, …).
export CODESEAL="${CODESEAL}"
[ -f "\$CODESEAL/scripts/app.sh" ] && CODESEAL_QUIET=1 . "\$CODESEAL/scripts/app.sh"
# <<< codeseal <<<
PROFILE
  ok "Wired ${profile} (export CODESEAL + source app.sh)."
}

# ──────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────

main() {
  tmpdir=$(mktemp -d 2>/dev/null || mktemp -d -t codeseal-install)
  trap 'rm -rf "${tmpdir}"' EXIT INT TERM

  install_sgit

  if [ "${SGIT_ONLY}" = "1" ]; then
    ok "SGIT_ONLY=1 — done."
    return 0
  fi

  setup_home
  download_assets
  generate_env
  install_seal
  wire_profile

  bin_dir=$(pick_install_dir)
  case ":${PATH}:" in
    *":${bin_dir}:"*) ;;
    *)
      warn "${bin_dir} is NOT on your PATH. Add: export PATH=\"${bin_dir}:\$PATH\""
      ;;
  esac

  echo
  ok "CodeSeal installed."
  cat >&2 <<NEXT

Next steps (new shell, or 'source ${profile:-your shell profile}' first):

  sgit rd                    # seal a repo: per-developer keys, you trigger CI
  sgit init --wizard         # or answer questions instead

  seal up                    # run the whole Portal stack locally
  seal deploy railway WS     # deploy to a Railway workspace
  seal help                  # everything else

\`seal\` is a small launcher on your PATH; the implementation lives at
  ${CODESEAL}/scripts/seal.sh
and can be run directly if you prefer. That directory is deliberately NOT
added to PATH — it also holds build.sh, dev.sh and install.sh, and those
are not commands you want globally.

Your keys live in ${CODESEAL}. Back it up: a repository can be re-cloned,
these cannot be regenerated.

NEXT
}

main "$@"
