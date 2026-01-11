#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

echo -e "${BOLD}${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║         Cache Stampede Demo - Results Analyzer             ║${NC}"
echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if results directory exists
if [ ! -d "results" ]; then
    echo -e "${RED}Error: results/ directory not found${NC}"
    echo "Run ./run_all_tests.sh first to generate test results"
    exit 1
fi

# Find the latest result files
NO_CACHE=$(ls -t results/no_cache_*.txt 2>/dev/null | head -1)
NAIVE=$(ls -t results/naive_cache_*.txt 2>/dev/null | head -1)
STAMPEDE=$(ls -t results/stampede_*.txt 2>/dev/null | head -1)
SINGLEFLIGHT=$(ls -t results/singleflight_*.txt 2>/dev/null | head -1)
NEGATIVE=$(ls -t results/negative_cache_*.txt 2>/dev/null | head -1)

# Check if we have results to analyze
FOUND=0
[ -n "$NO_CACHE" ] && FOUND=$((FOUND+1))
[ -n "$NAIVE" ] && FOUND=$((FOUND+1))
[ -n "$STAMPEDE" ] && FOUND=$((STAMPEDE+1))
[ -n "$SINGLEFLIGHT" ] && FOUND=$((FOUND+1))
[ -n "$NEGATIVE" ] && FOUND=$((FOUND+1))

if [ $FOUND -eq 0 ]; then
    echo -e "${RED}No test results found in results/ directory${NC}"
    echo "Run ./run_all_tests.sh first to generate test results"
    exit 1
fi

echo -e "${GREEN}Found $FOUND test result(s) to analyze${NC}"
echo ""

# Function to extract metrics
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

# Function to extract requests/sec
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

# Extract and display detailed comparison
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${CYAN}                        DETAILED METRICS COMPARISON${NC}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════════════════${NC}"
echo ""

# Table header
printf "${BOLD}┌─────────────────┬──────────┬──────────┬──────────┬───────────┬─────────────┬─────────────┬────────────┐${NC}\n"
printf "${BOLD}│ %-15s │ %-8s │ %-8s │ %-8s │ %-9s │ %-11s │ %-11s │ %-10s │${NC}\n" \
    "Test Mode" "p50" "p95" "p99" "Req/sec" "Cache Hits" "DB Calls" "Hit Rate %"
printf "${BOLD}├─────────────────┼──────────┼──────────┼──────────┼───────────┼─────────────┼─────────────┼────────────┤${NC}\n"

# Function to display row
display_row() {
    local name=$1
    local file=$2
    local color=$3

    if [ -f "$file" ]; then
        local p50=$(extract_wrk_latency "$file" "50")
        local p95=$(extract_wrk_latency "$file" "95")
        local p99=$(extract_wrk_latency "$file" "99")
        local rps=$(extract_rps "$file")
        local hits=$(extract_metric "$file" "cache_hits")
        local misses=$(extract_metric "$file" "cache_misses")
        local db_calls=$(extract_metric "$file" "downstream_calls")

        local hit_rate="N/A"
        if [ "$hits" != "0" ] && [ "$misses" != "0" ]; then
            hit_rate=$(awk "BEGIN {printf \"%.1f\", ($hits*100)/($hits+$misses)}")
        elif [ "$hits" -eq "0" ] && [ "$misses" -eq "0" ]; then
            hit_rate="N/A"
        fi

        printf "${color}│ %-15s │ %-8s │ %-8s │ %-8s │ %-9s │ %-11s │ %-11s │ %-10s │${NC}\n" \
            "$name" "$p50" "$p95" "$p99" "$rps" "$hits" "$db_calls" "$hit_rate"
    else
        printf "${color}│ %-15s │ %-8s │ %-8s │ %-8s │ %-9s │ %-11s │ %-11s │ %-10s │${NC}\n" \
            "$name" "N/A" "N/A" "N/A" "N/A" "N/A" "N/A" "N/A"
    fi
}

# Display rows
display_row "No Cache" "$NO_CACHE" ""
display_row "Naive Cache" "$NAIVE" "${GREEN}"
display_row "Stampede" "$STAMPEDE" "${RED}"
display_row "Singleflight" "$SINGLEFLIGHT" "${GREEN}"
display_row "Negative Cache" "$NEGATIVE" "${CYAN}"

printf "${BOLD}└─────────────────┴──────────┴──────────┴──────────┴───────────┴─────────────┴─────────────┴────────────┘${NC}\n"
echo ""

# Key observations
echo -e "${BOLD}${YELLOW}═══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${YELLOW}                           KEY OBSERVATIONS${NC}"
echo -e "${BOLD}${YELLOW}═══════════════════════════════════════════════════════════════════════════${NC}"
echo ""

# Observation 1: Baseline vs Cached
if [ -f "$NO_CACHE" ] && [ -f "$NAIVE" ]; then
    no_cache_db=$(extract_metric "$NO_CACHE" "downstream_calls")
    naive_db=$(extract_metric "$NAIVE" "downstream_calls")

    echo -e "${BOLD}1. Cache Benefit (No Cache → Naive Cache)${NC}"
    echo "   ─────────────────────────────────────────"
    if [ -n "$no_cache_db" ] && [ -n "$naive_db" ] && [ "$no_cache_db" != "0" ] && [ "$naive_db" != "0" ]; then
        if [ "$no_cache_db" -gt "$naive_db" ]; then
            reduction=$((no_cache_db - naive_db))
            pct=$(awk "BEGIN {printf \"%.1f\", (1-$naive_db/$no_cache_db)*100}")
            echo -e "   ${GREEN}✓ Reduced DB calls by $reduction ($pct%)${NC}"
            echo "   • Without cache: $no_cache_db DB calls"
            echo "   • With cache: $naive_db DB calls"
        else
            echo -e "   ${YELLOW}⚠ Cache didn't reduce DB load significantly${NC}"
        fi
    else
        echo -e "   ${YELLOW}⚠ Missing data for comparison${NC}"
    fi
    echo ""
