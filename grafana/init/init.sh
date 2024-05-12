#!/bin/bash

add_datasource ()
{
    for (( i=1; i<=60; i++ )); do
        echo "Adding Prometheus datasource to Grafana, Attempt #$i"
        curl -sS "http://admin:admin@grafana:3000/api/datasources" \
            -X POST \
            -H 'Content-Type: application/json;charset=UTF-8' \
            --data-binary \
            '{"name":"Prometheus","type":"prometheus","url":"http://prometheus.prometheus:9090","access":"proxy","isDefault":true}'
        if [[ $? == 0 ]]; then
            echo
            echo "Datasource added successfully"
            return
        fi
        sleep 5s
    done

    echo "Cannot add Prometheus datasource to Grafana"
    exit 1
}

add_dashboards ()
{
    local dashboards_dir=$1
    local postBodyFilename='/tmp/curlPostBodyFile.tmp'

    echo "Looking for dashboards in $dashboards_dir"
    for file in $dashboards_dir/*.json; do
        echo "Adding dashboard from $file"
        echo '{"dashboard":' > $postBodyFilename
        cat $file >> $postBodyFilename
        echo ',  "overwrite": false }' >> $postBodyFilename
        curl -sS "http://admin:admin@grafana:3000/api/dashboards/db" \
            -X POST \
            -H 'Content-Type: application/json;charset=UTF-8' \
            --data "@$postBodyFilename"
        echo
    done

    rm -f $postBodyFilename
}

add_datasource
add_dashboards $1