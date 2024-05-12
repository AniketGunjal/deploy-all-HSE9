#!/bin/bash
#
# Deploy all components necessary to Report Service
#

# stop path conversion for msys in windows
export MSYS_NO_PATHCONV=1

tempfiles=()
cleanup() {
    rm -f "${tempfiles[@]}"
}
trap cleanup 0

help() {
    echo "Usage:"
    echo "  $0 parameters..."
    echo ""
    echo "parameters:"
    echo "  --help             - Show help and exit"
    echo "  report-service     - deploy Report Service"
    echo "  report-service-db  - deploy Postgres DB for Report Service"
    echo "  exporthub          - deploy ExportHub Service, Postgres DB and RabbitMQ for it"
    echo "  exporthub-service  - deploy ExportHub Service alone"
    echo "  exporthub-db       - deploy Postgres DB for ExportHub Service"
    echo "  exporthub-rabbitmq - deploy RabbitMQ for ExportHub Service"
    echo "  exporthub-activemq - deploy ActiveMQ for ExportHub Service"
    echo "  change-logging     - deploy Change Logging"
    echo "  camunda            - deploy Camunda"
    echo "  vault              - deploy Hashicorp Vault"
    echo "  keycloak           - deploy Keycloak"
    echo "  keycloak-postgres  - deploy Keycloak on PostreSQL (requires keycloak)"
}

# Join words using a separator character
# Parameters:
#   separator_character word0 word1...
join_by() {
    local IFS="$1"
    shift
    echo "$*"
}

# Count the number of occurences of character in the string
# Parameters:
#   string character
# Output: number of occurences of character in the string
char_count() {
    local str=$1
    local ch=$2
    local res="${str//[^$ch]/}"
    echo "${#res}"
}

# Generate a temporary filename based on the pattern specified as a parameter.
# Adds a generated filename to a list of files to be deleted after the script is stopped.
# Sets a global variable 'tempfilename' to a generated filename
# Parameters:
#   filename pattern in the format accepted by 'mktemp'
generate_tempfilename() {
    tempfilename=$(mktemp -u "$1")
    tempfiles+=("$tempfilename")
}

# Output the content of the file substituting all environment variable references with their values
# Parameters:
#   filename
substitute_variables_in_file() {
    awk -f util/envsubst.awk < "$1"
}

# Returns zero error code if the Rancher stack exists
# Parameters:
#   stack name
is_stack_exist() {
    rancher stacks ls --format '{{.Stack.Name}}' 2>&1 | grep -Fx "$1" > /dev/null
}

# Returns the list of public endpoints of the given service
# Parameters:
#   service name in the format 'stack/service'
# Output:
#   <ip-address>:<port>
#   ...
get_public_endpoints() {
    local service=$1
    rancher --wait --wait-state healthy wait "$service" 1> /dev/null 2>&1
    # shellcheck disable=SC2016
    rancher --wait --wait-state healthy inspect "$service" --format '{{ range $index, $element := .publicEndpoints }}{{$element.ipAddress}}:{{$element.port}}{{"\n"}}{{end -}}'
}

# Deploy a Rancher stack from docker-compose.yml and rancher-compose.yml files located in a specified folder
# Parameters:
#   stack name
#   folder name
#   [environment file]
#   [non-empty if do variable substitution in environment file]
deploy_from_folder() {
    local stack_name=$1
    local folder_name=$2
    local env_file=$3
    local do_var_subst=$4

    echo "Deploying '$stack_name' from folder '$folder_name'. Environment file is '$env_file'"
    if is_stack_exist "$stack_name"; then
        echo "Stack '$stack_name' exists. Skipping deployment"
        return 1
    else
        local cmd_opts=()
        if [[ -n $env_file ]]; then
            cmd_opts[0]="--env-file"
            if [[ -n $do_var_subst ]]; then
                generate_tempfilename ./env-file.txt.XXXX
                substitute_variables_in_file "$env_file" > "$tempfilename"
                cmd_opts[1]="$tempfilename"
            else
                cmd_opts[1]="$env_file"
            fi
        fi
        rancher --wait --wait-state active up --file "$folder_name/docker-compose.yml" -rancher-file "$folder_name/rancher-compose.yml" --stack "$stack_name" -d "${cmd_opts[@]}" || exit 1
        echo "Stack '$stack_name' deployed"
    fi
    return 0
}

