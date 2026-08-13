#!/bin/sh
# check-env.sh — pre-flight validation of CodeSeal `.env`.
#
# Fails CLOSED with a clear remediation message before docker compose
# spins up postgres / redis / portal-migrate.
#
# Why this exists:
#   POSTGRES_PASSWORD and REDIS_PASSWORD are interpolated raw into
#   `postgres://user:PASS@host:port/db` style connection strings by
#   compose.yml. If the password contains a URL-unsafe character —
#   `/`, `+`, `@`, `:`, `?`, `#`, `=`, `&`, `%`, `[`, `]`, whitespace —
#   the URL parser misreads the authority and Prisma errors with
#   `P1013: invalid port number in database URL`, which is one of the
#   least helpful error messages in the ecosystem.
#
#   `openssl rand -base64 N` is a tempting password generator that
#   emits exactly those characters. This script catches the mistake
#   BEFORE postgres bakes the broken password into its data dir.
#
# Also enforces minimum lengths on SESSION_SECRET / ENCRYPTION_PEPPER /
# CODESEAL_WORKER_SECRET so a half-filled .env doesn't ship to
# production by accident.
#
# POSIX sh only — runs in `alpine:3` without bash. Compose calls it via
# the `env-check` service in compose.yml; humans can run it directly
# from the repo root: `sh scripts/check-env.sh`.

set -eu

# ── Inputs ──────────────────────────────────────────────────────────────
ENV_FILE="${ENV_FILE:-/env/.env}"

if [ ! -r "$ENV_FILE" ]; then
  printf '✗ env-check: cannot read %s\n' "$ENV_FILE" >&2
  printf '  Are you running `docker compose up` from the repo root?\n' >&2
  printf '  Copy .env.example → .env and fill in values before retrying.\n' >&2
  exit 2
fi

# ── Helpers ─────────────────────────────────────────────────────────────
# Extract a single `KEY=value` from $ENV_FILE without sourcing the file
# (sourcing would execute any backticks/$(...) the user has, and would
# leak values into our env if we later spawn a child process). Strips
# matching surrounding single or double quotes the same way dotenv does.
read_var() {
  # Use grep -m1 + sed; portable across BusyBox + GNU sed.
  raw=$(grep -m1 -E "^${1}=" "$ENV_FILE" 2>/dev/null || true)
  if [ -z "$raw" ]; then
    printf ''
    return
  fi
  value=${raw#*=}
  # Strip one pair of surrounding " or ' if present, mirroring dotenv.
  case "$value" in
    \"*\") value=${value#\"}; value=${value%\"} ;;
    \'*\') value=${value#\'}; value=${value%\'} ;;
  esac
  printf '%s' "$value"
}

FAIL=0
note_fail() {
  FAIL=$((FAIL + 1))
  printf '✗ %s\n' "$1" >&2
}

# A password is "URL-safe" iff every character is in RFC 3986's
# unreserved set: A-Z a-z 0-9 - . _ ~  (none of these EVER need
# percent-encoding in a URL, in any position).
url_safe_alpha='A-Za-z0-9._~-'

is_url_safe() {
  # Strip every URL-safe char; if anything remains, the password is bad.
  remainder=$(printf '%s' "$1" | tr -d "$url_safe_alpha")
  [ -z "$remainder" ]
}

# Print a short summary of the bad characters found, without leaking
# the password itself.
report_bad_chars() {
  bad=$(printf '%s' "$1" | tr -d "$url_safe_alpha")
  # De-duplicate by character; show up to 8 unique offenders.
  uniq=$(printf '%s' "$bad" | fold -w1 | sort -u | tr -d '\n' | cut -c1-8)
  printf '    URL-unsafe characters detected: %s\n' "$uniq" >&2
}

regen_hint() {
  printf '    Regenerate with:  openssl rand -hex 32       # 64 hex chars, always URL-safe\n' >&2
  printf '    Then in .env:     %s=<paste-here>\n' "$1" >&2
}

# ── Required URL-safe passwords ────────────────────────────────────────
for var in POSTGRES_PASSWORD REDIS_PASSWORD; do
  value=$(read_var "$var")
  if [ -z "$value" ]; then
    note_fail "$var is empty or missing in $ENV_FILE"
    regen_hint "$var"
    continue
  fi
  if ! is_url_safe "$value"; then
    note_fail "$var contains URL-unsafe characters — will break connection-string parsing"
    report_bad_chars "$value"
    regen_hint "$var"
    continue
  fi
  # Length sanity: ≥ 24 random URL-safe chars ≈ 128 bits.
  len=$(printf '%s' "$value" | wc -c | tr -d ' ')
  if [ "$len" -lt 16 ]; then
    note_fail "$var is only ${len} chars — pick at least 24"
    regen_hint "$var"
  fi
done

# ── Required high-entropy secrets (length-only check) ──────────────────
check_min_len() {
  var=$1
  min=$2
  value=$(read_var "$var")
  if [ -z "$value" ]; then
    note_fail "$var is empty or missing in $ENV_FILE"
    printf '    Generate with:  openssl rand -hex %d\n' "$((min / 2))" >&2
    return
  fi
  # The placeholder strings in .env.example all start with `change-me-`.
  case "$value" in
    change-me-*)
      note_fail "$var is still the .env.example placeholder — replace before booting"
      printf '    Generate with:  openssl rand -hex %d\n' "$((min / 2))" >&2
      return
      ;;
  esac
  len=$(printf '%s' "$value" | wc -c | tr -d ' ')
  if [ "$len" -lt "$min" ]; then
    note_fail "$var is only ${len} chars — required minimum is ${min}"
    printf '    Generate with:  openssl rand -hex %d\n' "$((min / 2))" >&2
  fi
}

check_min_len SESSION_SECRET 64
check_min_len ENCRYPTION_PEPPER 64
check_min_len CODESEAL_WORKER_SECRET 32

# ── Signup spec §2 env vars ────────────────────────────────────────────
# OPEN_SIGN_UP is "true" or "false"; anything else is a typo, fail closed.
open_signup=$(read_var OPEN_SIGN_UP)
case "$open_signup" in
  "" | "true" | "false") ;;
  *)
    note_fail "OPEN_SIGN_UP must be 'true' or 'false' (got: ${open_signup})"
    ;;
esac

# INVITATION_TOKEN_SECRET is REQUIRED when invitation-mode signup is on.
# When OPEN_SIGN_UP=true it's still recommended (a super-admin can mint
# invitations to grow the team) so we check it the same way.
check_min_len INVITATION_TOKEN_SECRET 32

# DEFAULT_INVITATION_TTL_HOURS must be a positive integer ≤ 8760 (1 year).
ttl=$(read_var DEFAULT_INVITATION_TTL_HOURS)
if [ -n "$ttl" ]; then
  case "$ttl" in
    ''|*[!0-9]*)
      note_fail "DEFAULT_INVITATION_TTL_HOURS must be a positive integer (got: ${ttl})"
      ;;
    *)
      if [ "$ttl" -lt 1 ] || [ "$ttl" -gt 8760 ]; then
        note_fail "DEFAULT_INVITATION_TTL_HOURS must be in 1..8760 (got: ${ttl})"
      fi
      ;;
  esac
fi

# ── Exit summary ───────────────────────────────────────────────────────
if [ "$FAIL" -gt 0 ]; then
  printf '\n✗ env-check: %d problem(s) found in %s.\n' "$FAIL" "$ENV_FILE" >&2
  printf '  Fix the lines above, then retry `docker compose up`.\n' >&2
  exit 1
fi

printf '✓ env-check: %s passes all checks.\n' "$ENV_FILE"
