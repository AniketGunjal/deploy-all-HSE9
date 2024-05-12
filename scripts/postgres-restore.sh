#!/bin/bash
# Restore Posgres DB running in Docker container
# Usage:
#   posgres-backup.sh source-file-name container-id

set -e

source_file_name="$1"
container_name="$2"

if [ -z "$container_name" ]; then
    echo "$0 source-file-name container-id"
    exit 1
fi

# Copy file from local file to container
docker cp "$source_file_name" "$container_name:/var/lib/postgresql/data/db.backup"

# Restore database from a file inside of container
# shellcheck disable=SC2016
docker exec -it "$container_name" sh -c 'pg_restore --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --clean --if-exists /var/lib/postgresql/data/db.backup'