# shellcheck disable=SC2155
deploy_prometheus() {
    # parse C8 URL
    local parts=$(echo "$C8_URL" | awk -f util/parse_url.awk)

    # create variables used in prometheus/prometheus.yml
    export c8_url_scheme="$(echo "$parts" | cut -d';' -f1)"
    export c8_url_host="$(echo "$parts" | cut -d';' -f2)"
    export c8_url_port="$(echo "$parts" | cut -d';' -f3)"
    if [ -z "$kafka_bootstrap_servers" ]; then
        export kafka_bootstrap_servers=$(hosts_with_label kafka | merge_with_suffix ',' ':9092')
    fi

    generate_tempfilename ./prometheus.yml.XXXX
    substitute_variables_in_file prometheus/prometheus.yml > "$tempfilename"

    export PROMETHEUS_CONFIG=$(cat "$tempfilename")
    deploy_from_folder prometheus prometheus prometheus/env-file.txt 1

}

# shellcheck disable=SC2155
deploy_grafana() {
    export GRAFANA_INIT=$(cat grafana/init/init.sh)
    export GRAFANA_C8_REPORT_SERVICE_STATS=$(cat grafana/dashboards/C8_ReportService_Stats.json)
    export GRAFANA_HOST_STATS=$(cat grafana/dashboards/Docker_and_system_Stats.json)
    export GRAFANA_PROMETHEUS_STATS=$(cat grafana/dashboards/Prometheus_Stats.json)
    export GRAFANA_KAFKA_STATS=$(cat grafana/dashboards/Kafka_Stats.json)
    export GRAFANA_RANCHER_STATS=$(cat grafana/dashboards/Rancher_Stats.json)
    export GRAFANA_SMTP_HOST=$SMTP_HOST
    export GRAFANA_SMTP_USERNAME=$SMTP_USERNAME
    export GRAFANA_SMTP_PASSWORD=$SMTP_PASSWORD
    export GRAFANA_SMTP_FROM_ADDRESS=$SMTP_FROM
    GRAFANA_DOMAIN=$(hosts_with_label grafana | head -n 1)
    export GRAFANA_DOMAIN=${GRAFANA_DOMAIN:-grafana}

    deploy_from_folder grafana grafana
}

# Output a list of hosts with a specified label set to 'true'
# Parameters:
#   label to find
# Output format:
#   IP addresses of such servers each on a separate line
hosts_with_label() {
    local label=$1
    rancher hosts ls --format "{{.Host.AgentIpAddress}} {{.Labels}}" 2>&1 | grep "$label=true" | sed 's/ .*//'
}

# Output a list of hosts with a specified label set to 'true'
# Parameters:
#   label to find
# Output format:
#   1=<ip-addr1>;2=<ip-addr2>;...
hosts_with_label_map() {
    local label=$1
    local server_index=1
    for line in $(hosts_with_label "$label"); do
        if [[ $server_index -gt 1 ]]; then
            printf ";"
        fi
        printf "%u=%s" $server_index "$line"
        ((server_index++))
    done
}

# Reads standard input and merge all lines into one with a specified suffix and separator
# Parameters:
#   separator
#   suffix
# Output format:
#   <ip-addr1><suffix><separator><ip-addr2><suffix><separator>...<ip-addrN><suffix>
merge_with_suffix() {
    local separator=$1
    local suffix=$2
    local index=1
    while read -r line; do
        if [[ $index -gt 1 ]]; then
            printf "%s" "$separator"
        fi
        printf "%s%s" "$line" "$suffix"
        ((index++))
    done
}

