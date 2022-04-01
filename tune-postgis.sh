#!/bin/sh

set -e
export PGUSER="$POSTGRES_USER"

createdb -E UTF8 -O renderer gis
psql -d gis -c "CREATE EXTENSION IF NOT EXISTS postgis;"
psql -d gis -c "CREATE EXTENSION IF NOT EXISTS hstore;"
psql -d gis -c "ALTER TABLE geometry_columns OWNER TO renderer;"
psql -d gis -c "ALTER TABLE spatial_ref_sys OWNER TO renderer;"

#"${psql[@]}" -c "ALTER SYSTEM SET work_mem='${PG_WORK_MEM:-16MB}';"
#"${psql[@]}" -c "ALTER SYSTEM SET maintenance_work_mem='${PG_MAINTENANCE_WORK_MEM:-256MB}';"
