#!/bin/bash

bearer=<copy token in here>
miw_api=https://managed-identity-wallets-new.int.demo.catena-x.net/api

csv_file="./../entries.csv"

# Read the CSV file line by line
while IFS='	' read -r bpn name
do
    # Perform an action with the columns
    echo "BPN: $bpn"
    echo "Name: $name"

   echo "CREATE WALLET"
  curl  -X POST --location "$miw_api/wallets" -o /dev/null -w "\t%{http_code}" \
  --header 'Content-Type: application/json' \
  --header "Authorization: Bearer $bearer" \
  --data "{ \"name\": \"managedWallet_$bpn\", \"bpn\": \"$bpn\" }"

  echo "CREATE MEMBERSHIP CREDENTIAL"
  curl -X POST --location '$miw_api/credentials/issuer/membership' -o /dev/null -w "\t%{http_code}" \
    --header 'Content-Type: application/json' \
    --header "Authorization: Bearer $bearer" \
    --data "{ \"bpn\": \"$bpn\" }"

done < "$csv_file"
