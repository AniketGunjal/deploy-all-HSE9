#!/bin/bash
#
# Outputs the location and hostnames of all volumes for the specified service running under Rancher
#

# Returns the list of Rancher container Ids of the given service
# Parameters:
#   service name in the format 'stack/service'
# Output:
#   <Rancher-container-id>
#   ...
get_instanceIds ()
{
    rancher inspect $1 --format '{{ range $index, $element := .instanceIds }}{{$element}}{{"\n"}}{{end -}}' || exit 1
}

# Returns the list of Rancher host and volume Ids of all containers of the given service
# Parameters:
#   service name in the format 'stack/service'
# Output:
#   <Rancher-host-id> <Rancher-volume-id>
#   ...
get_host_and_volumeIds ()
{
    get_instanceIds $1 | while read instanceId; do
        #echo "instanceId=$instanceId"
        rancher inspect $instanceId --format '{{$hostId:=.hostId}}{{ range $index, $mount := .mounts }}{{$hostId}} {{$mount.volumeId}}{{"\n"}}{{end -}}' || exit 1
    done | sort -u
}

# Returns the hostname by Rancher host Id
# Parameters:
#   Rancher host Id
# Output:
#   hostname
get_hostname_by_hostId ()
{
    rancher inspect $1 --format '{{.hostname}}' || exit 1
}

# Returns the volume info by Rancher volume Id
# Parameters:
#   Rancher volume Id
# Output:
#   container-instance-name mount-path file-url
get_volumes_info_by_id ()
{
    rancher inspect $1 --format '{{$uri:=.uri}}{{ range $index, $mount := .mounts }}{{$mount.instanceName}} {{$mount.path}} {{$uri}}{{"\n"}}{{end -}}' || exit 1
}

get_host_and_volumeIds $1 | while read hostId volumeId; do
    #echo "hostId=$hostId volumeId=$volumeId"
    host_name=$(get_hostname_by_hostId $hostId)
    get_volumes_info_by_id $volumeId | while read volume_info; do
        echo "$host_name $volume_info"
    done
done | sort -u