fi

# Observation 2: Stampede Problem
if [ -f "$STAMPEDE" ]; then
    stampede_db=$(extract_metric "$STAMPEDE" "downstream_calls")
    stampede_p99=$(extract_wrk_latency "$STAMPEDE" "99")

    echo -e "${BOLD}2. Stampede Impact${NC}"
    echo "   ────────────────"
    echo -e "   ${RED}✗ Synchronized TTL expiry causes thundering herd${NC}"
    echo "   • Downstream calls during stampede: $stampede_db"
    echo "   • p99 latency during stampede: $stampede_p99"
    echo "   • Problem: All 400 concurrent requests miss cache simultaneously"
    echo ""
fi

# Observation 3: Singleflight Solution
if [ -f "$STAMPEDE" ] && [ -f "$SINGLEFLIGHT" ]; then
    stampede_db=$(extract_metric "$STAMPEDE" "downstream_calls")
    singleflight_db=$(extract_metric "$SINGLEFLIGHT" "downstream_calls")

    echo -e "${BOLD}3. Singleflight Protection${NC}"
    echo "   ───────────────────────"
    if [ -n "$stampede_db" ] && [ -n "$singleflight_db" ] && [ "$stampede_db" != "0" ] && [ "$singleflight_db" != "0" ]; then
        if [ "$stampede_db" -gt "$singleflight_db" ]; then
            reduction=$(awk "BEGIN {printf \"%.1f\", (1-$singleflight_db/$stampede_db)*100}")
            echo -e "   ${GREEN}✓ Reduced stampede DB calls by $reduction%${NC}"
            echo "   • Stampede: $stampede_db DB calls"
            echo "   • Singleflight: $singleflight_db DB calls"
            echo "   • Mechanism: Request coalescing (only 1 request per key fetches)"
        else
            echo -e "   ${YELLOW}⚠ Singleflight didn't reduce DB calls${NC}"
        fi
    else
        echo -e "   ${YELLOW}⚠ Could not compare (missing data)${NC}"
    fi
    echo ""
fi

# Observation 4: Negative Caching
if [ -f "$NEGATIVE" ]; then
    negative_hits=$(extract_metric "$NEGATIVE" "cache_hits")
    negative_db=$(extract_metric "$NEGATIVE" "downstream_calls")

    echo -e "${BOLD}4. Negative Caching (Error Response Caching)${NC}"
    echo "   ──────────────────────────────────────────"
    echo -e "   ${GREEN}✓ Prevents retry storms during failures${NC}"
    echo "   • Cache hits (including errors): $negative_hits"
    echo "   • Downstream calls: $negative_db"
    echo "   • Benefit: Errors cached for 1s, preventing repeated DB hammering"
    echo ""
fi

# Recommendations
echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${BLUE}                          PRODUCTION RECOMMENDATIONS${NC}"
echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${GREEN}✓ MUST HAVE:${NC}"
echo "  1. Request coalescing / Singleflight pattern"
echo "     → Prevents cache stampedes"
echo "     → Protects downstream from thundering herd"
echo ""
echo "  2. Negative caching for errors"
echo "     → Short TTL (1-5s) for failures"
echo "     → Prevents retry amplification"
echo ""
echo "  3. TTL jitter (±10-20%)"
echo "     → Prevents synchronized expiration"
echo "     → Spreads cache misses over time"
echo ""

echo -e "${YELLOW}⚠ IMPORTANT METRICS:${NC}"
echo "  • Don't rely solely on cache hit rate"
echo "  • Monitor p99 latency trends"
echo "  • Track downstream call spikes"
echo "  • Watch for temporal clustering of cache misses"
echo ""

echo -e "${RED}✗ AVOID:${NC}"
echo "  • Naive TTL-based caching in high-concurrency scenarios"
echo "  • Synchronized cache warming/population"
echo "  • Ignoring tail latency (p99, p999)"
echo ""

# File references
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${CYAN}                            RESULT FILES${NC}"
echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════════════════════════${NC}"
echo ""

[ -n "$NO_CACHE" ] && echo -e "  ${BLUE}No Cache:${NC}       $NO_CACHE"
[ -n "$NAIVE" ] && echo -e "  ${BLUE}Naive Cache:${NC}    $NAIVE"
[ -n "$STAMPEDE" ] && echo -e "  ${BLUE}Stampede:${NC}       $STAMPEDE"
[ -n "$SINGLEFLIGHT" ] && echo -e "  ${BLUE}Singleflight:${NC}   $SINGLEFLIGHT"
[ -n "$NEGATIVE" ] && echo -e "  ${BLUE}Negative Cache:${NC} $NEGATIVE"

echo ""
echo -e "${BOLD}${GREEN}Analysis complete!${NC}"
echo ""
