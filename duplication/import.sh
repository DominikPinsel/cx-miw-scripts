#!/bin/bash

# Configuration parameters
env_file='./../envs/env.json'
output_dir='./out/import'
input_dir='./out/export'

log() {
    local timestamp
    timestamp=$(date +"[%Y-%m-%d %H:%M:%S]")
    echo -e "$timestamp $1"
    echo -e "$timestamp $1" >>$out_logs
}

log_step_start() {
    log "\t$1"
    log "\t\t-----------------"
}

log_step_mid() {
    log "\t\t$1"
}

log_step_mid_info() {
    log "\t\t\t$1"
}

log_step_end() {
    log "\t\t-----------------"
}

remove_file() {
    if [ -e "$1" ]; then
        rm -f "$1"
    fi
}

remove_dir() {
    if [ -e "$1" ]; then
        rm -r -f "$1"
    fi
}

issue_dismantler_credential() {
    local data="{ \"bpn\": \"$1\", \"activityType\": \"Dismantler Certificate\", \"allowedVehicleBrands\": [] }"
    issue_credential DismantlerCredential /dismantler "$data"
}

issue_membership_credential() {
    local data="{ \"bpn\": \"$1\" }"
    issue_credential MembershipCredential /membership "$data"
}

issue_framework_credential() {
    local bpn=$1
    local type=$2
    local template=$3
    local version=$4
    local data="{ \"holderIdentifier\": \"$bpn\",\"value\": \"ID_3.0_Trace\", \"type\": \"$type\", \"contract-template\": \"$template\", \"contract-version\": \"$version\" }"
    issue_credential UseCaseFrameworkCondition /framework "$data"
}

issue_credential() {
    local name=$1
    local path=$2
    local data=$3

    http_status=$(curl -s -X POST "$miw_url/api/credentials/issuer$path" -o "/dev/null" -w "\t%{http_code}" \
        --header 'Content-Type: application/json' \
        --header "Authorization: Bearer $access_token" \
        --data-raw "$data")
    if [[ "$http_status" -eq 201 ]]; then
        log_step_mid_info "Created"
    elif [[ "$http_status" -eq 409 ]]; then
        log_step_mid_info "Already exists"
    else
        log_step_mid_info "Issue $name HTTP request failed with status code $http_status"
    fi
}

store_credential() {
    local bpn=$1
    local data=$2

    http_status=$(curl -s -X POST "$miw_url/api/wallets/$bpn/credentials" -o "/dev/null" -w "\t%{http_code}" \
        --header 'Content-Type: application/json' \
        --header "Authorization: Bearer $access_token" \
        --data-raw "$data")
    if [[ "$http_status" -eq 201 ]]; then
        log_step_mid_info "Created"
    elif [[ "$http_status" -eq 409 ]]; then
        log_step_mid_info "Already exists"
    else
        log_step_mid_info "Store Credential HTTP request failed with status code $http_status"
    fi
}

# Prepare skript run
in_wallets=$input_dir/wallets.txt
in_credentials=$input_dir/issued_credentials.txt
out_logs=$output_dir/output.log
input_credentials_dir=$input_dir/credentials

mkdir -p $output_dir
remove_file $out_logs

# Check if jq is installed
if ! command -v jq &>/dev/null; then
    echo "jq is not installed. Please install jq to proceed."
    exit 1
fi

log "-----------------"
log "Start importing wallets"
log "-----------------"

# Read the environment file
log_step_start "Reading environment from $env_file:"
env=$(cat $env_file)
miw_url=$(echo $env | jq -r '.miw.url')
miw_operator_bpn=$(echo $env | jq -r '.miw.operator.bpn')
keycloak_url=$(echo $env | jq -r '.keycloak.url.token')
keycloak_client=$(echo $env | jq -r '.keycloak.client.id')
keycloak_secret=$(echo $env | jq -r '.keycloak.client.secret')
log_step_mid "Keycloak URL: $keycloak_url"
log_step_mid "Keycloak Client ID: $keycloak_client"
log_step_mid "Keycloak Client Secret: **********"
log_step_mid "MIW URL: $miw_url"
log_step_mid "MIW Operator BPN: $miw_operator_bpn"
log_step_end

