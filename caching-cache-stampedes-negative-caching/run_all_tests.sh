#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
BOLD='\033[1m'

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SUMMARY_FILE="results/summary_${TIMESTAMP}.txt"

echo -e "${BOLD}${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║     Cache Stampede Demo - Complete Test Suite              ║${NC}"
echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Timestamp: $(date)${NC}"
echo -e "${YELLOW}Results will be saved to individual test files + summary${NC}"
echo ""

# Create results directory if it doesn't exist
mkdir -p results

# Function to extract metrics from a result file
extract_metric() {
    local file="$1"
    local pattern="$2"
    local default="${3:-0}"

    if [ -f "$file" ]; then
        # Match lines like "metric_name NUMBER" and extract just the number
        local value=$(grep "^${pattern} [0-9]" "$file" | tail -1 | awk '{print $2}')
        if [ -n "$value" ] && [ "$value" != "" ]; then
            echo "$value"
        else
            echo "$default"
        fi
    else
        echo "$default"
    fi
}

# Function to extract latency from wrk output
extract_wrk_latency() {
    local file="$1"
    local percentile="$2"

    if [ -f "$file" ]; then
        local value=$(grep "^[[:space:]]*${percentile}%" "$file" | awk '{print $2}' | head -1)
        if [ -n "$value" ]; then
            echo "$value"
        else
            echo "N/A"
        fi
    else
        echo "N/A"
    fi
}

# Function to extract requests/sec from wrk output
extract_rps() {
    local file="$1"

    if [ -f "$file" ]; then
        local value=$(grep "Requests/sec:" "$file" | awk '{print $2}' | head -1)
        if [ -n "$value" ]; then
            echo "$value"
        else
            echo "N/A"
        fi
    else
        echo "N/A"
    fi
}

# Array to store test results
declare -A test_files

echo -e "${BOLD}${GREEN}[1/5] Running No Cache Test...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
./run_no_cache.sh
test_files[no_cache]=$(ls -t results/no_cache_*.txt | head -1)
echo ""
sleep 3

echo -e "${BOLD}${GREEN}[2/5] Running Naive Cache Test...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
./run_naive_cache.sh
test_files[naive]=$(ls -t results/naive_cache_*.txt | head -1)
echo ""
sleep 3

echo -e "${BOLD}${GREEN}[3/5] Running Stampede Test...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
./run_stampede.sh
test_files[stampede]=$(ls -t results/stampede_*.txt | head -1)
echo ""
sleep 3

echo -e "${BOLD}${GREEN}[4/5] Running Singleflight Test...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
./run_singleflight.sh
test_files[singleflight]=$(ls -t results/singleflight_*.txt | head -1)
echo ""
sleep 3

echo -e "${BOLD}${GREEN}[5/5] Running Negative Cache Test...${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
./run_negative_cache.sh
test_files[negative]=$(ls -t results/negative_cache_*.txt | head -1)
echo ""

echo -e "${BOLD}${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║           Analyzing Results and Generating Summary         ║${NC}"
echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Extract metrics from all tests
declare -A metrics

# No Cache
metrics[no_cache_p50]=$(extract_wrk_latency "${test_files[no_cache]}" "50")
metrics[no_cache_p99]=$(extract_wrk_latency "${test_files[no_cache]}" "99")
metrics[no_cache_rps]=$(extract_rps "${test_files[no_cache]}")
metrics[no_cache_downstream]=$(extract_metric "${test_files[no_cache]}" "downstream_calls")
metrics[no_cache_cache_hits]=$(extract_metric "${test_files[no_cache]}" "cache_hits")

# Naive Cache
metrics[naive_p50]=$(extract_wrk_latency "${test_files[naive]}" "50")
metrics[naive_p99]=$(extract_wrk_latency "${test_files[naive]}" "99")
metrics[naive_rps]=$(extract_rps "${test_files[naive]}")
metrics[naive_downstream]=$(extract_metric "${test_files[naive]}" "downstream_calls")
metrics[naive_cache_hits]=$(extract_metric "${test_files[naive]}" "cache_hits")
metrics[naive_cache_misses]=$(extract_metric "${test_files[naive]}" "cache_misses")

