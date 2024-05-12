#!/bin/bash
# Backup Posgres DB running in Docker container
# Usage:
#   posgres-backup.sh container-id destination-file-name

set -e

container_name="$1"
destination_file_name="$2"

if [ -z "$destination_file_name" ]; then
    echo "$0 container-id destination-file-name"
    exit 1
fi

# Dump database into a file inside of container
# shellcheck disable=SC2016
docker exec -it "$container_name" sh -c 'pg_dump --username="$POSTGRES_USER" "$POSTGRES_DB" --file=/var/lib/postgresql/data/db.backup --format=custom'

# Copy file from container to local file
docker cp "$container_name:/var/lib/postgresql/data/db.backup" "$destination_file_name"