#!/bin/bash
# Set the log driver for Docker to 'json-file' with rolling log files using 'systemd' drop-in file
# Usage:
#   ubuntu-docker-set-log-limit.sh [log_file_max_size (default: 10m)] [max_number_of_log_files (default: 10)]

# Parameters for log driver
log_file_max_size="${1:-10m}"
max_number_of_log_files=${2:-10}

# Docker daemon start command
dockerd_cmd="/usr/bin/dockerd -H fd:// --log-driver=json-file --log-opt max-size=$log_file_max_size --log-opt max-file=$max_number_of_log_files"

drop_in_dir=/etc/systemd/system/docker.service.d
drop_in_file=$drop_in_dir/exec_start.conf

# Create a drop-in directory for systemd
mkdir -p $drop_in_dir

# Create a drop-in file

(
cat <<EOF
[Service]
ExecStart=
ExecStart=$dockerd_cmd
EOF
) > $drop_in_file

# Flush changes
systemctl daemon-reload

# Verify that the configuration has been loaded:
#systemctl show --property=ExecStart docker

echo Restart Docker
systemctl restart docker