# Stampede
metrics[stampede_p50]=$(extract_wrk_latency "${test_files[stampede]}" "50")
metrics[stampede_p99]=$(extract_wrk_latency "${test_files[stampede]}" "99")
metrics[stampede_rps]=$(extract_rps "${test_files[stampede]}")
metrics[stampede_downstream]=$(extract_metric "${test_files[stampede]}" "downstream_calls")
metrics[stampede_cache_hits]=$(extract_metric "${test_files[stampede]}" "cache_hits")
metrics[stampede_cache_misses]=$(extract_metric "${test_files[stampede]}" "cache_misses")

# Singleflight
metrics[singleflight_p50]=$(extract_wrk_latency "${test_files[singleflight]}" "50")
metrics[singleflight_p99]=$(extract_wrk_latency "${test_files[singleflight]}" "99")
metrics[singleflight_rps]=$(extract_rps "${test_files[singleflight]}")
metrics[singleflight_downstream]=$(extract_metric "${test_files[singleflight]}" "downstream_calls")
metrics[singleflight_cache_hits]=$(extract_metric "${test_files[singleflight]}" "cache_hits")
metrics[singleflight_cache_misses]=$(extract_metric "${test_files[singleflight]}" "cache_misses")
metrics[singleflight_inflight]=$(extract_metric "${test_files[singleflight]}" "in_flight_loads")

# Negative Cache
metrics[negative_p50]=$(extract_wrk_latency "${test_files[negative]}" "50")
metrics[negative_p99]=$(extract_wrk_latency "${test_files[negative]}" "99")
metrics[negative_rps]=$(extract_rps "${test_files[negative]}")
metrics[negative_downstream]=$(extract_metric "${test_files[negative]}" "downstream_calls")
metrics[negative_cache_hits]=$(extract_metric "${test_files[negative]}" "cache_hits")
metrics[negative_cache_misses]=$(extract_metric "${test_files[negative]}" "cache_misses")