# Get Bearer Token
log_step_start "Requesting access token"
response=$(curl -s -X POST "$keycloak_url" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=$keycloak_client" \
    -d "client_secret=$keycloak_secret" \
    -d "grant_type=client_credentials")
access_token=$(echo "$response" | jq -r '.access_token')
if [ -z "$access_token" ]; then
    echo "Failed to obtaout_wallets_responsein the access token."
    exit 1
fi
log_step_mid "Token: $(echo "$access_token" | cut -c 1-20)..."
log_step_end

# Create Wallets
log_step_start "Creating wallets"
while IFS=: read -ra parts; do
    walletBpn=${parts[0]}
    walletName=${parts[1]}

    http_status=$(curl -s -X POST "$miw_url/api/wallets" -o "/dev/null" -w "\t%{http_code}" \
        --header 'Content-Type: application/json' \
        --header "Authorization: Bearer $access_token" \
        --data-raw "{ \"name\": \"$walletName\", \"bpn\": \"$walletBpn\"}")
    if [[ "$http_status" -eq 201 ]]; then
        log_step_mid_info "Created Wallet $walletBpn"
    elif [[ "$http_status" -eq 409 ]]; then
        log_step_mid_info "Wallet $walletBpn already exists"
    else
        log_step_mid_info "Create HTTP request failed with status code $http_status"
    fi

done <<<$(cat $in_wallets)
log_step_end

# Re-issue Catena-X Credentials
log_step_start "Re-issuing Catena-X Credentials"

while IFS=';' read -ra parts; do
    credentialBpn=${parts[0]}
    credentialType=${parts[1]}

    if [[ "$credentialType" == "MembershipCredential" ]]; then
        log_step_mid "Issuing MembershipCredential for $credentialBpn"
        issue_membership_credential $credentialBpn
    elif [[ "$credentialType" == "DismantlerCredential" ]]; then
        log_step_mid "Issuing DismantlerCredential for $credentialBpn"
        issue_dismantler_credential $credentialBpn
    elif [[ "$credentialType" == "UseCaseFrameworkCondition" ]]; then
        frameworktype=${parts[2]}
        contractTemplate=${parts[3]}
        contractVersion=${parts[4]}
        log_step_mid "Issuing $frameworktype for $credentialBpn"
        issue_framework_credential $credentialBpn $frameworktype $contractTemplate $contractVersion
    else
        log_step_mid_info "Unknown credential type $credentialType"
        exit 1
    fi

done <<<$(cat $in_credentials)
log_step_end

# Re-instating Other Credentials
log_step_start "Re-instating other Credentials"

for folder in $(find "$input_credentials_dir" -maxdepth 1 -type d); do
    keepFolder="$folder/keep"
    if [ -d "$keepFolder" ]; then
        credentialBpn=$(basename "$folder")
        log_step_mid "Re-instating $credentialBpn"
        for file in $(find "$keepFolder" -maxdepth 1 -type f); do
            if [ -f $file ]; then
                credentialId=$(basename "$file")
                log_step_mid_info "Re-instating $credentialId"
                store_credential $credentialBpn "$(cat $file)"
            fi
        done
    fi
done
log_step_end

# Summary
log_step_start "Summary"
log_step_mid "Created Wallets: $(grep -o -i "Created Wallet " "$out_logs" | wc -l)"
log_step_mid "Wallet already existed: $(grep -o -i "Wallet.*already exists" "$out_logs" | wc -l)"
log_step_mid "Re-issued Credentials: $(grep -o -i "Issuing.*Credential for " "$out_logs" | wc -l) (check log for success)"
log_step_mid "Re-instated Credentials: $(grep -o -i "Re-instating.*json" "$out_logs" | wc -l) (check logs for success)"