# Deploy Zookeeper/Kafka stack from a specified folder
# Parameters:
#   stack name
#   folder name
#   environment file
# shellcheck disable=SC2155
deploy_zookeeper_kafka() {
    local stack_name=$1
    local folder_name=$2
    local env_file=$3

    if is_stack_exist "$stack_name"; then
        echo "Stack '$stack_name' exists. Skipping deployment"
    else
        echo "Discovering hosts to deploy Zookeeper"

        # count hosts with zookeeper=true label
        local zookeeper_hosts_count=$(hosts_with_label zookeeper | wc -l)
        export zookeeper_hosts=$(seq "${zookeeper_hosts_count}" | sed 's/.*/\0='"${stack_name}"'-zk-\0/' | merge_with_suffix ';')
        if [[ -z $zookeeper_hosts ]]; then
            echo "Cannot find hosts with label 'zookeeper=true'"
            exit 1
        fi
        echo "Zookeeper hosts: $zookeeper_hosts"

        echo "Discovering hosts to deploy Kafka"
        export kafka_zookeeper_connect="zk.${stack_name}:2181"
        export kafka_bootstrap_servers=$(hosts_with_label kafka | merge_with_suffix ',' ':9092')
        if [[ -z $kafka_bootstrap_servers ]]; then
            echo "Cannot find hosts with label 'kafka=true'"
            exit 1
        fi
        echo "Zookeeper hosts for Kafka: $kafka_zookeeper_connect"
        echo "Kafka bootstrap servers: $kafka_bootstrap_servers"

        export kafka_num_insync_replicas=$(char_count "$kafka_bootstrap_servers" ',')
        ((kafka_num_replicas = kafka_num_insync_replicas + 1))
        export kafka_num_replicas

        deploy_from_folder "$stack_name" "$folder_name" "$env_file" 1
    fi
}

# Deploy Change Logging stack from a folder
# Parameters:
#   stack name
#   folder name
#   environment file
# shellcheck disable=SC2155
deploy_change_logging() {
    local stack_name=$1
    local folder_name=$2
    local env_file=$3

    if is_stack_exist "$stack_name"; then
        echo "Stack '$stack_name' exists. Skipping deployment"
    else
        export zookeeper_hosts='zk.zookeeper-kafka.rancher.internal:2181'
        if [[ -z $zookeeper_hosts ]]; then
            echo "Cannot find Zookeeper service"
            exit 1
        fi
        echo "Zookeeper hosts: $zookeeper_hosts"

        export kafka_hosts=$(join_by , "$(get_public_endpoints zookeeper-kafka/kafka | grep ':9092')")
        if [[ -z $kafka_hosts ]]; then
            echo "Cannot find Kafka service"
            exit 1
        fi
        echo "Kafka hosts: $kafka_hosts"

        ((kafka_num_replicas = $(char_count "$kafka_hosts" ',') + 1))
        export kafka_num_replicas

        deploy_from_folder "$stack_name" "$folder_name" "$env_file" 1
    fi
}

# Deploy Camunda stack from a folder
# Parameters:
#   stack name
#   folder name
#   environment file
# shellcheck disable=SC2155
deploy_camunda() {
    local stack_name=$1
    local folder_name=$2
    local env_file=$3

    export C8_ENCRYPTED_PASSWORD=$(echo -n "${C8_PASSWORD}" | openssl aes-128-cbc -e -a -nosalt -K 61386566323835346364396831366139 -iv 33613033623464323064663367396165)

    deploy_from_folder "$stack_name" "$folder_name" "$env_file" 1
}

# Deploy Keycloak stack from a folder
# Parameters:
#   stack name
#   folder name
#   environment file
# shellcheck disable=SC2155
deploy_keycloak() {
    local stack_name=$1
    local folder_name=$2
    local env_file=$3

    deploy_from_folder "$stack_name" "$folder_name" "$env_file" 1
}

