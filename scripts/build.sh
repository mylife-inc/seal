#!/usr/bin/env bash
#
# CodeSeal's build, run by CI after the repository has been decrypted.
#
# By the time this runs, `cli/`, `portal/`, `infra/` and the internal docs
# exist as plaintext on the runner, and the key material that decrypted them
# has already been destroyed — the `codeseal-decrypt` action does that before
# it returns. Nothing here needs a secret, and nothing here should ask for one.
#
# The commands mirror `.github/workflows/cli-ci.yml` in the plaintext
# repository, deliberately. A sealed repository that builds differently from
# the original proves the sealing works and nothing else; the point is that the
# SAME build runs on a repository GitHub cannot read.
set -euo pipefail

say() { printf '\n\033[1m▸ %s\033[0m\n' "$*"; }

# Prove the decryption happened before spending ten minutes discovering it did
# not. Without this a failed decrypt surfaces as a Rust error about a missing
# module, which reads as a code problem and sends you looking in the wrong
# place entirely.
say "Checking the working tree was decrypted"
missing=""
for f in cli/src/main.rs cli/Cargo.toml portal/package.json; do
  [ -s "$f" ] || missing="$missing $f"
done
if [ -n "$missing" ]; then
  echo "build: these should exist and do not:$missing" >&2
  echo "build: the repository was not decrypted — check the dispatch token." >&2
  exit 1
fi
echo "  decrypted: cli, portal"

say "Format"
(cd cli && cargo fmt --all -- --check)

say "Lint"
(cd cli && cargo clippy --all-targets -- -D clippy::correctness)

say "Tests"
(cd cli && cargo test --all-targets --locked)

say "Release build"
(cd cli && cargo build --release --locked)
./cli/target/release/sgit --version

say "Build complete"
