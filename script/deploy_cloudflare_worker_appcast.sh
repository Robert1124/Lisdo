#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: script/deploy_cloudflare_worker_appcast.sh dist/release/appcast.xml

Deploys a Cloudflare module Worker that serves the supplied appcast XML from
one exact route. This does not deploy or modify any Cloudflare Pages site files.

Required environment:
  CLOUDFLARE_API_TOKEN
  CLOUDFLARE_ACCOUNT_ID
  CLOUDFLARE_ZONE_ID

Optional environment:
  CLOUDFLARE_WORKER_NAME   default: lisdo-appcast
  CLOUDFLARE_WORKER_ROUTE  default: lisdo.robertw.me/appcast.xml
  CLOUDFLARE_WORKER_COMPATIBILITY_DATE  default: 2024-11-01
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

APPCAST_PATH="${1:-}"
if [[ -z "$APPCAST_PATH" ]]; then
  usage >&2
  exit 64
fi
if [[ ! -s "$APPCAST_PATH" ]]; then
  echo "Appcast XML file does not exist or is empty: $APPCAST_PATH" >&2
  exit 66
fi

missing=()
for name in CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID CLOUDFLARE_ZONE_ID; do
  if [[ -z "${!name:-}" ]]; then
    missing+=("$name")
  fi
done
if [[ "${#missing[@]}" -gt 0 ]]; then
  printf 'Missing required Cloudflare environment variable(s): %s\n' "${missing[*]}" >&2
  exit 1
fi

WORKER_NAME="${CLOUDFLARE_WORKER_NAME:-lisdo-appcast}"
ROUTE_PATTERN="${CLOUDFLARE_WORKER_ROUTE:-lisdo.robertw.me/appcast.xml}"
COMPATIBILITY_DATE="${CLOUDFLARE_WORKER_COMPATIBILITY_DATE:-2024-11-01}"
API_BASE="https://api.cloudflare.com/client/v4"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

WORKER_MODULE="$TMP_DIR/worker.mjs"
METADATA_FILE="$TMP_DIR/metadata.json"
UPLOAD_RESPONSE="$TMP_DIR/upload-response.json"
ROUTES_RESPONSE="$TMP_DIR/routes-response.json"
ROUTE_PAYLOAD="$TMP_DIR/route-payload.json"
ROUTE_RESPONSE="$TMP_DIR/route-response.json"

python3 - "$APPCAST_PATH" "$WORKER_MODULE" <<'PY'
import json
import sys
from pathlib import Path

appcast_path = Path(sys.argv[1])
worker_module = Path(sys.argv[2])
xml = appcast_path.read_text(encoding="utf-8")
worker_module.write_text(
    """const APPCAST_XML = %s;

export default {
  async fetch(request, env, ctx) {
    return new Response(APPCAST_XML, {
      headers: {
        "content-type": "application/xml; charset=utf-8",
        "access-control-allow-origin": "*",
        "cache-control": "public, max-age=0, must-revalidate"
      }
    });
  }
};
"""
    % json.dumps(xml),
    encoding="utf-8",
)
PY

python3 - "$METADATA_FILE" "$COMPATIBILITY_DATE" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(
    json.dumps({"main_module": "worker.mjs", "compatibility_date": sys.argv[2]}),
    encoding="utf-8",
)
PY

require_api_success() {
  local response_file="$1"
  local context="$2"
  python3 - "$response_file" "$context" <<'PY'
import json
import sys
from pathlib import Path

response_path = Path(sys.argv[1])
context = sys.argv[2]
try:
    data = json.loads(response_path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"{context} failed: could not parse Cloudflare API response: {exc}", file=sys.stderr)
    sys.exit(1)

if data.get("success") is True:
    sys.exit(0)

messages = []
for error in data.get("errors") or []:
    code = error.get("code")
    message = error.get("message") or error
    messages.append(f"{code}: {message}" if code is not None else str(message))
if not messages:
    messages.append(json.dumps(data, sort_keys=True))
print(f"{context} failed: {'; '.join(messages)}", file=sys.stderr)
sys.exit(1)
PY
}

curl -fsS \
  -X PUT "$API_BASE/accounts/$CLOUDFLARE_ACCOUNT_ID/workers/scripts/$WORKER_NAME" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -F "metadata=<$METADATA_FILE;type=application/json" \
  -F "worker.mjs=@$WORKER_MODULE;type=application/javascript+module" \
  -o "$UPLOAD_RESPONSE"
require_api_success "$UPLOAD_RESPONSE" "Cloudflare Worker upload"

curl -fsS \
  "$API_BASE/zones/$CLOUDFLARE_ZONE_ID/workers/routes?per_page=100" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -o "$ROUTES_RESPONSE"
require_api_success "$ROUTES_RESPONSE" "Cloudflare Worker route lookup"

ROUTE_ID="$(
  python3 - "$ROUTES_RESPONSE" "$ROUTE_PATTERN" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
pattern = sys.argv[2]
for route in data.get("result") or []:
    if route.get("pattern") == pattern:
        print(route.get("id", ""))
        break
PY
)"

python3 - "$ROUTE_PAYLOAD" "$ROUTE_PATTERN" "$WORKER_NAME" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(
    json.dumps({"pattern": sys.argv[2], "script": sys.argv[3]}),
    encoding="utf-8",
)
PY

if [[ -n "$ROUTE_ID" ]]; then
  ROUTE_METHOD="PUT"
  ROUTE_URL="$API_BASE/zones/$CLOUDFLARE_ZONE_ID/workers/routes/$ROUTE_ID"
else
  ROUTE_METHOD="POST"
  ROUTE_URL="$API_BASE/zones/$CLOUDFLARE_ZONE_ID/workers/routes"
fi

curl -fsS \
  -X "$ROUTE_METHOD" "$ROUTE_URL" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  --data @"$ROUTE_PAYLOAD" \
  -o "$ROUTE_RESPONSE"
require_api_success "$ROUTE_RESPONSE" "Cloudflare Worker route deployment"

echo "Deployed $WORKER_NAME to Cloudflare Worker route $ROUTE_PATTERN."