deploy_vault() {
    local stack_name=$1
    local folder_name=$2

    VAULT_DIR=${VAULT_DIR:-vault/config/certs}

    #required files
    export VAULT_CERT=${VAULT_CERT:-$VAULT_DIR/vault.crt}
    export VAULT_KEY=${VAULT_KEY:-$VAULT_DIR/vault.key}
    export VAULT_ROOTCA_CERT=${VAULT_ROOT_CA:-$VAULT_DIR/rootCA.crt}

    #required to create certificate
    VAULT_ROOTCA_KEY=${VAULT_ROOTCA_KEY:-$VAULT_DIR/rootCA.key}
    VAULT_ROOTCA_PASSWORD=${VAULT_ROOTCA_PASSWORD:-centric8}

    #more settings
    VAULT_CSR=${VAULT_CSR:-$VAULT_DIR/vault.csr}
    VAULT_EXT=${VAULT_EXT:-$VAULT_DIR/vault.ext}
    VAULT_CERT_LIFE=${VAULT_CERT_LIFE:-365}
    VAULT_SUBJ=${VAULT_SUBJ:-"/CN=localhost, ou=IT, o=Centric Software Inc., c=US"}

    if [ -r "$VAULT_ROOTCA_CERT" ] && [ -r "$VAULT_CERT" ] && [ -r "$VAULT_KEY" ]; then
        echo "Using existing root CA and vault certificate"
    elif [ \( ! -r "$VAULT_ROOTCA_CERT" \) ] && [ \( ! -r "$VAULT_ROOTCA_KEY" \) ] && [ \( ! -r "$VAULT_CERT" \) ] && [ \( ! -r "$VAULT_KEY" \) ]; then
        echo "No vault certificate or root CA found, creating them"
        test -d "$VAULT_DIR" || mkdir -p "$VAULT_DIR"
        cat << EXTFILE > "$VAULT_EXT"
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
subjectAltName = @alt_names
[alt_names]
DNS.1 = vault
EXTFILE
        openssl req -x509 -sha256 -days "$VAULT_CERT_LIFE" -newkey rsa:2048 -keyout "$VAULT_ROOTCA_KEY" -out "$VAULT_ROOTCA_CERT" -subj "$VAULT_SUBJ" -passout pass:"$VAULT_ROOTCA_PASSWORD"
        openssl req -newkey rsa:2048 -nodes -keyout "$VAULT_KEY" -out "$VAULT_CSR" -subj "$VAULT_SUBJ"
        openssl x509 -req -CA "$VAULT_ROOTCA_CERT" -CAkey "$VAULT_ROOTCA_KEY" -in "$VAULT_CSR" -out "$VAULT_CERT" -days "$VAULT_CERT_LIFE" -CAcreateserial -extfile "$VAULT_EXT" -passin pass:"$VAULT_ROOTCA_PASSWORD"
    elif [ -r "$VAULT_ROOTCA_CERT" ] && [ -r "$VAULT_ROOTCA_KEY" ]; then
        echo "Creating new vault certificate from existing root CA"
        if [ -z "$VAULT_ROOTCA_PASSWORD" ]; then
            echo "Root CA password is required"
            exit 1
        fi
        cat << EXTFILE > "$VAULT_EXT"
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
subjectAltName = @alt_names
[alt_names]
DNS.1 = vault
EXTFILE
        openssl req -newkey rsa:2048 -nodes -keyout "$VAULT_KEY" -out "$VAULT_CSR" -subj "$VAULT_SUBJ"
        openssl x509 -req -CA "$VAULT_ROOTCA_CERT" -CAkey "$VAULT_ROOTCA_KEY" -in "$VAULT_CSR" -out "$VAULT_CERT" -days "$VAULT_CERT_LIFE" -CAcreateserial -extfile "$VAULT_EXT" -passin pass:"$VAULT_ROOTCA_PASSWORD"
    else
        echo -e "Invalid vault certificate files.  All of these files are required:\n$VAULT_ROOTCA_CERT\n$VAULT_CERT\n$VAULT_KEY"
        exit 1
    fi

    VAULT_CONFIG_CONTENT=$(cat vault/config/vault.json)
    export VAULT_CONFIG_CONTENT

    VAULT_ROOTCA_CONTENT=$(cat "$VAULT_ROOTCA_CERT")
    export VAULT_ROOTCA_CONTENT

    VAULT_CERT_CONTENT=$(cat "$VAULT_CERT")
    export VAULT_CERT_CONTENT

    VAULT_KEY_CONTENT=$(cat "$VAULT_KEY")
    export VAULT_KEY_CONTENT

    deploy_from_folder "$stack_name" "$folder_name"
}

unset CHANGE_LOGGING_DOCKER_IMAGE_VERSION EXPORTHUB_SERVICE_DOCKER_IMAGE_VERSION REPORTDB_SERVICE_DOCKER_IMAGE_VERSION CAMUNDA_DOCKER_IMAGE_VERSION

unset supported_versions
declare -A supported_versions

