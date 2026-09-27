#!/usr/bin/env bash
set -euo pipefail

PORTAL_ID="46962361"
BASE="https://app.hubspot.com"

request() {
  local name="$1"; shift
  echo "===== $name ====="
  curl --silent --show-error --location --max-time 20 \
    -D "/tmp/$name.headers" -o "/tmp/$name.body" "$@" || true
  head -n 1 "/tmp/$name.headers" || true
  grep -iE '^(location|content-type|x-hubspot-auth-failure|x-hubspot-correlation-id):' "/tmp/$name.headers" || true
  head -c 1200 "/tmp/$name.body" || true
  echo
}

request shell "$BASE/contacts/$PORTAL_ID/"

request crm_search \
  -H 'content-type: application/json' \
  --data '{"count":1,"offset":0,"objectTypeId":"0-1","requestOptions":{"properties":["firstname","email","super_secret"]}}' \
  "$BASE/api/crm-search/search?portalId=$PORTAL_ID"

request lists "$BASE/api/contacts/v1/lists/internal/all?portalId=$PORTAL_ID"
