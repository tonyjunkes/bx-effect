#!/usr/bin/env bash
# Run ColdBox against real HTTP request contexts, independently of the CLI suite.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
port="${BX_EFFECT_FRAMEWORK_PORT:-8951}"
output="$root/.boxlang/framework-integration"
mkdir -p "$output"
base="http://127.0.0.1:$port"

if curl --silent --max-time 1 "$base/health" >/dev/null; then
  echo "Port $port is already in use; set BX_EFFECT_FRAMEWORK_PORT to a free port." >&2
  exit 1
fi

if [[ -n "${MINISERVER_JAR:-}" ]]; then
  server=(java -jar "$MINISERVER_JAR")
else
  command -v boxlang-miniserver >/dev/null
  server=(boxlang-miniserver)
fi
"${server[@]}" --host 127.0.0.1 --port "$port" --webroot "$root" \
  --serverHome "$output/home" --configPath "$root/tests/frameworks/boxlang.json" --health-check \
  >"$output/server.log" 2>&1 &
server_pid=$!
cleanup() { kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; }
trap cleanup EXIT

ready=false
for ((attempt=0; attempt<60; attempt++)); do
  if curl --fail --silent --max-time 1 "$base/health/ready" >/dev/null; then ready=true; break; fi
  if ! kill -0 "$server_pid" 2>/dev/null; then break; fi
  sleep 1
done
if [[ "$ready" != true ]]; then cat "$output/server.log"; exit 1; fi

curl --fail --silent --show-error --max-time 90 "$base/tests/frameworks/Run.bxm" >"$output/report.json"
jq '{totalPass,totalFail,totalError}' "$output/report.json"
if ! jq -e '.totalFail == 0 and .totalError == 0 and .totalPass > 0' "$output/report.json" >/dev/null; then
  cat "$output/report.json"
  exit 1
fi

# Verify the copyable web entry point through the complete ColdBox request pipeline.
curl --fail --silent --show-error --max-time 30 "$base/examples/coldbox/Index.bxm?name=Ada" >"$output/success.json"
jq -e '.greeting == "Hello, Ada!"' "$output/success.json" >/dev/null
status="$(curl --silent --show-error --max-time 30 -o "$output/invalid.json" -w '%{http_code}' "$base/examples/coldbox/Index.bxm?name=")"
[[ "$status" == 400 ]]
jq -e '._tag == "InvalidName"' "$output/invalid.json" >/dev/null
echo "ColdBox HTTP integration and response checks passed."
