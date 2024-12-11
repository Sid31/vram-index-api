#!/bin/bash

# Configuration
PACKAGE_ID="0x64efefcc5a540d229a9ce7accb02b4724af1af9507ac914f99ff484dab51fa0b"
CONFIG_ID="0x5941a48bcca8fa8568678deadc53274b607bfa07905793df8d29640a431e3675"
LAUNCHPAD_ID="0xa50ccfcd28f779f33f75b533dc5ac0fe77eba0cd62220da19d20173711e8a560"
CLOCK_ID="0x0000000000000000000000000000000000000000000000000000000000000006"  # System clock object ID

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color
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
        echo -e "${YELLOW}Details${NC}: $details"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Function to check launchpad state
check_launchpad_state() {
    local expected_state=$1
    local state_output=$(sui client object $LAUNCHPAD_ID)
    
    if echo "$state_output" | grep -q "is_active.*$expected_state"; then
        return 0
    else
        return 1
    fi
}

# Function to call pause_pool
call_pause_pool() {
    echo "Calling pause_pool..."
    local output=$(sui client call \
        --package $PACKAGE_ID \
        --module launchpad \
        --function pause_pool \
        --args $CONFIG_ID $LAUNCHPAD_ID $CLOCK_ID \
        --gas-budget 10000000 2>&1)
    
    local exit_code=$?
    echo "$output"
    return $exit_code
}

# Function to call unpause_pool
call_unpause_pool() {
    echo "Calling unpause_pool..."
    local output=$(sui client call \
        --package $PACKAGE_ID \
        --module launchpad \
        --function unpause_pool \
        --args $CONFIG_ID $LAUNCHPAD_ID $CLOCK_ID \
        --gas-budget 10000000 2>&1)
    
    local exit_code=$?
    echo "$output"
    return $exit_code
}

# Function to run a test case
run_test_case() {
    local test_name=$1
    local action=$2
    local expected_state=$3
    
    echo -e "\n${YELLOW}Running Test: $test_name${NC}"
    
    if [ "$action" = "pause" ]; then
        call_pause_pool
        local call_result=$?
    else
        call_unpause_pool
        local call_result=$?
    fi
    
    # Wait for transaction to be processed
    sleep 2
    
    # Verify state
    check_launchpad_state $expected_state
    local state_result=$?
    
    if [ $call_result -eq 0 ] && [ $state_result -eq 0 ]; then
        print_test_result "$test_name" 0 "Success"
    else
        print_test_result "$test_name" 1 "Function call result: $call_result, State verification: $state_result"
    fi
}

# Main test sequence
echo -e "${YELLOW}Starting Launchpad Pause/Unpause Tests...${NC}"
echo "Package ID: $PACKAGE_ID"
echo "Config ID: $CONFIG_ID"
echo "Launchpad ID: $LAUNCHPAD_ID"
echo "Clock ID: $CLOCK_ID"

# Initial state check
echo -e "\n${YELLOW}Checking initial state...${NC}"
check_launchpad_state "false"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Initial state verified: Pool is paused${NC}"
else
    echo -e "${RED}Initial state check failed${NC}"
    exit 1
fi

# Test cases
run_test_case "Test 1: Unpause Pool" "unpause" "true"
sleep 2

run_test_case "Test 2: Pause Pool" "pause" "false"
sleep 2

run_test_case "Test 3: Unpause Pool Again" "unpause" "true"
sleep 2

run_test_case "Test 4: Final Pause" "pause" "false"

# Print test summary
echo -e "\n${YELLOW}Test Summary${NC}"
echo -e "${GREEN}Tests Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Tests Failed: $TESTS_FAILED${NC}"

# Set exit code based on test results
if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "\n${GREEN}All tests passed successfully!${NC}"
    exit 0
else
    echo -e "\n${RED}Some tests failed. Check the output above for details.${NC}"
    exit 1
fi