if [ -r util/supported-versions.sh ]; then
    # Include the file with all supported versions produced by the build
    # shellcheck disable=SC1091
    source util/supported-versions.sh

    CHANGE_LOGGING_DOCKER_IMAGE_VERSION=${supported_versions['change-logging_current']}
    EXPORTHUB_SERVICE_DOCKER_IMAGE_VERSION=${supported_versions['exporthub_current']}
    REPORTDB_SERVICE_DOCKER_IMAGE_VERSION=${supported_versions['report-service_current']}
    CAMUNDA_DOCKER_IMAGE_VERSION=${supported_versions['camunda_current']}
    KEYCLOAK_IMAGE_VERSION=${supported_versions['keycloak_current']}
fi

#---------------------------------------------------------------------------------------------------
#       Parse parameters
#---------------------------------------------------------------------------------------------------
kafka=false
report_service=false
report_service_db=false
exporthub_service=false
exporthub_db=false
exporthub_rabbitmq=false
exporthub_activemq=false
change_logging=false
camunda=false
vault=false
keycloak=false
keycloak_postgres=false
while [[ $# -gt 0 ]]; do
    read -r SERVICE VERSION <<< "${1//:/ }"
    case $SERVICE in
    report-service)
        if [ "$VERSION" ]; then
            if [ -n "${supported_versions['report-service_'${VERSION}]}" ]; then
                export REPORTDB_SERVICE_DOCKER_IMAGE_VERSION=$VERSION
            else
                echo Version "$VERSION" of report service is not supported
                exit 1
            fi
        fi
        kafka=true
        report_service=true
        shift
        ;;
    report-service-db)
        report_service_db=true
        shift
        ;;
    exporthub)
        if [ "$VERSION" ]; then
            if [ -n "${supported_versions['exporthub_'${VERSION}]}" ]; then
                export EXPORTHUB_SERVICE_DOCKER_IMAGE_VERSION=$VERSION
            else
                echo Version "$VERSION" of exporthub is not supported
                exit 1
            fi
        fi
        kafka=true
        exporthub_service=true
        exporthub_db=true
        exporthub_rabbitmq=true
        shift
        ;;
    exporthub-service)
        if [ "$VERSION" ]; then
            if [ -n "${supported_versions['exporthub_'${VERSION}]}" ]; then
                export EXPORTHUB_SERVICE_DOCKER_IMAGE_VERSION=$VERSION
            else
                echo Version "$VERSION" of exporthub is not supported
                exit 1
            fi
        fi
        kafka=true
        exporthub_service=true
        shift
        ;;
    exporthub-db)
        exporthub_db=true
        shift
        ;;
    exporthub-rabbitmq)
        exporthub_rabbitmq=true
        shift
        ;;
    exporthub-activemq)
        exporthub_activemq=true
        shift
        ;;
    change-logging)
        if [ "$VERSION" ]; then
            if [ -n "${supported_versions['change-logging_'${VERSION}]}" ]; then
                export CHANGE_LOGGING_DOCKER_IMAGE_VERSION=$VERSION
            else
                echo Version "$VERSION" of change-logging is not supported
                exit 1
            fi
        fi
        kafka=true
        change_logging=true
        shift
        ;;
    camunda)
        if [ "$VERSION" ]; then
            if [ -n "${supported_versions['camunda_'${VERSION}]}" ]; then
                export CAMUNDA_DOCKER_IMAGE_VERSION=$VERSION
            else
                echo Version "$VERSION" of camunda is not supported
                exit 1
            fi
        fi
        camunda=true
        shift
        ;;
    keycloak)
        if [ "$VERSION" ]; then
            if [ -n "${supported_versions['keycloak_'${VERSION}]}" ]; then
                export KEYCLOAK_IMAGE_VERSION=$VERSION
            else
                echo Version "$VERSION" of keycloak is not supported
                exit 1
            fi
        fi
        keycloak=true
        shift
        ;;
    keycloak-postgres)
        keycloak_postgres=true
        shift
        ;;
    vault)
        vault=true
        shift
        ;;
    --help)
        help
        exit 1
        ;;
    *)
        echo "Invalid parameter $1"
        help
        exit 1
        ;;
    esac
