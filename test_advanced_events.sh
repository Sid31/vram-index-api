#!/bin/bash

# Colors for output
RED='\e[0;31m'
GREEN='\e[0;32m'
YELLOW='\e[1;33m'
NC='\e[0m'

# Configuration
PACKAGE_ID="0x64efefcc5a540d229a9ce7accb02b4724af1af9507ac914f99ff484dab51fa0b"
CONFIG_ID="0x5941a48bcca8fa8568678deadc53274b607bfa07905793df8d29640a431e3675"
LAUNCHPAD_ID="0xa50ccfcd28f779f33f75b533dc5ac0fe77eba0cd62220da19d20173711e8a560"
CLOCK_ID="0x6"
USER_ADDRESS=$(sui client active-address)

# Clean the output by removing version mismatch warnings
clean_output() {
    grep -v "Client/Server api version mismatch" | sed 's/^.*Transaction Effects: //g'
}

# Function to monitor events
monitor_events() {
    local event_type=$1
    echo -e "${YELLOW}Monitoring $event_type events...${NC}"
    
    sui client events --package $PACKAGE_ID --module launchpad --event-type $event_type 2>&1 | clean_output
}

# Monitor all new events
echo -e "${YELLOW}Starting Advanced Event Monitoring...${NC}"

# Monitor vesting claims
monitor_events "VestingClaimed"

# Monitor whitelist updates
monitor_events "WhitelistUpdated"

# Monitor pool stats
monitor_events "PoolStatsUpdated"

# Monitor user participation
monitor_events "UserParticipationStats"

echo -e "\n${YELLOW}Event Monitoring Complete${NC}"
