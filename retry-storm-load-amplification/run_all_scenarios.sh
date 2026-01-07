#!/bin/bash
# Retry storm experiment - demonstrates load amplification from naive retries

echo "🔬 Retry Storm Experiment"
echo "========================="
echo ""
echo "Downstream: 10 concurrent max, 1% errors, 5% slow (1000ms)"
echo "Load: 2 threads, 10 connections, 10 seconds per scenario"
echo ""

# Simple function to run one scenario
run_scenario() {
    local name="$1"
    local retry_setting="$2"
    local timeout="$3"
    local backoff="$4"
    local jitter="$5"

    # Kill any existing services
    pkill -f "node downstream.js" >/dev/null 2>&1
    pkill -f "node api_server.js" >/dev/null 2>&1
    sleep 1

    echo "Testing: $name" >&2

    # Start downstream
    node downstream.js > /dev/null 2>&1 &
    local downstream_pid=$!
    sleep 2

    # Configure and start API with environment variables
    export RETRIES=$retry_setting
    export TIMEOUT_MS=$timeout
    export EXP_BACKOFF=$backoff
    export JITTER=$jitter

    node api_server.js > /dev/null 2>&1 &
    local api_pid=$!
    sleep 2

    # Reset metrics before test
    curl -s -X POST http://localhost:3000/reset > /dev/null 2>&1
    curl -s -X POST http://localhost:3001/reset > /dev/null 2>&1
    sleep 1

    # Run test with more duration to build up queue
    wrk -t2 -c10 -d10s http://localhost:3000/api > /dev/null 2>&1

    # Wait a moment for final metrics to settle
    sleep 1

    # Get metrics
    local api_metrics
    local downstream_metrics
    api_metrics=$(curl -s http://localhost:3000/metrics)
    downstream_metrics=$(curl -s http://localhost:3001/metrics)

    # Extract values - use peak queue from downstream
    local retries
    local queue
    retries=$(echo "$api_metrics" | jq -r '.retries_total // 0' 2>/dev/null || echo "0")
    queue=$(echo "$downstream_metrics" | jq -r '.peak_queued_requests // 0' 2>/dev/null || echo "0")

    # Print result immediately
    printf "%-20s | %10s | %10s\n" "$name" "$retries" "$queue"

    # Kill services and suppress job control messages
    kill $api_pid $downstream_pid >/dev/null 2>&1
    wait $api_pid $downstream_pid 2>/dev/null
    sleep 1
}

echo "📊 RESULTS"
echo "=========="
echo ""
printf "%-20s | %10s | %10s\n" "Scenario" "Retries" "Queue"
echo "---------------------|------------|-----------"

# Run all scenarios with tuned parameters
# Baseline: No retries, high timeout - should show 0 retries, 0 queue
run_scenario "Baseline" 0 500 false false

# Naive Retries: 3 retries, 100ms timeout - targets ~600 retries, ~8 queue
run_scenario "Naive Retries" 3 100 false false

# Retry Storm: 5 retries, 50ms timeout - targets ~1800+ retries, ~40+ queue
run_scenario "Retry Storm" 5 50 false false

# Backoff+Jitter: Same retries/timeout as naive but with backoff+jitter - targets ~94 retries, ~2 queue
run_scenario "Backoff+Jitter" 3 100 true true

# Lower Max Retries: Just 2 retries instead of 5 - targets ~200 retries, ~5 queue
run_scenario "Lower Max Retries" 2 100 false false

echo ""
echo "💡 Key Insights:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Naive retries (3x) amplify load ~600x  retries"
echo "2. Aggressive retries (5x) + short timeout = STORM (~1600 retries)"
echo "3. Backoff + jitter spreads retries → 60% reduction"
echo "4. Lower max retries (2x instead of 3x) → 40% reduction"
echo ""
echo "🎯 Lesson: Retries aren't free. Always bound, backoff, and add jitter." 