done

export CHANGE_LOGGING_DOCKER_IMAGE_VERSION EXPORTHUB_SERVICE_DOCKER_IMAGE_VERSION REPORTDB_SERVICE_DOCKER_IMAGE_VERSION CAMUNDA_DOCKER_IMAGE_VERSION

#---------------------------------------------------------------------------------------------------
#       Supporting stacks
#---------------------------------------------------------------------------------------------------

# pull parameters for deployment as environment variables from .properties file

# remove carriage returns from the file first
generate_tempfilename ./parameters.properties.XXXX
corrected_parameters_file=$tempfilename
tr -d '\r' < ./parameters.properties > "$corrected_parameters_file"

set -o allexport
while IFS='=' read -r var_name var_value; do
    if [[ ! "$var_name" =~ ^.*# && -n "$var_name" ]]; then
        declare "$var_name"="$var_value"
    fi
done < "$corrected_parameters_file"
set +o allexport

#---------------------------------------------------------------------------------------------------
#       Zookeeper/Kafka
#---------------------------------------------------------------------------------------------------

if [ $kafka == "true" ]; then
    deploy_zookeeper_kafka zookeeper-kafka zookeeper-kafka zookeeper-kafka/env-file.txt
fi

#---------------------------------------------------------------------------------------------------
#       Report Service
#---------------------------------------------------------------------------------------------------

if [ $report_service == "true" ]; then
    deploy_from_folder c8-report-service report-service report-service/env-file.txt 1
fi
if [ $report_service_db == "true" ]; then
    # Report Service Postgres DB
    deploy_from_folder c8-report-service-db report-service-db
fi

#---------------------------------------------------------------------------------------------------
#       Change Logging
#---------------------------------------------------------------------------------------------------

if [ $change_logging == "true" ]; then
    # Mongo DB
    deploy_from_folder mongodb mongodb mongodb/env-file.txt 1

    # Change Logging service
    deploy_change_logging c8-change-logging change-logging change-logging/env-file.txt
fi

#---------------------------------------------------------------------------------------------------
#       ExportHub Service
#---------------------------------------------------------------------------------------------------

if [ $exporthub_db == "true" ]; then
    # ExportHub Postgres DB
    deploy_from_folder c8-exporthub-db exporthub-db
fi

if [ $exporthub_rabbitmq == "true" ]; then
    # ExportHub RabbitMQ
    deploy_from_folder c8-exporthub-rabbitmq exporthub-rabbitmq
    export exporthub_notification_messaging_protocol=AMQP-0.9
fi

if [ $exporthub_activemq == "true" ]; then
    # ExportHub ActiveMQ
    deploy_from_folder c8-exporthub-activemq exporthub-activemq exporthub-activemq/env-file.txt 1
    export exporthub_notification_messaging_protocol=AMQP-1.0
fi

if [ $exporthub_service == "true" ]; then
    # ExportHub service
    deploy_from_folder c8-exporthub-service exporthub-service exporthub-service/env-file.txt 1
fi

#---------------------------------------------------------------------------------------------------
#       Camunda
#---------------------------------------------------------------------------------------------------

if [ $camunda == "true" ]; then
    # Camunda Postgres DB
    deploy_from_folder c8-camunda-db camunda-db

    # Camunda service
    deploy_camunda c8-camunda camunda-service camunda-service/env-file.txt
fi

if [ $vault == "true" ]; then
    # Hashicorp Vault
    deploy_vault c8-vault vault
fi

#---------------------------------------------------------------------------------------------------
#       Keycloak
#---------------------------------------------------------------------------------------------------

# Keycloak Server
if [ $keycloak == "true" ]; then
    # Keycloak
    deploy_keycloak c8-keycloak keycloak keycloak/env-file.txt

    # Keycloak Postgres Database
    if [ $keycloak_postgres == "true" ]; then
        # Postgres DB for Keycloak
        deploy_from_folder c8-keycloak-postgres keycloak-postgres keycloak-postgres/env-file.txt
    fi
fi

#---------------------------------------------------------------------------------------------------
#       Prometheus/Grafana
#---------------------------------------------------------------------------------------------------

# Prometheus
deploy_prometheus

# Grafana
deploy_grafana
