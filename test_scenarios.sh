#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Package ID - Replace with your deployed package ID
PACKAGE_ID="YOUR_PACKAGE_ID"

# Test addresses
ADMIN_ADDRESS=$(sui client active-address)
echo "Admin address: $ADMIN_ADDRESS"

# Create new addresses for testing
USER_ADDRESS=$(sui client new-address ed25519 | grep "Created address" | awk '{print $3}')
echo "User address: $USER_ADDRESS"
USER2_ADDRESS=$(sui client new-address ed25519 | grep "Created address" | awk '{print $3}')
echo "User2 address: $USER2_ADDRESS"

# Fund test addresses
echo -e "${GREEN}Funding test addresses...${NC}"
sui client transfer-sui --amount 10000000000 --to $USER_ADDRESS --gas-budget 10000000
sui client transfer-sui --amount 10000000000 --to $USER2_ADDRESS --gas-budget 10000000

# Test 1: Initialize Launchpad
echo -e "${GREEN}Test 1: Initializing Launchpad...${NC}"
INIT_RESULT=$(sui client call --package $PACKAGE_ID --module launchpad --function init_for_testing --gas-budget 10000000)
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Launchpad initialized successfully${NC}"
else
    echo -e "${RED}✗ Failed to initialize launchpad${NC}"
    exit 1
fi

# Test 2: Update Creation Fee
echo -e "${GREEN}Test 2: Updating Creation Fee...${NC}"
sui client call --package $PACKAGE_ID --module launchpad --function update_creation_fee \
    --args \"$ADMIN_ADDRESS\" 200000000 --gas-budget 10000000

# Test 3: Create Launchpad Instance
echo -e "${GREEN}Test 3: Creating Launchpad Instance...${NC}"
sui client call --package $PACKAGE_ID --module launchpad --function create_launchpad \
    --args \"Test Token\" \"Test Description\" \"\" \"http://test.com\" \"\" \"\" 100000 1000 1000000000 true \
    --gas-budget 10000000

# Test 4: Add to Whitelist
echo -e "${GREEN}Test 4: Adding User to Whitelist...${NC}"
sui client call --package $PACKAGE_ID --module launchpad --function add_to_whitelist \
    --args \"$USER_ADDRESS\" --gas-budget 10000000

# Test 5: Buy Tokens (Whitelisted User)
echo -e "${GREEN}Test 5: Buying Tokens (Whitelisted User)...${NC}"
sui client call --package $PACKAGE_ID --module launchpad --function buy_tokens \
    --args 500000000 --gas-budget 10000000 --sender $USER_ADDRESS

# Test 6: Deploy Liquidity
echo -e "${GREEN}Test 6: Deploying Liquidity...${NC}"
sui client call --package $PACKAGE_ID --module launchpad --function deploy_liquidity \
    --gas-budget 10000000

# Test 7: Move Liquidity
echo -e "${GREEN}Test 7: Moving Liquidity...${NC}"
sui client call --package $PACKAGE_ID --module launchpad --function move_liquidity \
    --args \"$ADMIN_ADDRESS\" 100000000 --gas-budget 10000000

# Test 8: Pause Pool
echo -e "${GREEN}Test 8: Pausing Pool...${NC}"
sui client call --package $PACKAGE_ID --module launchpad --function pause_pool \
    --gas-budget 10000000

# Test 9: Try to Buy Tokens While Paused (Should Fail)
echo -e "${GREEN}Test 9: Attempting to Buy Tokens While Paused...${NC}"
sui client call --package $PACKAGE_ID --module launchpad --function buy_tokens \
    --args 500000000 --gas-budget 10000000 --sender $USER2_ADDRESS

# Test 10: Unpause Pool
echo -e "${GREEN}Test 10: Unpausing Pool...${NC}"
sui client call --package $PACKAGE_ID --module launchpad --function unpause_pool \
    --gas-budget 10000000

echo -e "${GREEN}All test scenarios completed!${NC}"
