#!/bin/bash

# script out/output.log

# Configuration parameters
env_file='./../envs/env.json'
output_dir='./out/export'

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

out_credential_request() {
    bpn=$1
    mkdir -p $out_dir_credentials/$1
    echo "$out_dir_credentials/$1/credential_request.json"
}

out_credential_keep() {
    mkdir -p $out_dir_credentials/$1/keep

    filename="credential_$2.json"
    filename=${filename//:/_}  # Remove colons
    filename=${filename//\//_} # Remove forward slashes

    echo "$out_dir_credentials/$1/keep/$filename"
}

# Prepare skript run
mkdir -p $output_dir

out_logs=$output_dir/output.log
out_wallets_response=$output_dir/wallets_response.json
out_wallets=$output_dir/wallets.txt
out_issued_credentials_response=$output_dir/issued_credentials_response.json
out_issued_credentials=$output_dir/issued_credentials.txt
out_dir_credentials=$output_dir/credentials

remove_file $out_wallets_response
remove_file $out_wallets
remove_file $out_issued_credentials_response
remove_file $out_issued_credentials
remove_file $out_logs
remove_dir $out_dir_credentials

# Check if jq is installed
if ! command -v jq &>/dev/null; then
    echo "jq is not installed. Please install jq to proceed."
    exit 1
fi

log "-----------------"
log "Start reading wallets"
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

# Request Wallets
log_step_start "Requesting wallets"

http_status=$(curl -s -X GET $miw_url/api/wallets -o $out_wallets_response -w "\t%{http_code}" \
    --header 'Content-Type: application/json' \
    --header "Authorization: Bearer $access_token")
if [[ "$http_status" -ne 200 ]]; then
    log_step_mid_info "Get Wallets HTTP request failed with status code $http_status"
    exit 1
fi
log_step_mid "Wrote response to $out_wallets_response"
log_step_mid "Parsing wallet response..."
cat $out_wallets_response | jq -c '.content[]' | while read -r entry; do
    bpn=$(echo "$entry" | jq -r '.bpn')
    name=$(echo "$entry" | jq -r '.name')
    log_step_mid_info "Found BPN $bpn"
    touch $out_wallets
    echo $bpn:$name >>$out_wallets
done

log_step_mid "Wrote wallets to $out_wallets"
log_step_end

# Request Issued Credentials
log_step_start "Requesting credentials by wallets"

while IFS=: read -ra parts; do
    wallet_bpn=${parts[0]}

    log_step_mid "Wallet: $wallet_bpn"
    out_request_file=$(out_credential_request $wallet_bpn)
    http_status=$(curl -s -X GET "$miw_url/api/wallets/$wallet_bpn?withCredentials=true" -o $out_request_file -w "\t%{http_code}" \
        --header 'Content-T: application/json' \
        --header "Authorization: Bearer $access_token")
    if [[ "$http_status" -ne 200 ]]; then
        echo "Get issued credentials HTTP request failed with status code $http_status"
        exit 1
    fi

    cat $out_request_file | jq -c '.verifiableCredentials[]' | while read -r credential; do

        id=$(echo "$credential" | jq -r '.id')

        type=""
        while read -r t; do
            if [[ "$type" == "" ]]; then
                type=${t:1:-1} #remove quotes
            else
                type=$type,${t:1:-1} #remove quotes
            fi
        done <<<$(echo $credential | jq -c '.type[]')

        # if issud by operator
        if [[ "$type" == *"SummaryCredential"* ]]; then
            log_step_mid_info "Ignoring SummaryCredential (issued in combination with other cx-credentials)"
        elif [[ "$type" == *"BpnCredential"* ]]; then
            log_step_mid_info "Ignoring BpnCredential (issued during wallet creation)"
        elif [[ "$type" == *"DismantlerCredential"* ]]; then
            log_step_mid_info "Found DismantlerCredential for re-issuing"
            echo "$wallet_bpn;DismantlerCredential" >>$out_issued_credentials
        elif [[ "$type" == *"UseCaseFrameworkCondition"* ]]; then
            frameworktype=$(echo "$credential" | jq -r '.credentialSubject[0].type')
            contractTemplate=$(echo "$credential" | jq -r '.credentialSubject[0].contractTemplate')
            contractVersion=$(echo "$credential" | jq -r '.credentialSubject[0].contractVersion')
            log_step_mid_info "Found $frameworktype for re-issuing"
            echo "$wallet_bpn;UseCaseFrameworkCondition;$frameworktype;$contractTemplate;$contractVersion" >>$out_issued_credentials
        elif [[ "$type" == *"MembershipCredential"* ]]; then
            log_step_mid_info "Found MembershipCredential for re-issuing"
            echo "$wallet_bpn;MembershipCredential" >>$out_issued_credentials
        else
            log_step_mid_info "Third party credential $type ($id)"
            out=$(out_credential_keep $wallet_bpn $id)
            echo $credential >>$out
        fi

        # if credential was issued by MIW add it to issued credential list
        # if not store credential in folder
    done
done <<<$(cat $out_wallets)

log_step_mid "Wrote credentials to re-issue into $out_issued_credentials"
log_step_mid "Copied third party credentials into /out/<bpn>/keep/credentials_<id>.json"
log_step_end

# Write Sumamry
log_step_start "Summary"
log_step_mid "Found Wallets: $(grep -o -i "Found BPN " "$out_logs" | wc -l)"
log_step_mid "Found Credentials to re-issue: $(grep -o -i "Found.*Credential " "$out_logs" | wc -l)"
log_step_mid "Found Credentials to reinstantiate: $(grep -o -i "Third party credential " "$out_logs" | wc -l)"
log_step_end
