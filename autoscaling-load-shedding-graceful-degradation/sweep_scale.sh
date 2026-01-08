#!/bin/bash

set -e

RESULTS_DIR="sweep_results_$(date +%s)"
mkdir -p "$RESULTS_DIR"

echo "=== Parameter Sweep: Shed Thresholds ==="
echo "Results: $RESULTS_DIR"
echo ""

cleanup() {
    [ -n "$DISPATCHER_PID" ] && kill $DISPATCHER_PID 2>/dev/null
    [ -n "$AUTOSCALER_PID" ] && kill $AUTOSCALER_PID 2>/dev/null
    wait $DISPATCHER_PID 2>/dev/null || true
    wait $AUTOSCALER_PID 2>/dev/null || true
    sleep 1
}

run_test() {
    local SHED_THRESH=$1
    local TEST_NAME="shed${SHED_THRESH}"

    echo -n "Testing shed_threshold=$SHED_THRESH ... "

    cleanup

    # Start dispatcher
    POOL_SIZE=4 SHED_THRESHOLD=$SHED_THRESH DEGRADE_MODE=0 node dispatcher.js > /dev/null 2>&1 &
    DISPATCHER_PID=$!
    sleep 3

    # Start autoscaler
    node autoscaler.js > /dev/null 2>&1 &
    AUTOSCALER_PID=$!
    sleep 3

    if ! curl -s http://localhost:8080/health > /dev/null 2>&1; then
        echo "FAILED (startup)"
        return 1
    fi

    # Run short test
    wrk -t4 -c200 -d10s --latency http://localhost:8080/work > "$RESULTS_DIR/${TEST_NAME}_wrk.txt" 2>&1
    ./collect_metrics.sh "$RESULTS_DIR/${TEST_NAME}_metrics.json" > /dev/null 2>&1

    # Extract from wrk output (with defaults for missing values)
    local WRK_P50=$(grep "50%" "$RESULTS_DIR/${TEST_NAME}_wrk.txt" | awk '{print $2}' | tr -d '\n' || echo "N/A")
    local WRK_P90=$(grep "90%" "$RESULTS_DIR/${TEST_NAME}_wrk.txt" | awk '{print $2}' | tr -d '\n' || echo "N/A")
    local WRK_P99=$(grep "99%" "$RESULTS_DIR/${TEST_NAME}_wrk.txt" | awk '{print $2}' | tr -d '\n' || echo "N/A")
    local RPS=$(grep "Requests/sec" "$RESULTS_DIR/${TEST_NAME}_wrk.txt" | awk '{print $2}' | tr -d '\n' || echo "N/A")

    # Extract from metrics (with defaults)
    local INSTANCES=$(cat "$RESULTS_DIR/${TEST_NAME}_metrics.json" 2>/dev/null | jq -r '.dispatcher.dispatcher_active_instances // 0' || echo "0")
    local SHED_COUNT=$(cat "$RESULTS_DIR/${TEST_NAME}_metrics.json" 2>/dev/null | jq -r '[.api_instances[].api_shed_count] | add // 0' || echo "0")
    local APP_P95=$(cat "$RESULTS_DIR/${TEST_NAME}_metrics.json" 2>/dev/null | jq -r '.dispatcher.p95_estimate // 0' || echo "0")

    # Ensure no newlines in values
    WRK_P50=${WRK_P50//[$'\n\r']/}
    WRK_P90=${WRK_P90//[$'\n\r']/}
    WRK_P99=${WRK_P99//[$'\n\r']/}
    RPS=${RPS//[$'\n\r']/}

    echo "$SHED_THRESH,$WRK_P50,$WRK_P90,$WRK_P99,$RPS,$INSTANCES,$SHED_COUNT,$APP_P95" >> "$RESULTS_DIR/summary.csv"
    echo "done (p90=$WRK_P90, shed=$SHED_COUNT)"
}

# Create CSV header
echo "shed_threshold,p50,p90,p99,rps,instances,shed_count,app_p95" > "$RESULTS_DIR/summary.csv"

# Run tests with different thresholds
run_test 5
run_test 8
run_test 10
run_test 15
run_test 20

cleanup

echo ""
echo "╔════════════════════════════════════════════════════════════════════════════════════════════════════╗"
echo "║                                    SWEEP RESULTS                                                   ║"
echo "╠════════════════════════════════════════════════════════════════════════════════════════════════════╣"

# Print table header
printf "║ %-6s │ %-10s │ %-10s │ %-10s │ %-10s │ %-5s │ %-10s │ %-10s ║\n" "Thresh" "p50" "p90" "p99" "Req/sec" "Inst" "Shed Count" "App p95"
echo "╟────────┼────────────┼────────────┼────────────┼────────────┼───────┼────────────┼────────────╢"

# Print each row (strip any newlines/spaces)
tail -n +2 "$RESULTS_DIR/summary.csv" | while IFS=, read -r thresh p50 p90 p99 rps inst shed app_p95; do
    # Clean values
    thresh=$(echo "$thresh" | tr -d '\n\r' | xargs)
    p50=$(echo "$p50" | tr -d '\n\r' | xargs)
    p90=$(echo "$p90" | tr -d '\n\r' | xargs)
    p99=$(echo "$p99" | tr -d '\n\r' | xargs)
    rps=$(echo "$rps" | tr -d '\n\r' | xargs)
    inst=$(echo "$inst" | tr -d '\n\r' | xargs)
    shed=$(echo "$shed" | tr -d '\n\r' | xargs)
    app_p95=$(echo "$app_p95" | tr -d '\n\r' | xargs)

    # Only print if thresh is a number
    if [[ "$thresh" =~ ^[0-9]+$ ]]; then
        printf "║ %-6s │ %-10s │ %-10s │ %-10s │ %-10s │ %-5s │ %-10s │ %-10s ║\n" "$thresh" "$p50" "$p90" "$p99" "$rps" "$inst" "$shed" "${app_p95}ms"
    fi
done

echo "╚════════════════════════════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "📊 Analysis:"
echo "   - Lower shed threshold = more aggressive shedding"
echo "   - Compare 'Shed Count' vs 'p90/p99' to find optimal trade-off"
echo "   - 'App p95' is from application metrics (successful requests only)"
echo ""
echo "📁 Detailed results: $RESULTS_DIR/summary.csv"
