#!/bin/bash

# Quick comparison script for stampede vs singleflight
# Useful for demonstrations and blog posts

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${BLUE}     Quick Comparison: Stampede vs Singleflight Protection${NC}"
echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
echo ""

# Find latest files
STAMPEDE=$(ls -t results/stampede_*.txt 2>/dev/null | head -1)
SINGLEFLIGHT=$(ls -t results/singleflight_*.txt 2>/dev/null | head -1)

if [ -z "$STAMPEDE" ] || [ -z "$SINGLEFLIGHT" ]; then
    echo -e "${YELLOW}Missing test results. Running both tests now...${NC}"
    echo ""

    echo -e "${RED}[1/2] Running stampede test...${NC}"
    ./run_stampede.sh > /dev/null 2>&1
    STAMPEDE=$(ls -t results/stampede_*.txt | head -1)
    echo -e "${GREEN}✓ Complete${NC}"
    echo ""

    echo -e "${GREEN}[2/2] Running singleflight test...${NC}"
    ./run_singleflight.sh > /dev/null 2>&1
    SINGLEFLIGHT=$(ls -t results/singleflight_*.txt | head -1)
    echo -e "${GREEN}✓ Complete${NC}"
    echo ""
fi

# Extract metrics
extract_metric() {
    local file="$1"
    local pattern="$2"
    # Match lines like "metric_name NUMBER" and extract just the number
    grep "^${pattern} [0-9]" "$file" | tail -1 | awk '{print $2}' || echo "0"
}

extract_latency() {
    grep "$2%" "$1" | awk '{print $2}' | head -1 || echo "N/A"
}

# Stampede metrics
ST_P50=$(extract_latency "$STAMPEDE" "50")
ST_P99=$(extract_latency "$STAMPEDE" "99")
ST_DB=$(extract_metric "$STAMPEDE" "downstream_calls")
ST_HITS=$(extract_metric "$STAMPEDE" "cache_hits")
ST_MISSES=$(extract_metric "$STAMPEDE" "cache_misses")

# Singleflight metrics
SF_P50=$(extract_latency "$SINGLEFLIGHT" "50")
SF_P99=$(extract_latency "$SINGLEFLIGHT" "99")
SF_DB=$(extract_metric "$SINGLEFLIGHT" "downstream_calls")
SF_HITS=$(extract_metric "$SINGLEFLIGHT" "cache_hits")
SF_MISSES=$(extract_metric "$SINGLEFLIGHT" "cache_misses")
SF_INFLIGHT=$(extract_metric "$SINGLEFLIGHT" "in_flight_loads")

# Display comparison
echo -e "${BOLD}┌─────────────────────────┬────────────────┬────────────────┬──────────────┐${NC}"
echo -e "${BOLD}│ Metric                  │ Stampede       │ Singleflight   │ Improvement  │${NC}"
echo -e "${BOLD}├─────────────────────────┼────────────────┼────────────────┼──────────────┤${NC}"

# p50 latency
printf "│ ${BOLD}p50 Latency${NC}             │ %-14s │ %-14s │ %-12s │\n" "$ST_P50" "$SF_P50" "~same"

# p99 latency
if [ "$ST_P99" != "N/A" ] && [ "$SF_P99" != "N/A" ]; then
    echo -e "│ ${BOLD}p99 Latency${NC}             │ ${RED}%-14s${NC} │ ${GREEN}%-14s${NC} │ ${GREEN}✓ Lower${NC}      │" "$ST_P99" "$SF_P99"
else
    printf "│ ${BOLD}p99 Latency${NC}             │ %-14s │ %-14s │ %-12s │\n" "$ST_P99" "$SF_P99" "N/A"
fi

# Downstream calls (key metric!)
if [ "$ST_DB" -gt 0 ] && [ "$SF_DB" -gt 0 ]; then
    reduction=$(awk "BEGIN {printf \"%.0f\", (1-$SF_DB/$ST_DB)*100}")
    echo -e "│ ${BOLD}Downstream DB Calls${NC}     │ ${RED}%-14s${NC} │ ${GREEN}%-14s${NC} │ ${GREEN}✓ -${reduction}%%${NC}      │" "$ST_DB" "$SF_DB"
else
    printf "│ ${BOLD}Downstream DB Calls${NC}     │ %-14s │ %-14s │ %-12s │\n" "$ST_DB" "$SF_DB" "N/A"
fi

# Cache hits
printf "│ Cache Hits              │ %-14s │ %-14s │ %-12s │\n" "$ST_HITS" "$SF_HITS" "~same"

# Cache misses
printf "│ Cache Misses            │ %-14s │ %-14s │ %-12s │\n" "$ST_MISSES" "$SF_MISSES" "~same"

# In-flight loads (singleflight only)
echo -e "│ In-Flight Loads         │ ${YELLOW}N/A${NC}            │ ${GREEN}%-14s${NC} │ ${GREEN}✓ Limited${NC}    │" "$SF_INFLIGHT"

echo -e "${BOLD}└─────────────────────────┴────────────────┴────────────────┴──────────────┘${NC}"

echo ""
echo -e "${BOLD}${YELLOW}KEY INSIGHT:${NC}"
echo ""

if [ "$ST_DB" -gt 0 ] && [ "$SF_DB" -gt 0 ]; then
    reduction=$(awk "BEGIN {printf \"%.0f\", (1-$SF_DB/$ST_DB)*100}")
    amplification=$(awk "BEGIN {printf \"%.1f\", $ST_DB/$SF_DB}")

    echo -e "  ${RED}Problem (Stampede):${NC}"
    echo -e "    • ${BOLD}$ST_DB${NC} database calls during cache miss"
    echo -e "    • All 400 concurrent requests triggered separate DB queries"
    echo -e "    • Thundering herd overwhelmed downstream"
    echo ""
    echo -e "  ${GREEN}Solution (Singleflight):${NC}"
    echo -e "    • ${BOLD}$SF_DB${NC} database calls (${BOLD}${reduction}% reduction${NC})"
    echo -e "    • Only ${BOLD}~1 request per cache miss${NC} actually loads from DB"
    echo -e "    • Other ${BOLD}399 requests${NC} wait for the first one (coalescing)"
    echo -e "    • DB load reduced by ${BOLD}${amplification}x${NC}"
    echo ""
    echo -e "  ${BLUE}This is why singleflight is CRITICAL for production caches.${NC}"
else
    echo -e "  ${YELLOW}Run ./run_stampede.sh and ./run_singleflight.sh to see the comparison${NC}"
fi

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Files analyzed:"
echo "  Stampede:     $STAMPEDE"
echo "  Singleflight: $SINGLEFLIGHT"
echo ""
