#!/bin/bash

# Set up environment variables
ADMIN_ADDRESS="0x5088c377c10dc5466d9249321b068dacc98487e666de845990dd970bcc569927"  # Using active address
USER1_ADDRESS="0x5088c377c10dc5466d9249321b068dacc98487e666de845990dd970bcc569927"  # Using same address for testing
USER2_ADDRESS="0x5088c377c10dc5466d9249321b068dacc98487e666de845990dd970bcc569927"  # Using same address for testing
PACKAGE_ID="0x64efefcc5a540d229a9ce7accb02b4724af1af9507ac914f99ff484dab51fa0b"  # Package ID from indexer
CONFIG_ID="0x584a39b88c979ce0a3523041a2f1194bd0376bab2f573394e045f5872b8e1617"    # Config ID
CLOCK_ID="0x6"    # System clock object ID
VESTING_DURATION=604800000  # 7 days in milliseconds
AMOUNT=1000000000  # 1 SUI
LAUNCHPAD_ID="0xbbe5c8f4381e0ac03d114962d55868baa37e7248f95066fb044999db74cd2496"  # Previously created launchpad

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to log messages with timestamp
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    case $level in
        "INFO")
            echo -e "${GREEN}[$timestamp INFO] $message${NC}"
            ;;
        "ERROR")
            echo -e "${RED}[$timestamp ERROR] $message${NC}"
            ;;
        "DEBUG")
            if [ ! -z "$DEBUG" ]; then
                echo -e "${BLUE}[$timestamp DEBUG] $message${NC}"
            fi
            ;;
    esac
}

# Function to log transaction details
log_transaction() {
    local tx_output="$1"
    local operation="$2"
    
    log_message "INFO" "=== Transaction Details for $operation ==="
    echo "$tx_output"
    log_message "INFO" "=== End Transaction Details ==="
}

# Function to get a gas coin with sufficient balance
get_gas_coin() {
    local min_balance=$1
    local coins_output=$(sui client gas --json)
    echo "$coins_output" | jq -r ".[] | select(.mistBalance >= $min_balance) | .gasCoinId" | head -n 1
}

# Start test scenarios
log_message "INFO" "Starting Launchpad Test Scenarios..."

# Get a gas coin for the creation fee (minimum 0.1 SUI = 100000000)
GAS_COIN=$(get_gas_coin 100000000)
if [ -z "$GAS_COIN" ]; then
    log_message "ERROR" "No gas coin with sufficient balance found for creation fee (need minimum 0.1 SUI)"
    exit 1
fi
log_message "INFO" "Using gas coin: $GAS_COIN for creation fee"

# Test 1: Create Launchpad
log_message "INFO" "Test 1: Creating Launchpad"
log_message "DEBUG" "Creating launchpad with config ID: $CONFIG_ID"

CREATION_OUTPUT=$(sui client call \
    --package "$PACKAGE_ID" \
    --module "launchpad" \
    --function "create_launchpad" \
    --args \
    "$CONFIG_ID" \
    "Test Token" \
    "Test Description" \
    "https://twitter.com/test" \
    "https://discord.gg/test" \
    1000 \
    100 \
    1000000 \
    false \
    "[]" \
    true \
    $VESTING_DURATION \
    true \
    "$ADMIN_ADDRESS" \
    "$GAS_COIN" \
    "$CLOCK_ID" \
    --gas-budget 100000000)

log_transaction "$CREATION_OUTPUT" "Launchpad Creation"

# Extract Launchpad ID from transaction output
echo "DEBUG: Full creation output:"
echo "$CREATION_OUTPUT"
echo "DEBUG: After grep -A 2 'Created Objects:':"
echo "$CREATION_OUTPUT" | grep -A 2 "Created Objects:"
echo "DEBUG: After grep '│ ID:':"
echo "$CREATION_OUTPUT" | grep -A 2 "Created Objects:" | grep "│ ID:"
LAUNCHPAD_ID=$(echo "$CREATION_OUTPUT" | grep -A 2 "Created Objects:" | grep "│ ID:" | head -n 1 | awk -F': ' '{print $2}' | tr -d ' ' | tr -d '│')
echo "DEBUG: Extracted LAUNCHPAD_ID: $LAUNCHPAD_ID"
if [ -z "$LAUNCHPAD_ID" ]; then
    log_message "ERROR" "Failed to extract launchpad ID from creation output"
    exit 1
