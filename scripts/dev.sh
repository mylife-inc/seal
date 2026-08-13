#!/usr/bin/env bash

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

up() {
  (
    cd "$ROOT_DIR" || exit 1

    docker compose \
      -f compose.yml \
      -f compose.dev.yml \
      up \
      -d \
      --build
  )
}

down() {
  (
    cd "$ROOT_DIR" || exit 1

    docker compose \
      -f compose.yml \
      -f compose.dev.yml \
      down
  )
}

restart() {
  down
  up
}

logs() {
  (
    cd "$ROOT_DIR" || exit 1

    docker compose \
      -f compose.yml \
      -f compose.dev.yml \
      logs -f
  )
}

ps() {
  (
    cd "$ROOT_DIR" || exit 1

    docker compose \
      -f compose.yml \
      -f compose.dev.yml \
      ps
  )
}

shell_portal() {
  (
    cd "$ROOT_DIR" || exit 1

    docker compose exec portal bash
  )
}

shell_worker() {
  (
    cd "$ROOT_DIR" || exit 1

    docker compose exec worker bash
  )
}

shell_postgres() {
  (
    cd "$ROOT_DIR" || exit 1

    docker compose exec postgres bash
  )
}

shell_redis() {
  (
    cd "$ROOT_DIR" || exit 1

    docker compose exec redis sh
  )
}