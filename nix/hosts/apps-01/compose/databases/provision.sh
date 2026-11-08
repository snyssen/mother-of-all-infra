#!/bin/sh
# Idempotently create/update a Postgres role+database for each name in $DB_NAMES
# (comma-separated), then lock down PUBLIC privileges. Safe to re-run: existing
# roles/databases are left alone (besides an unconditional password refresh, which
# is how a rotated password gets picked up).
#
# Each name's password is read from PG_PASSWORD_<UPPERCASED_NAME> (e.g. "team_wiki"
# -> PG_PASSWORD_TEAM_WIKI), which must be exported into this container's environment
# by docker-compose.yaml.
#
# Names also listed in $DB_NAMES_C_LOCALE get their database created with the C
# collation and ctype, as Synapse requires (it refuses to start otherwise). Only at
# creation: a database's locale can't be changed afterwards, so an existing one with
# the wrong locale is reported, not fixed — drop it (it must be empty, or restorable)
# and re-run.
set -eu

IFS=','
for name in $DB_NAMES; do
  envvar="PG_PASSWORD_$(printf '%s' "$name" | tr 'a-z-' 'A-Z_')"
  eval "pgpass=\${$envvar}"

  createopts=""
  case ",${DB_NAMES_C_LOCALE:-}," in
    # Quotes doubled: this lands inside the SQL string literal that \gexec runs below.
    *",$name,"*) createopts=" TEMPLATE template0 ENCODING ''UTF8'' LC_COLLATE ''C'' LC_CTYPE ''C''" ;;
  esac

  PGPASSWORD="$POSTGRES_PASSWORD" psql -v ON_ERROR_STOP=1 -h postgres -U postgres <<-SQL
		DO \$\$ BEGIN
		  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$name') THEN
		    CREATE ROLE "$name" LOGIN;
		  END IF;
		END \$\$;
		ALTER ROLE "$name" WITH PASSWORD '$pgpass';
		SELECT 'CREATE DATABASE "$name" OWNER "$name"$createopts'
		  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$name')\gexec
		REVOKE ALL ON DATABASE "$name" FROM PUBLIC;
	SQL

  PGPASSWORD="$POSTGRES_PASSWORD" psql -v ON_ERROR_STOP=1 -h postgres -U postgres \
    -d "$name" -c "REVOKE ALL ON SCHEMA public FROM PUBLIC;"

  if [ -n "$createopts" ]; then
    locale=$(PGPASSWORD="$POSTGRES_PASSWORD" psql -v ON_ERROR_STOP=1 -h postgres -U postgres -tA \
      -c "SELECT datcollate || '/' || datctype FROM pg_database WHERE datname = '$name'")
    if [ "$locale" != "C/C" ]; then
      echo "WARNING: database $name has collation/ctype $locale, not C/C. It predates" >&2
      echo "  DB_NAMES_C_LOCALE, and its consumer will refuse it. Drop it and re-run" >&2
      echo "  provisioning to recreate it with the C locale, then restore its data." >&2
    fi
  fi
done
