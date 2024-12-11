#!/bin/bash

# Configuration
RPC_URL="https://fullnode.devnet.sui.io:443"
PACKAGE_ID="0x64efefcc5a540d229a9ce7accb02b4724af1af9507ac914f99ff484dab51fa0b"
ADMIN_ADDRESS="0x5102ff6c5c12c899ca75c40dbbb1faa261e5d825f0185178b58e0c4c0ef8ab00"  # Replace with your admin address

# Function to call pause_pool
call_pause_pool() {
    echo "Calling pause_pool..."
    curl -X POST -H "Content-Type: application/json" -d '{
        "jsonrpc": "2.0",
        "id": 1,
        "method": "sui_executeTransactionBlock",
        "params": [
            "AAACAQEBAQEBAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAQEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgEBAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADAQEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==",
            {
                "signerAddress": "'$ADMIN_ADDRESS'",
                "signature": "BASE64_SIGNATURE_HERE",
                "requestType": "WaitForLocalExecution"
            }
        ]
    }' $RPC_URL
    echo -e "\n"
}

# Function to call unpause_pool
call_unpause_pool() {
    echo "Calling unpause_pool..."
    curl -X POST -H "Content-Type: application/json" -d '{
        "jsonrpc": "2.0",
        "id": 1,
        "method": "sui_executeTransactionBlock",
        "params": [
            "AAACAQEBAQEBAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAQEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgEBAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADAQEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==",
            {
                "signerAddress": "'$ADMIN_ADDRESS'",
                "signature": "BASE64_SIGNATURE_HERE",
                "requestType": "WaitForLocalExecution"
            }
        ]
    }' $RPC_URL
    echo -e "\n"
}

# Let's first get the admin's gas objects
get_gas_objects() {
    echo "Getting gas objects for admin..."
    curl -X POST -H "Content-Type: application/json" -d '{
        "jsonrpc": "2.0",
        "id": 1,
        "method": "suix_getOwnedObjects",
        "params": [
            "'$ADMIN_ADDRESS'",
            {
                "filter": {
                    "MatchAll": [
                        {
                            "StructType": "0x2::coin::Coin<0x2::sui::SUI>"
                        }
                    ]
                }
            },
            null,
            10
        ]
    }' $RPC_URL
    echo -e "\n"
}

# Main test sequence
echo "Starting event tests..."

echo "Getting gas objects..."
get_gas_objects

echo "Test 1: Pausing the pool"
call_pause_pool
sleep 5

echo "Test 2: Unpausing the pool"
call_unpause_pool
sleep 5

echo "Test 3: Pausing the pool again"
call_pause_pool
sleep 5

echo "Test 4: Final unpause"
call_unpause_pool

echo "Tests completed. Check the indexer output for events."
