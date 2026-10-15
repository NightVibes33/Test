#!/usr/bin/env python3
"""Single-object, owned-test-account Mercado Libre order authorization probe.

NO discovery, guessed IDs, privileged login attempts, brute force, or real accounts.
Requires exactly 3 distinct developer test users and an existing controlled order.
Logs only status and account IDs, never tokens or full order bodies.
"""
import datetime as dt
import hashlib
import json
import os
import re
import ssl
import sys
import time
import urllib.error
import urllib.request

API = "https://api.mercadolibre.com"
ROLE_TOKENS = {
    "seller": os.getenv("ML_TEST_SELLER_TOKEN", "").strip(),
    "buyer": os.getenv("ML_TEST_BUYER_TOKEN", "").strip(),
    "outsider": os.getenv("ML_TEST_OUTSIDER_TOKEN", "").strip(),
}
ORDER_ID = os.getenv("ML_OWN_TEST_ORDER_ID", "").strip()
OUTPUT = os.getenv("ML_EVIDENCE", "mercadolibre-order-authz-evidence.json")
ROWS = []


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


OPENER = urllib.request.build_opener(
    urllib.request.HTTPSHandler(context=ssl.create_default_context()),
    NoRedirect(),
)


def request(path, token=None):
    if not re.fullmatch(r"/(?:users/me|orders/[0-9]{6,25})", path):
        raise ValueError("Only the two documented allowlisted paths may be requested")
    headers = {"Accept": "application/json", "User-Agent": "Owned-Account-Authz-Research/1.0"}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(API + path, headers=headers, method="GET")
    try:
        with OPENER.open(req, timeout=15) as resp:
            status, body = resp.status, resp.read(200000)
    except urllib.error.HTTPError as err:
        status, body = err.code, err.read(200000)
    parsed = None
    try:
        parsed = json.loads(body)
    except (ValueError, UnicodeDecodeError):
        pass
    return status, parsed, hashlib.sha256(body).hexdigest()


def record(role, path, status, digest):
    ROWS.append({
        "role": role, "path": path, "status": status,
        "body_sha256": digest, "time_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
    })
    print(f"{role:9} GET {path:27} => HTTP {status}", flush=True)


def main():
    if not re.fullmatch(r"[0-9]{6,25}", ORDER_ID):
        sys.exit("Set ML_OWN_TEST_ORDER_ID to a single existing order ID from your two test users")
    if any(not token for token in ROLE_TOKENS.values()):
        sys.exit("Missing at least one ML_TEST_{SELLER,BUYER,OUTSIDER}_TOKEN")
    if len(set(ROLE_TOKENS.values())) != 3:
        sys.exit("The three test tokens must be distinct")

    identities = {}
    for role, token in ROLE_TOKENS.items():
        status, obj, digest = request("/users/me", token)
        record(role, "/users/me", status, digest)
        if status != 200 or not isinstance(obj, dict):
            sys.exit(f"{role} token did not authenticate as expected (HTTP {status})")
        # Explicitly refuse testing with real customer accounts.
        tags = obj.get("tags") or []
        if "test_user" not in tags:
            sys.exit(f"{role} is not marked test_user; refusing live authorization testing")
        identities[role] = str(obj.get("id") or "")
        if not identities[role].isdigit():
            sys.exit(f"Cannot validate controlled identity for {role}")
    if len(set(identities.values())) != 3:
        sys.exit("Some roles resolve to the same user; three distinct test users required")

    path = "/orders/" + ORDER_ID
    seller_status, order, digest = request(path, ROLE_TOKENS["seller"])
    record("seller", path, seller_status, digest)
    if seller_status not in (200, 206) or not isinstance(order, dict):
        sys.exit("Controlled seller order not readable; no cross-account probe performed")
    actual = str(order.get("id", ""))
    seller_id = str((order.get("seller") or {}).get("id", ""))
    buyer_id = str((order.get("buyer") or {}).get("id", ""))
    if (actual, seller_id, buyer_id) != (
        ORDER_ID, identities["seller"], identities["buyer"]
    ):
        sys.exit("Order owner identities were not independently established; STOP")

    buyer_status, buyer_obj, digest = request(path, ROLE_TOKENS["buyer"])
    record("buyer", path, buyer_status, digest)
    if buyer_status not in (200, 206) or not isinstance(buyer_obj, dict):
        sys.exit("Controlled buyer order not readable; no cross-account probe performed")
    if str(buyer_obj.get("id")) != ORDER_ID:
        sys.exit("Buyer order ID mismatch; STOP")

    # Only after both authorized controls match do we test the unrelated account.
    time.sleep(0.5)
    other_status, other_obj, digest = request(path, ROLE_TOKENS["outsider"])
    record("outsider", path, other_status, digest)
    time.sleep(0.5)
    anon_status, anon_obj, digest = request(path)
    record("anonymous", path, anon_status, digest)

    unauthorized_2xx = []
    for role, status, obj in [
        ("outsider", other_status, other_obj),
        ("anonymous", anon_status, anon_obj),
    ]:
        if status in (200, 206) and isinstance(obj, dict) and str(obj.get("id")) == ORDER_ID:
            unauthorized_2xx.append(role)

    result = {
        "test_type": "owned_test_user_single_order_authorization",
        "api_host": API,
        "controlled_order_id": ORDER_ID,
        "controlled_test_user_ids": identities,
        "checks": ROWS,
        "unexpected_success_roles": unauthorized_2xx,
        "verdict": (
            "CANDIDATE_UNAUTHORIZED_ORDER_READ_REQUIRES_MANUAL_REVIEW"
            if unauthorized_2xx else "NOT_REPRODUCED"
        ),
        "important": "This is not a bounty finding until real unintended data exposure and policy impact are confirmed.",
    }
    with open(OUTPUT, "w", encoding="utf-8") as fh:
        json.dump(result, fh, indent=2)
    print("VERDICT:", result["verdict"], "evidence:", OUTPUT)
    return 2 if unauthorized_2xx else 0


if __name__ == "__main__":
    sys.exit(main())