fi
log_message "INFO" "Created Launchpad ID: $LAUNCHPAD_ID"

# Test 2: Buy Tokens
log_message "INFO" "Test 2: Buying Tokens"
GAS_COIN=$(get_gas_coin 100000)
if [ -z "$GAS_COIN" ]; then
    log_message "ERROR" "No gas coin with sufficient balance found for buying tokens"
    exit 1
fi
log_message "INFO" "Using gas coin: $GAS_COIN for buying tokens"

BUY_OUTPUT=$(sui client call \
    --package "$PACKAGE_ID" \
    --module "launchpad" \
    --function "buy_tokens_with_sui_entry" \
    --args \
    "$CONFIG_ID" \
    "$LAUNCHPAD_ID" \
    "$GAS_COIN" \
    "$CLOCK_ID" \
    --gas-budget 100000000)

log_transaction "$BUY_OUTPUT" "Token Purchase"

sleep 2

# Test 3: Multiple Holders Scenario
log_message "INFO" "Test 3: Multiple Holders Scenario"
# User 1 buys tokens
GAS_COIN=$(get_gas_coin 100000)
if [ -z "$GAS_COIN" ]; then
    log_message "ERROR" "No gas coin with sufficient balance found for multiple holders test"
    exit 1
fi
log_message "INFO" "Using gas coin: $GAS_COIN for User 1"

USER1_OUTPUT=$(sui client call \
    --package "$PACKAGE_ID" \
    --module "launchpad" \
    --function "buy_tokens_with_sui_entry" \
    --args \
    "$CONFIG_ID" \
    "$LAUNCHPAD_ID" \
    "$GAS_COIN" \
    "$CLOCK_ID" \
    --gas-budget 100000000)

log_transaction "$USER1_OUTPUT" "User 1 Token Purchase"

sleep 2

# User 2 buys tokens
GAS_COIN=$(get_gas_coin 100000)
if [ -z "$GAS_COIN" ]; then
    log_message "ERROR" "No gas coin with sufficient balance found for final transaction"
    exit 1
fi
log_message "INFO" "Using gas coin: $GAS_COIN for User 2"

USER2_OUTPUT=$(sui client call \
    --package "$PACKAGE_ID" \
    --module "launchpad" \
    --function "buy_tokens_with_sui_entry" \
    --args \
    "$CONFIG_ID" \
    "$LAUNCHPAD_ID" \
    "$GAS_COIN" \
    "$CLOCK_ID" \
    --gas-budget 100000000)

log_transaction "$USER2_OUTPUT" "User 2 Token Purchase"

sleep 2

# Test 4: Check Launchpad Status
log_message "INFO" "Test 4: Checking Launchpad Status"
log_message "INFO" "=== Final Status Report ==="

# Check launchpad object status
LAUNCHPAD_STATUS=$(sui client object $LAUNCHPAD_ID)
log_message "INFO" "Launchpad Status:"
echo "$LAUNCHPAD_STATUS"

# Try to claim tokens (this should fail due to vesting)
log_message "INFO" "Attempting to claim tokens (should fail due to vesting)..."
CLAIM_OUTPUT=$(sui client call \
    --package "$PACKAGE_ID" \
    --module "launchpad" \
    --function "claim" \
    --args \
    "$LAUNCHPAD_ID" \
    "$CLOCK_ID" \
    --gas-budget 100000000 2>&1) || log_message "INFO" "Claim failed as expected (vesting period not elapsed)"

log_message "INFO" "Claim attempt result:"
echo "$CLAIM_OUTPUT"

# Verify events in indexer
log_message "INFO" "Verifying events in indexer..."
INDEXER_URL="http://localhost:3000"
if curl --output /dev/null --silent --head --fail "$INDEXER_URL"; then
    EVENTS_OUTPUT=$(curl -X GET "$INDEXER_URL/events?module=launchpad")
    log_message "INFO" "=== Indexer Events ==="
    echo "$EVENTS_OUTPUT"
    log_message "INFO" "=== End Indexer Events ==="
else
    log_message "ERROR" "Failed to connect to indexer at $INDEXER_URL"
fi

log_message "INFO" "Test scenarios completed"
