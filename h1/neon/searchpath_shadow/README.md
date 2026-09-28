# Neon compute-spec search_path shadow candidate

Target program: HackerOne `neon_bbp`

Relevant in-scope managed target: `https://console-stage.neon.build/`

Source location:

`compute_tools/src/sql/drop_subscriptions.sql`

Current main contains:

```sql
SELECT oid FROM pg_database
WHERE datname OPERATOR(pg_catalog.=) ...
```

The surrounding hardening patch qualified nearly every PostgreSQL catalog,
function, operator, and type specifically to prevent user-controlled objects
from being confused with PostgreSQL built-ins. This `pg_database` reference
remains unqualified.

## Candidate attack path

1. Database owner sets database-level `search_path = public, pg_catalog`.
2. Database owner creates attacker-controlled `public.pg_database`.
3. A fresh privileged maintenance connection inherits that database setting.
4. Neon's compute-spec `DropLogicalSubscriptions` phase executes the
   unqualified `pg_database` lookup.
5. PostgreSQL resolves the attacker object first.
6. An attacker-controlled invoker function reached through the shadow object
   executes under the privileged maintenance identity.

The workflow proves the database owner cannot directly write an admin-only
marker, then shows the shadow lookup can cause a write as `cloud_admin`.

This repository PoC is only the isolated PostgreSQL primitive. A HackerOne
report still requires confirmation on Neon's managed staging environment and
must follow the program's staging/account/header rules.
