#!/bin/sh
# Idempotently create/update a Postgres role+database for each name in $DB_NAMES
# (comma-separated), then lock down PUBLIC privileges. Safe to re-run: existing
# roles/databases are left alone (besides an unconditional password refresh, which
# is how a rotated password gets picked up).
#
# Each name's password is read from PG_PASSWORD_<UPPERCASED_NAME> (e.g. "team_wiki"
# -> PG_PASSWORD_TEAM_WIKI), which must be exported into this container's environment
# by docker-compose.yaml.
set -eu

IFS=','
for name in $DB_NAMES; do
  envvar="PG_PASSWORD_$(printf '%s' "$name" | tr 'a-z-' 'A-Z_')"
  eval "pgpass=\${$envvar}"

  PGPASSWORD="$POSTGRES_PASSWORD" psql -v ON_ERROR_STOP=1 -h postgres -U postgres <<-SQL
		DO \$\$ BEGIN
		  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$name') THEN
		    CREATE ROLE "$name" LOGIN;
		  END IF;
		END \$\$;
		ALTER ROLE "$name" WITH PASSWORD '$pgpass';
		SELECT 'CREATE DATABASE "$name" OWNER "$name"'
		  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$name')\gexec
		REVOKE ALL ON DATABASE "$name" FROM PUBLIC;
	SQL

  PGPASSWORD="$POSTGRES_PASSWORD" psql -v ON_ERROR_STOP=1 -h postgres -U postgres \
    -d "$name" -c "REVOKE ALL ON SCHEMA public FROM PUBLIC;"
done