# Generate summary report
{
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "                     CACHE STAMPEDE DEMO - TEST SUMMARY"
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo ""
    echo "Test Run: $(date)"
    echo "Summary File: $SUMMARY_FILE"
    echo ""
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "                           PERFORMANCE COMPARISON"
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo ""
    printf "┌─────────────────┬──────────┬──────────┬───────────┬─────────────┬─────────────┐\n"
    printf "│ %-15s │ %-8s │ %-8s │ %-9s │ %-11s │ %-11s │\n" "Test Mode" "p50" "p99" "Req/sec" "Cache Hits" "DB Calls"
    printf "├─────────────────┼──────────┼──────────┼───────────┼─────────────┼─────────────┤\n"
    printf "│ %-15s │ %-8s │ %-8s │ %-9s │ %-11s │ %-11s │\n" \
        "No Cache" \
        "${metrics[no_cache_p50]}" \
        "${metrics[no_cache_p99]}" \
        "${metrics[no_cache_rps]}" \
        "${metrics[no_cache_cache_hits]}" \
        "${metrics[no_cache_downstream]}"
    printf "│ %-15s │ %-8s │ %-8s │ %-9s │ %-11s │ %-11s │\n" \
        "Naive Cache" \
        "${metrics[naive_p50]}" \
        "${metrics[naive_p99]}" \
        "${metrics[naive_rps]}" \
        "${metrics[naive_cache_hits]}" \
        "${metrics[naive_downstream]}"
    printf "│ %-15s │ %-8s │ %-8s │ %-9s │ %-11s │ %-11s │\n" \
        "Stampede" \
        "${metrics[stampede_p50]}" \
        "${metrics[stampede_p99]}" \
        "${metrics[stampede_rps]}" \
        "${metrics[stampede_cache_hits]}" \
        "${metrics[stampede_downstream]}"
    printf "│ %-15s │ %-8s │ %-8s │ %-9s │ %-11s │ %-11s │\n" \
        "Singleflight" \
        "${metrics[singleflight_p50]}" \
        "${metrics[singleflight_p99]}" \
        "${metrics[singleflight_rps]}" \
        "${metrics[singleflight_cache_hits]}" \
        "${metrics[singleflight_downstream]}"
    printf "│ %-15s │ %-8s │ %-8s │ %-9s │ %-11s │ %-11s │\n" \
        "Negative Cache" \
        "${metrics[negative_p50]}" \
        "${metrics[negative_p99]}" \
        "${metrics[negative_rps]}" \
        "${metrics[negative_cache_hits]}" \
        "${metrics[negative_downstream]}"
    printf "└─────────────────┴──────────┴──────────┴───────────┴─────────────┴─────────────┘\n"

    echo ""
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "                              KEY FINDINGS"
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo ""

    # Analysis 1: Cache benefit
    echo "1. CACHE EFFECTIVENESS"
    echo "   ────────────────────"
    echo "   • No Cache served: ${metrics[no_cache_downstream]} DB calls"
    echo "   • Naive Cache saved: $((${metrics[naive_downstream]} < ${metrics[no_cache_downstream]} ? ${metrics[no_cache_downstream]}-${metrics[naive_downstream]} : 0)) DB calls"
    if [ "${metrics[naive_cache_hits]}" -gt 0 ]; then
        hit_rate=$(awk "BEGIN {printf \"%.1f\", (${metrics[naive_cache_hits]}*100)/(${metrics[naive_cache_hits]}+${metrics[naive_cache_misses]})}")
        echo "   • Cache hit rate: ${hit_rate}%"
    fi
    echo ""

    # Analysis 2: Stampede impact
    echo "2. STAMPEDE IMPACT (Naive Cache with synchronized TTL expiry)"
    echo "   ────────────────────────────────────────────────────────────"
    echo "   • Downstream calls during stampede: ${metrics[stampede_downstream]}"
    echo "   • p99 latency spike: ${metrics[stampede_p99]}"
    echo "   • Problem: All concurrent requests hit expired cache simultaneously"
    echo "   • Result: Thundering herd overwhelms downstream database"
    echo ""

    # Analysis 3: Singleflight protection
    echo "3. SINGLEFLIGHT PROTECTION"
    echo "   ────────────────────────"
    stampede_db=${metrics[stampede_downstream]}
    singleflight_db=${metrics[singleflight_downstream]}
    if [ "$stampede_db" -gt 0 ] && [ "$singleflight_db" -gt 0 ]; then
        reduction=$(awk "BEGIN {printf \"%.1f\", (1-$singleflight_db/$stampede_db)*100}")
        echo "   • Downstream calls reduced by: ${reduction}%"
        echo "   • Stampede DB calls: ${stampede_db}"
        echo "   • Singleflight DB calls: ${singleflight_db}"
        echo "   • Protection mechanism: Only 1 request per key loads from DB"
        echo "   • Others wait for the result (request coalescing)"
    fi
    echo ""

    # Analysis 4: Negative caching
    echo "4. NEGATIVE CACHING (Error Response Caching)"
    echo "   ──────────────────────────────────────────"
    echo "   • Errors cached for 1 second to prevent retry storms"
    echo "   • Downstream calls: ${metrics[negative_downstream]}"
    echo "   • Cache hits (including errors): ${metrics[negative_cache_hits]}"
    echo "   • Benefit: Prevents hammering DB during partial outages"
    echo ""

    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "                                 RECOMMENDATIONS"
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo ""
    echo "✓ ALWAYS use request coalescing/singleflight for production caches"
    echo "  - Prevents stampedes during cache misses"
    echo "  - Protects downstream systems from thundering herd"
    echo ""
    echo "✓ IMPLEMENT negative caching for error responses"
    echo "  - Short TTL (1-5 seconds) for failures"
    echo "  - Prevents retry amplification during outages"
    echo ""
    echo "✓ ADD TTL jitter to prevent synchronized expiration"
    echo "  - Random offset: TTL ± 10-20%"
    echo "  - Spreads out cache misses over time"
    echo ""
    echo "✗ DON'T rely solely on cache hit rate as a metric"
    echo "  - Temporal distribution of misses matters more"
    echo "  - Monitor p99 latency and downstream call spikes"
    echo ""
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo ""
    echo "Individual test results:"
    echo "  • No Cache:       ${test_files[no_cache]}"
    echo "  • Naive Cache:    ${test_files[naive]}"
    echo "  • Stampede:       ${test_files[stampede]}"
    echo "  • Singleflight:   ${test_files[singleflight]}"
    echo "  • Negative Cache: ${test_files[negative]}"
    echo ""
    echo "════════════════════════════════════════════════════════════════════════════════"

} | tee "$SUMMARY_FILE"

echo ""
echo -e "${BOLD}${GREEN}✓ All tests complete!${NC}"
echo -e "${YELLOW}Summary saved to: ${SUMMARY_FILE}${NC}"
echo ""
echo -e "${BLUE}Quick comparison commands:${NC}"
echo -e "  cat $SUMMARY_FILE"
echo -e "  grep 'downstream_calls' results/*_${TIMESTAMP}.txt"
echo ""
