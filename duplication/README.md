# Duplication Script

> Note: Please be aware that an export must be run before the import.


## What does the script

The export script does the following:


- Writes the existing wallets to `./out/export/wallets.txt`
- Writes the issued CX credentials to `./out/export/issued_credentials.txt`
- Writes all credential requests to `./out/export/credentials/<bpn>/*` (to have a backup)
- Writes all non-Catena-X credentials to `./out/export/credentials/<bpn>/keep/*` (but cannot be imported, see _Limitations_)

The import script does the following:

- Creates all wallets from  `./out/export/wallets.txt`
- Re-issues all CX credentials from  `./out/export/issued_credentials.txt`
- Tries to store credentials from `./out/export/credentials/<bpn>/keep/*` in their corresponding wallet (but this will not work, see _Limitations_)


## How to Run

1. Update [environment configuration](./envs/env.json) to the Managed Identity Wallet (MIW) that should be exported.
2. Run the [export.sh](./export.sh) script.
3. Update [environment configuration](./envs/env.json) to the MIW that should be imported.
4. Run the [import.sh](./import.sh) script.

## Limitations

- With the current API, it is not possible to put non-Catena-X credentials back into the wallets (but the script will still try to add them).
- It is possible that the MIW has wallets with invalid BPNs, which cannot be created anew when switching to a newer version.