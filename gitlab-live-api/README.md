# GitLab 19.4.1-ee — real-HTTP reproduction

**Finding state: NOT VERIFIED.** Passing source-code tests did not prove this vulnerability. The original RSpec fixture inserted a related-Epic link directly into the database, bypassing normal API authorization. GitLab triage reproduced a `404 No matching epic found` when attempting to create the link after banning the author.

## Evidence obtained so far

- A disposable Docker installation of GitLab 19.4.1-ee.0 was started on GitHub Actions.
- `GET /api/v4/version` returned HTTP 200.
- Real `POST /api/v4/users`, `POST /api/v4/groups`, and `POST /api/v4/groups/:id/members` requests succeeded.
- `POST /api/v4/groups/:id/epics` returned HTTP **403**. Consequently, **no related-Epic relationship was created via the API**, and **no data leakage was reproduced**.
- The ephemeral instance had no Ultimate entitlement; the HTTP 403 may also depend on other instance-level permissions. Do not claim that entitlement is the sole proven cause without confirming the subscription status.

## Prerequisites for an actual live test

1. A **self-owned, disposable GitLab self-managed** host, with enough RAM and disk for GitLab EE.
2. **GitLab 19.4.1-ee**, as used in the submitted report.
3. A legitimately obtained and **activated GitLab Ultimate subscription or trial** on that very instance. See [GitLab's official Ultimate trial instructions](https://docs.gitlab.com/subscriptions/free_trials/). The trial requires an activation code that GitLab sends after registration; it is not provided by this repo.
4. Docker Engine, Docker Compose v2, Python 3 on the host; access to GitLab's Admin > Subscription.
5. Only test with self-created users, groups, and data.

## Setup and execution

From the `gitlab-live-api` directory:

```sh
docker compose -f compose.yml up -d
docker compose -f compose.yml ps
```

After GitLab has started, obtain the **initial local** administrator password:

```sh
docker compose -f compose.yml exec -T gitlab cat /etc/gitlab/initial_root_password
```

Access `http://127.0.0.1:8929` from the Docker host, sign in as `root`, then activate the GitLab Ultimate trial using **Admin > Subscription**. A self-managed activation code is issued by GitLab itself. Check the license is activated before running any tests. Do not place license codes or tokens into GitHub commits or public Actions logs.

Run:

```sh
bash run_owned_instance.sh
```

The runner provisions a **temporary local** root personal-access token and uses GitLab's normal `PRIVATE-TOKEN` + `Sudo` headers to make REST calls as separately created test users. It does not create Epic relationships in the database or bypass API permissions.

Review these files after execution:

- `evidence/summary.json`: verdict and blocker.
- `evidence/http-transcript.json`: timestamped requests/responses, with credentials redacted.
- `evidence/identifiers.json`: group and Epic IDs when creation reaches those steps.
- `evidence/version.json`: actual reported GitLab version.

**Required positive proof:** the target Epic is *not* directly readable anonymously after its author is banned (403/404), but its unique marker is nevertheless disclosed in the anonymous related-links listing. The target relationship must have been created through a **successful real HTTP POST** from a permissible user; no factory-inserted links count. Compare pre-ban and post-ban responses. Independently inspect the target work item's `hidden?` value and GitLab authorization if available. A failed request, an absent link, or a `403` due to licensing does **not** demonstrate a security vulnerability.

**Expected negative control:** attempt to create a separate link **after** the author has been banned; record the HTTP response. The previous analyst obtained `404`.

## Limitations

The GitHub-hosted workflow is a temporary disposable Docker instance without an activated Ultimate trial. Even a green runner is not evidence of exploitability. It cannot perform the reported Epic operation until the instance is entitled. A locally licensed, persistent installation is needed for a genuine live end-to-end reproduction. Do not submit these diagnostic attempts as a new vulnerability report.
