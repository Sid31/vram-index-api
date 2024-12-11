#!/bin/bash

# Set variables
ADMIN_ADDRESS="0x5088c377c10dc5466d9249321b068dacc98487e666de845990dd970bcc569927"
PACKAGE_ID="0x64efefcc5a540d229a9ce7accb02b4724af1af9507ac914f99ff484dab51fa0b"
CONFIG_ID="0x5941a48bcca8fa8568678deadc53274b607bfa07905793df8d29640a431e3675"

# Call pause function
sui client call --package $PACKAGE_ID \
    --module "launchpad" \
    --function "pause_pool" \
    --args $CONFIG_ID $ADMIN_ADDRESS true \
    --gas-budget 10000000 \
    --json
