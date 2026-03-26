#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_PATH="${WIZMAC_BIN:-$ROOT_DIR/.build/arm64-apple-macosx/debug/wizmac}"
QUERY="${WIZMAC_BENCH_QUERY:-Primary}"
APP_NAME="${WIZMAC_BENCH_APP:-}"
TARGET_ID="${WIZMAC_BENCH_TARGET_ID:-}"
TEXT_PAYLOAD="${WIZMAC_BENCH_TEXT:-hello from wizmac}"
ITERATIONS="${WIZMAC_BENCH_ITERATIONS:-3}"
RUN_PREFETCH="${WIZMAC_BENCH_PREFETCH:-1}"

if [[ ! -x "$BIN_PATH" ]]; then
  echo "error: wizmac binary not found at $BIN_PATH" >&2
  echo "hint: run 'swift build' first or set WIZMAC_BIN" >&2
  exit 1
fi

measure() {
  local label="$1"
  shift
  echo ""
  echo "== $label =="
  for iteration in $(seq 1 "$ITERATIONS"); do
    echo "-- run $iteration"
    /usr/bin/time -lp "$BIN_PATH" call "$@" >/dev/null
  done
}

search_args=("ui.search" "query=$QUERY" "debugTimings=true")
if [[ -n "$APP_NAME" ]]; then
  search_args+=("app=$APP_NAME")
fi

if [[ "$RUN_PREFETCH" == "1" ]]; then
  prefetch_args=("ui.prefetch")
  if [[ -n "$APP_NAME" ]]; then
    prefetch_args+=("app=$APP_NAME")
  fi
  measure "ui.prefetch" "${prefetch_args[@]}"
fi

measure "ui.search" "${search_args[@]}"

if [[ -n "$TARGET_ID" ]]; then
  act_args=("ui.act" "targetID=$TARGET_ID" "interaction=move" "debugTimings=true")
  if [[ -n "$APP_NAME" ]]; then
    act_args+=("app=$APP_NAME")
  fi
  measure "ui.act" "${act_args[@]}"
fi

measure "text.insert" "text=$TEXT_PAYLOAD" "debugTimings=true"

echo ""
echo "Benchmark complete."
