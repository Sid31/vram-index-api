#!/bin/bash

# Configuration
PACKAGE_ID="0x64efefcc5a540d229a9ce7accb02b4724af1af9507ac914f99ff484dab51fa0b"
CONFIG_ID="0x5941a48bcca8fa8568678deadc53274b607bfa07905793df8d29640a431e3675"
LAUNCHPAD_ID="0xa50ccfcd28f779f33f75b533dc5ac0fe77eba0cd62220da19d20173711e8a560"
CLOCK_ID="0x0000000000000000000000000000000000000000000000000000000000000006"

# Test Constants
INITIAL_PRICE=100000        # 0.0001 SUI per token
PRICE_INCREMENT=1000        # 0.000001 SUI increase per token
TARGET_POOL_SIZE=1000000000 # 1 SUI
NEW_CREATION_FEE=200000000

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
YELLOW='\033[1;33m'

# Test results counter
TESTS_PASSED=0
TESTS_FAILED=0

# Function to print test result
print_test_result() {
    local test_name=$1
    local result=$2
    local details=$3
    
    if [ "$result" -eq 0 ]; then
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗ FAIL${NC}: $test_name"
        if [ ! -z "$details" ]; then
            echo -e "Details: $details"
        fi
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Function to get gas coin
get_gas_coin() {
    local coin_id=$(sui client gas --json 2>/dev/null | jq -r '.[0].id // empty')
    if [ ! -z "$coin_id" ]; then
        echo "$coin_id"
        return 0
    fi
    return 1
}

# Function to clean the output by removing version mismatch warnings and extracting transaction status
clean_output() {
    grep -v "Client/Server api version mismatch" | sed 's/^.*Transaction Effects: //g'
}

# Function to execute test
run_test() {
    local test_name="$1"
    shift
    echo -e "\e[1;33mRunning Test: $test_name\e[0m"
    
    local output
    if output=$("$@" 2>&1); then
        echo -e "\e[0;32m✓ PASS\e[0m: $test_name"
        ((TESTS_PASSED++))
    else
        echo -e "\e[0;31m✗ FAIL\e[0m: $test_name"
        echo "Details: $output"
        ((TESTS_FAILED++))
    fi
}

# Test functions
test_update_creation_fee() {
    sui client call --package "$PACKAGE_ID" --module "launchpad" --function "update_creation_fee" \
        --args "$CONFIG_ID" 1000000 --gas-budget 10000000 2>&1 | clean_output
}

test_add_to_whitelist() {
    sui client call --package "$PACKAGE_ID" --module "launchpad" --function "add_to_whitelist" \
        --args "$CONFIG_ID" "$USER_ADDRESS" --gas-budget 10000000 2>&1 | clean_output
}

test_buy_tokens() {
    local gas_coin
    # Get a coin with sufficient balance (>= 1 SUI)
    gas_coin=$(sui client gas --json | jq -r '.[] | select(.suiBalance | tonumber >= 1) | .gasCoinId' | head -n 1)
    if [ -z "$gas_coin" ]; then
        echo "Failed to get payment coin with sufficient balance"
        return 1
    fi
    
    sui client call --package "$PACKAGE_ID" --module "launchpad" --function "buy_tokens" \
        --args "$LAUNCHPAD_ID" "$gas_coin" 1000000 --gas-budget 10000000 2>&1 | clean_output
}

test_deploy_liquidity() {
    sui client call --package "$PACKAGE_ID" --module "launchpad" --function "deploy_liquidity" \
        --args "$LAUNCHPAD_ID" --gas-budget 10000000 2>&1 | clean_output
}

test_move_liquidity() {
    sui client call --package "$PACKAGE_ID" --module "launchpad" --function "move_liquidity" \
        --args "$LAUNCHPAD_ID" --gas-budget 10000000 2>&1 | clean_output
}

test_pause_pool() {
    sui client call --package "$PACKAGE_ID" --module "launchpad" --function "pause_pool" \
        --args "$LAUNCHPAD_ID" --gas-budget 10000000 2>&1 | clean_output
}

test_unpause_pool() {
    sui client call --package "$PACKAGE_ID" --module "launchpad" --function "unpause_pool" \
        --args "$LAUNCHPAD_ID" --gas-budget 10000000 2>&1 | clean_output
}

# Additional test functions for new events

test_claim_vesting() {
    local user=$1
    sui client call --package "$PACKAGE_ID" --module "launchpad" --function "claim_tokens" \
        --args "$LAUNCHPAD_ID" "$CLOCK_ID" --gas-budget 10000000 2>&1 | clean_output
}

test_whitelist_batch() {
    local addresses=("$@")
    for address in "${addresses[@]}"; do
        sui client call --package "$PACKAGE_ID" --module "launchpad" --function "add_to_whitelist" \
            --args "$CONFIG_ID" "$LAUNCHPAD_ID" "$address" --gas-budget 10000000 2>&1 | clean_output
    done
}

test_update_pool_stats() {
    # This will trigger PoolStatsUpdated event
    sui client call --package "$PACKAGE_ID" --module "launchpad" --function "buy_tokens" \
        --args "$LAUNCHPAD_ID" "$GAS_COIN" 1000000 --gas-budget 10000000 2>&1 | clean_output
}

test_user_participation() {
    local user=$1
    local amount=$2
    local gas_coin
    gas_coin=$(sui client gas --json | jq -r '.[] | select(.suiBalance | tonumber >= 1) | .gasCoinId' | head -n 1)
    
    # Buy tokens to trigger UserParticipationStats event
    sui client call --package "$PACKAGE_ID" --module "launchpad" --function "buy_tokens" \
        --args "$LAUNCHPAD_ID" "$gas_coin" "$amount" --gas-budget 10000000 2>&1 | clean_output
}

# Main test sequence
echo -e "${YELLOW}Starting Launchpad Test Scenarios...${NC}"
echo "Package ID: $PACKAGE_ID"
echo "Config ID: $CONFIG_ID"
echo "Launchpad ID: $LAUNCHPAD_ID"

# Get active address
USER_ADDRESS=$(sui client active-address)
echo "Active address: $USER_ADDRESS"

# Test 1: Update Creation Fee
run_test "Update Creation Fee" test_update_creation_fee

# Test 2: Add to Whitelist
run_test "Add to Whitelist" test_add_to_whitelist

# Test 3: Buy Tokens
run_test "Buy Tokens" test_buy_tokens

# Test 4: Deploy Liquidity
run_test "Deploy Liquidity" test_deploy_liquidity

# Test 5: Move Liquidity
run_test "Move Liquidity" test_move_liquidity

# Test 6: Pause Pool
run_test "Pause Pool" test_pause_pool

# Test 7: Unpause Pool
run_test "Unpause Pool" test_unpause_pool

# Additional test scenarios
echo -e "\n${YELLOW}Running Additional Test Scenarios...${NC}"

# Test vesting claims
run_test "Vesting Claim" test_claim_vesting "$USER_ADDRESS"

# Test whitelist batch update
run_test "Whitelist Batch Update" test_whitelist_batch "$USER_ADDRESS" "0x123" "0x456"

# Test pool stats update
run_test "Pool Stats Update" test_update_pool_stats

# Test user participation
run_test "User Participation" test_user_participation "$USER_ADDRESS" 1000000

# Print test summary
echo -e "\n${YELLOW}Test Summary${NC}"
echo "Tests Passed: $TESTS_PASSED"
echo "Tests Failed: $TESTS_FAILED"

if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "\nSome tests failed. Check the output above for details."
    exit 1
fi
